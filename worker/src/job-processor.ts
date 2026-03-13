/**
 * Job Processor
 * Downloads EA, generates configs, runs MT5, parses results, uploads to Firestore.
 */

import * as fs from 'fs';
import * as path from 'path';
import { getDb, getBucket, admin } from './firebase';
import { COLLECTIONS, FIRESTORE_BATCH_LIMIT } from '@algo-trading/shared';
import type { OptimizationJob, StrategyVersion, SymbolMapping, OptimizationPass } from '@algo-trading/shared';
import {
  translateSymbol,
  generateIniContent,
  generateSetContent,
  writeIniFile,
  writeSetFile,
} from './config-generator';
import { runMT5 } from './mt5-runner';
import { parseResults, computeSummary, cleanupResults } from './result-parser';

/**
 * Process a single optimization job end-to-end
 */
export async function processJob(
  jobId: string,
  job: OptimizationJob,
  workerId: string,
  mt5Path: string,
  symbolMapping: SymbolMapping,
  maxJobDurationMs: number,
): Promise<void> {
  const db = getDb();
  const jobRef = db.collection(COLLECTIONS.OPTIMIZATION_JOBS).doc(jobId);

  // 1. Update job status to running
  await jobRef.update({
    status: 'running',
    startedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Update worker's current job
  await db.collection(COLLECTIONS.WORKERS).doc(workerId).update({
    currentJobId: jobId,
  });

  const startTime = Date.now();
  let tempFiles: string[] = [];

  try {
    // 2. Get strategy version details (for inputs)
    const versionDoc = await db.collection(COLLECTIONS.STRATEGIES)
      .doc(job.strategyName)
      .collection('versions')
      .doc(String(job.strategyVersion))
      .get();

    if (!versionDoc.exists) {
      throw new Error(`Strategy version not found: ${job.strategyName} v${job.strategyVersion}`);
    }

    const version = versionDoc.data() as StrategyVersion;

    // 3. Download .ex5 from Firebase Storage
    const eaFileName = `${job.strategyName}.ex5`;
    const eaLocalPath = path.join(mt5Path, 'MQL5', 'Experts', eaFileName);

    console.log(`  Downloading ${version.ex5StoragePath}...`);
    const bucket = getBucket();
    const file = bucket.file(version.ex5StoragePath);
    const [contents] = await file.download();
    fs.writeFileSync(eaLocalPath, contents);
    tempFiles.push(eaLocalPath);

    // 4. Translate symbol for this broker
    const brokerSymbol = translateSymbol(job.symbol, symbolMapping);
    console.log(`  Symbol: ${job.symbol} → ${brokerSymbol}`);

    // 5. Generate .ini and .set files
    const iniFileName = `job_${jobId}.ini`;
    const setFileName = `job_${jobId}.set`;
    const testerDir = path.join(mt5Path, 'MQL5', 'Profiles', 'Tester');

    // Ensure Tester directory exists
    if (!fs.existsSync(testerDir)) {
      fs.mkdirSync(testerDir, { recursive: true });
    }

    const iniPath = path.join(testerDir, iniFileName);
    const setPath = path.join(testerDir, setFileName);

    const iniContent = generateIniContent(job, brokerSymbol, eaFileName, setFileName);
    const setContent = generateSetContent(version.inputs || [], job.inputOverrides || {});

    writeIniFile(iniPath, iniContent);
    writeSetFile(setPath, setContent);
    tempFiles.push(iniPath, setPath);

    console.log(`  Config generated: ${iniFileName}, ${setFileName}`);

    // 6. Clean up any old result files before running
    cleanupResults(mt5Path);

    // 7. Run MT5
    console.log(`  Starting MT5 optimization...`);
    const result = await runMT5(mt5Path, iniPath, jobId, maxJobDurationMs);

    if (result.cancelled) {
      await jobRef.update({
        status: 'cancelled',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        duration: Math.round(result.durationMs / 1000),
      });
      return;
    }

    if (result.timedOut) {
      throw new Error(`Timeout after ${Math.round(maxJobDurationMs / 3600000)} hours`);
    }

    // 8. Parse results
    console.log(`  Parsing results...`);
    const passes = parseResults(mt5Path);
    console.log(`  Found ${passes.length} qualifying passes`);

    // 9. Upload passes to Firestore (batched)
    if (passes.length > 0) {
      await uploadPasses(db, jobId, passes);
    }

    // 10. Compute and save summary
    const summary = computeSummary(passes);
    const duration = Math.round((Date.now() - startTime) / 1000);

    await jobRef.update({
      status: 'completed',
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      duration,
      resultSummary: summary,
    });

    // Update worker stats
    const workerRef = db.collection(COLLECTIONS.WORKERS).doc(workerId);
    await workerRef.update({
      'stats.jobsCompleted': admin.firestore.FieldValue.increment(1),
      'stats.totalRuntime': admin.firestore.FieldValue.increment(duration),
    });

    console.log(`  Job ${jobId} completed: ${passes.length} passes, ${duration}s`);

  } catch (err) {
    const duration = Math.round((Date.now() - startTime) / 1000);
    const errorMsg = err instanceof Error ? err.message : String(err);

    await jobRef.update({
      status: 'failed',
      error: errorMsg.substring(0, 1000),
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      duration,
    });

    // Update worker failed stats
    await db.collection(COLLECTIONS.WORKERS).doc(workerId).update({
      'stats.jobsFailed': admin.firestore.FieldValue.increment(1),
    });

    throw err;
  } finally {
    // 11. Cleanup
    for (const f of tempFiles) {
      try {
        if (fs.existsSync(f)) fs.unlinkSync(f);
      } catch { /* ignore */ }
    }
    cleanupResults(mt5Path);

    // Clear worker's current job
    await db.collection(COLLECTIONS.WORKERS).doc(workerId).update({
      currentJobId: null,
    }).catch(() => {});
  }
}

/**
 * Upload optimization passes to Firestore in batches
 */
async function uploadPasses(
  db: FirebaseFirestore.Firestore,
  jobId: string,
  passes: OptimizationPass[],
): Promise<void> {
  const batchSize = FIRESTORE_BATCH_LIMIT - 10; // Leave room for safety
  let uploaded = 0;

  for (let i = 0; i < passes.length; i += batchSize) {
    const chunk = passes.slice(i, i + batchSize);
    const batch = db.batch();

    for (let j = 0; j < chunk.length; j++) {
      const passRef = db.collection(COLLECTIONS.OPTIMIZATION_RESULTS)
        .doc(jobId)
        .collection('passes')
        .doc(String(i + j));

      batch.set(passRef, chunk[j]);
    }

    await batch.commit();
    uploaded += chunk.length;
    console.log(`  Uploaded ${uploaded}/${passes.length} passes`);
  }
}
