/**
 * Deploy CLI — Scans MQL5/Experts/ for compiled .ex5 files,
 * compares hashes with Firestore, uploads new versions to Firebase.
 *
 * Usage: npm run deploy
 *
 * Requires:
 * - Firebase service account key at platform/cli/firebase-service-account.json
 *   (or path set in FIREBASE_CREDENTIALS_PATH env var)
 * - Compiled .ex5 files in MQL5/Experts/
 * - Matching .mq5 source files for input parameter parsing
 */

import * as admin from 'firebase-admin';
import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { execSync } from 'child_process';
import { parseMq5Inputs } from './parse-mq5';
import type { StrategyInput } from '@algo-trading/shared';
import { COLLECTIONS, STORAGE_PATHS } from '@algo-trading/shared';

// --- Config ---
const ROOT_DIR = path.resolve(__dirname, '..', '..', '..');
const MQL5_DIR = path.join(ROOT_DIR, 'MQL5');
const EXPERTS_DIR = path.join(MQL5_DIR, 'Experts');

const CREDENTIALS_PATH = process.env.FIREBASE_CREDENTIALS_PATH
  || path.join(__dirname, '..', 'firebase-service-account.json');

// Skip these files — not real strategies
const SKIP_FILES = new Set(['ExpertTemplate', 'ExampleStrategyWithExport', 'ScriptTemplate']);

// --- Initialize Firebase ---
function initFirebase(): void {
  if (!fs.existsSync(CREDENTIALS_PATH)) {
    console.error(`Firebase credentials not found at: ${CREDENTIALS_PATH}`);
    console.error('Set FIREBASE_CREDENTIALS_PATH env var or place firebase-service-account.json in platform/cli/');
    process.exit(1);
  }

  let serviceAccount: Record<string, string>;
  try {
    serviceAccount = JSON.parse(fs.readFileSync(CREDENTIALS_PATH, 'utf8'));
  } catch (err) {
    console.error(`Invalid Firebase credentials file: ${CREDENTIALS_PATH}`);
    console.error(err instanceof Error ? err.message : err);
    process.exit(1);
  }

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount as admin.ServiceAccount),
    storageBucket: serviceAccount.project_id
      ? `${serviceAccount.project_id}.firebasestorage.app`
      : undefined,
  });
}

// --- Compute SHA-256 hash of a file ---
function hashFile(filePath: string): string {
  const buffer = fs.readFileSync(filePath);
  const hash = crypto.createHash('sha256').update(buffer).digest('hex');
  return `sha256:${hash}`;
}

// --- Get current git commit hash ---
function getGitHash(): string {
  try {
    return execSync('git rev-parse HEAD', { cwd: ROOT_DIR }).toString().trim();
  } catch {
    console.warn('Warning: Could not get git hash — git not available or not a git repo');
    return '';
  }
}

// --- Find all .ex5 files in Experts/ ---
function findEx5Files(): string[] {
  if (!fs.existsSync(EXPERTS_DIR)) {
    console.error(`Experts directory not found: ${EXPERTS_DIR}`);
    process.exit(1);
  }

  return fs.readdirSync(EXPERTS_DIR)
    .filter(f => f.endsWith('.ex5'))
    .filter(f => !SKIP_FILES.has(path.basename(f, '.ex5')))
    .sort();
}

// --- Check if hash already exists for this strategy ---
async function findExistingVersion(
  db: FirebaseFirestore.Firestore,
  strategyName: string,
  ex5Hash: string,
): Promise<number | null> {
  const versionsRef = db.collection(COLLECTIONS.STRATEGIES).doc(strategyName)
    .collection('versions');

  const snapshot = await versionsRef.where('ex5Hash', '==', ex5Hash).limit(1).get();
  if (snapshot.empty) return null;
  return snapshot.docs[0].data().version as number;
}

// --- Main deploy function ---
async function deploy(): Promise<void> {
  initFirebase();

  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  const gitHash = getGitHash();

  console.log(`\nDeploying strategies from: ${EXPERTS_DIR}`);
  if (gitHash) {
    console.log(`Git commit: ${gitHash.substring(0, 7)}`);
  } else {
    console.log('Git commit: unavailable');
  }
  console.log('');

  const ex5Files = findEx5Files();

  if (ex5Files.length === 0) {
    console.log('No .ex5 files found in MQL5/Experts/');
    return;
  }

  const results: { name: string; status: string }[] = [];

  for (const ex5File of ex5Files) {
    const strategyName = path.basename(ex5File, '.ex5');
    const ex5Path = path.join(EXPERTS_DIR, ex5File);
    const mq5Path = path.join(EXPERTS_DIR, `${strategyName}.mq5`);

    // Compute hash
    const ex5Hash = hashFile(ex5Path);

    // Check for existing version with same hash
    const existingVersion = await findExistingVersion(db, strategyName, ex5Hash);

    if (existingVersion !== null) {
      results.push({ name: strategyName, status: `v${existingVersion} (unchanged)` });
      continue;
    }

    // Get current strategy doc or create it
    const stratRef = db.collection(COLLECTIONS.STRATEGIES).doc(strategyName);
    const stratDoc = await stratRef.get();

    let latestVersion = 0;
    if (stratDoc.exists) {
      const data = stratDoc.data();
      latestVersion = data?.latestVersion || 0;
    }

    const newVersion = latestVersion + 1;

    // Upload .ex5 to Firebase Storage
    const storagePath = `${STORAGE_PATHS.STRATEGIES}/${strategyName}/v${newVersion}.ex5`;
    const file = bucket.file(storagePath);

    await file.save(fs.readFileSync(ex5Path), {
      metadata: {
        contentType: 'application/octet-stream',
        metadata: {
          strategyName,
          version: String(newVersion),
          ex5Hash,
          gitHash: gitHash || 'unknown',
        },
      },
    });

    // Parse .mq5 for inputs (if source exists)
    let inputs: StrategyInput[] = [];
    if (fs.existsSync(mq5Path)) {
      const source = fs.readFileSync(mq5Path, 'utf8');
      inputs = parseMq5Inputs(source);
    } else {
      console.warn(`  Warning: No .mq5 source found for ${strategyName}, inputs will be empty`);
    }

    // Create/update strategy document
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (!stratDoc.exists) {
      await stratRef.set({
        name: strategyName,
        description: '',
        latestVersion: newVersion,
        createdAt: now,
        updatedAt: now,
      });
    } else {
      await stratRef.update({
        latestVersion: newVersion,
        updatedAt: now,
      });
    }

    // Create version document
    await stratRef.collection('versions').doc(String(newVersion)).set({
      version: newVersion,
      ex5Hash,
      gitHash: gitHash || 'unknown',
      ex5StoragePath: storagePath,
      inputs,
      createdAt: now,
    });

    results.push({ name: strategyName, status: `v${newVersion} (new)` });
    console.log(`  ${strategyName}: uploaded v${newVersion} (${inputs.length} inputs parsed)`);
  }

  // Summary
  console.log('\n--- Deploy Summary ---');
  for (const r of results) {
    console.log(`  ${r.name}: ${r.status}`);
  }

  const newCount = results.filter(r => r.status.includes('new')).length;
  const unchangedCount = results.filter(r => r.status.includes('unchanged')).length;
  console.log(`\n${newCount} new, ${unchangedCount} unchanged\n`);
}

// --- Run ---
deploy().catch((err) => {
  console.error('Deploy failed:', err);
  process.exit(1);
});
