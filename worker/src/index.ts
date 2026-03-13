/**
 * Worker App Entry Point
 *
 * Node.js service that runs on Windows servers to process MT5 optimization jobs.
 * Connects to Firebase, polls for jobs, runs MT5 optimizations, and uploads results.
 */

import * as os from 'os';
import * as fs from 'fs';
import * as path from 'path';
import { loadLocalConfig, getWorkerId } from './config';
import { initFirebase, getDb, admin } from './firebase';
import { startHeartbeat, stopHeartbeat } from './heartbeat';
import { startPolling, stopPolling, isCurrentlyProcessing } from './job-poller';
import { processJob } from './job-processor';
import {
  COLLECTIONS,
  DEFAULT_POLL_INTERVAL_MS,
  DEFAULT_HEARTBEAT_INTERVAL_MS,
  DEFAULT_MAX_JOB_DURATION_MS,
} from '@algo-trading/shared';
import type { SymbolMapping, WorkerConfig } from '@algo-trading/shared';

let isShuttingDown = false;

async function main(): Promise<void> {
  console.log('=== Algo Trading Worker ===\n');

  // 1. Load local config
  const localConfig = loadLocalConfig();
  const workerId = getWorkerId();
  console.log(`Worker ID: ${workerId}`);
  console.log(`MT5 Path: ${localConfig.mt5Path}`);

  // Validate MT5 path
  const terminalExe = path.join(localConfig.mt5Path, 'terminal64.exe');
  if (!fs.existsSync(localConfig.mt5Path)) {
    console.error(`MT5 directory not found: ${localConfig.mt5Path}`);
    process.exit(1);
  }
  if (!fs.existsSync(terminalExe)) {
    console.warn(`Warning: terminal64.exe not found at ${terminalExe}`);
    console.warn('MT5 optimizations will fail until the terminal is installed.\n');
  } else {
    console.log('MT5 terminal: found\n');
  }

  // 2. Initialize Firebase
  initFirebase(localConfig);
  const db = getDb();

  // 3. Register/update worker in Firestore
  const workerRef = db.collection(COLLECTIONS.WORKERS).doc(workerId);
  const workerDoc = await workerRef.get();
  const hostname = os.hostname();

  if (!workerDoc.exists) {
    await workerRef.set({
      name: workerId,
      hostname,
      status: 'online',
      lastPing: admin.firestore.FieldValue.serverTimestamp(),
      currentJobId: null,
      mt5Version: '',
      symbolMapping: { prefix: '', suffix: '', overrides: {} },
      supportedSymbols: [],
      stats: { jobsCompleted: 0, jobsFailed: 0, totalRuntime: 0 },
      config: {
        pollInterval: DEFAULT_POLL_INTERVAL_MS,
        heartbeatInterval: DEFAULT_HEARTBEAT_INTERVAL_MS,
        maxJobDuration: DEFAULT_MAX_JOB_DURATION_MS,
      },
      registeredAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('Worker registered (first time).');
    console.log('Configure name, symbol mapping, and supported symbols in the UI.\n');
  } else {
    await workerRef.update({
      status: 'online',
      lastPing: admin.firestore.FieldValue.serverTimestamp(),
      hostname,
    });
    console.log('Worker reconnected.\n');
  }

  // 4. Read worker config from Firestore
  const freshWorkerDoc = await workerRef.get();
  const workerData = freshWorkerDoc.data()!;

  const symbolMapping: SymbolMapping = workerData.symbolMapping || {
    prefix: '', suffix: '', overrides: {},
  };
  const supportedSymbols: string[] = workerData.supportedSymbols || [];
  const workerConfig: WorkerConfig = workerData.config || {
    pollInterval: DEFAULT_POLL_INTERVAL_MS,
    heartbeatInterval: DEFAULT_HEARTBEAT_INTERVAL_MS,
    maxJobDuration: DEFAULT_MAX_JOB_DURATION_MS,
  };

  console.log(`Symbol mapping: prefix="${symbolMapping.prefix}" suffix="${symbolMapping.suffix}"`);
  if (symbolMapping.overrides && Object.keys(symbolMapping.overrides).length > 0) {
    console.log(`Symbol overrides: ${JSON.stringify(symbolMapping.overrides)}`);
  }
  console.log(`Supported symbols: ${supportedSymbols.length > 0 ? supportedSymbols.join(', ') : '(all — no filter)'}`);
  console.log(`Poll interval: ${workerConfig.pollInterval / 1000}s`);
  console.log(`Max job duration: ${workerConfig.maxJobDuration / 3600000}h\n`);

  // 5. Start heartbeat
  startHeartbeat(workerId, workerConfig.heartbeatInterval);

  // 6. Start job polling
  startPolling(
    workerId,
    supportedSymbols,
    async (jobId, job) => {
      await processJob(
        jobId,
        job,
        workerId,
        localConfig.mt5Path,
        symbolMapping,
        workerConfig.maxJobDuration,
      );
    },
    workerConfig.pollInterval,
  );

  // 7. Register graceful shutdown
  const shutdown = async (signal: string) => {
    if (isShuttingDown) return;
    isShuttingDown = true;

    console.log(`\n${signal} received. Shutting down gracefully...`);

    stopPolling();
    stopHeartbeat();

    // Wait for current job to finish (up to 60 seconds)
    if (isCurrentlyProcessing()) {
      console.log('Waiting for current job to finish (max 60s)...');
      let waited = 0;
      while (isCurrentlyProcessing() && waited < 60_000) {
        await new Promise(r => setTimeout(r, 1000));
        waited += 1000;
      }
      if (isCurrentlyProcessing()) {
        console.log('Job still running. It will be recovered by stale job detection.');
      }
    }

    // Mark worker as offline
    try {
      await workerRef.update({
        status: 'offline',
        currentJobId: null,
      });
    } catch (err) {
      console.warn('Failed to update worker status:', err);
    }

    console.log('Worker shutdown complete.');
    process.exit(0);
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));

  console.log('Worker running. Press Ctrl+C to stop.\n');
}

// --- Run ---
main().catch((err) => {
  console.error('Worker failed to start:', err);
  process.exit(1);
});
