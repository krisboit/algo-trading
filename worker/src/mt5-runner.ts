/**
 * MT5 Process Runner
 * Spawns terminal64.exe, monitors process, handles timeout and cancellation.
 * Designed for Windows — uses taskkill for process termination.
 */

import { spawn, execSync, ChildProcess } from 'child_process';
import * as path from 'path';
import * as fs from 'fs';
import { getDb } from './firebase';
import { COLLECTIONS } from '@algo-trading/shared';

export interface MT5RunResult {
  exitCode: number | null;
  timedOut: boolean;
  cancelled: boolean;
  durationMs: number;
}

/**
 * Run MT5 strategy tester with the given .ini config.
 * Blocks until MT5 exits, times out, or job is cancelled.
 */
export async function runMT5(
  mt5Path: string,
  iniPath: string,
  jobId: string,
  maxDurationMs: number,
): Promise<MT5RunResult> {
  const terminalExe = path.join(mt5Path, 'terminal64.exe');
  const startTime = Date.now();

  // Validate MT5 executable exists
  if (!fs.existsSync(terminalExe)) {
    throw new Error(`MT5 terminal not found: ${terminalExe}`);
  }

  return new Promise<MT5RunResult>((resolve) => {
    let timedOut = false;
    let cancelled = false;
    let resolved = false;
    let process: ChildProcess | null = null;

    const finish = (exitCode: number | null) => {
      if (resolved) return;
      resolved = true;
      clearTimeout(timeoutHandle);
      clearInterval(cancellationHandle);
      resolve({
        exitCode,
        timedOut,
        cancelled,
        durationMs: Date.now() - startTime,
      });
    };

    // Spawn MT5
    process = spawn(terminalExe, ['/portable', `/config:${iniPath}`], {
      stdio: 'ignore',
      detached: false,
    });

    console.log(`MT5 started (PID: ${process.pid}) for job ${jobId}`);

    // Timeout watchdog
    const timeoutHandle = setTimeout(() => {
      if (process && !resolved) {
        timedOut = true;
        console.log(`Job ${jobId}: timeout after ${maxDurationMs / 1000}s, killing MT5`);
        killProcess(process);
      }
    }, maxDurationMs);

    // Cancellation check (every 30s)
    const cancellationHandle = setInterval(async () => {
      try {
        const db = getDb();
        const jobDoc = await db.collection(COLLECTIONS.OPTIMIZATION_JOBS).doc(jobId).get();
        if (jobDoc.exists && jobDoc.data()?.status === 'cancelled') {
          cancelled = true;
          console.log(`Job ${jobId}: cancelled by user, killing MT5`);
          if (process) killProcess(process);
          clearInterval(cancellationHandle);
        }
      } catch {
        // Ignore Firestore errors during cancellation check
      }
    }, 30_000);

    // Handle process exit
    process.on('exit', (code) => {
      const durationMs = Date.now() - startTime;
      console.log(`MT5 exited (code: ${code}) after ${Math.round(durationMs / 1000)}s`);
      finish(code);
    });

    process.on('error', (err) => {
      console.error('MT5 process error:', err);
      finish(-1);
    });
  });
}

/**
 * Kill MT5 process — Windows-compatible
 */
function killProcess(proc: ChildProcess): void {
  const pid = proc.pid;
  if (!pid) return;

  try {
    if (process.platform === 'win32') {
      // Windows: use taskkill for reliable process termination
      try {
        execSync(`taskkill /PID ${pid} /T /F`, { stdio: 'ignore' });
      } catch {
        // Process may already be dead
      }
    } else {
      // Unix: SIGTERM, then force-kill after 10s
      proc.kill('SIGTERM');
      setTimeout(() => {
        try { proc.kill('SIGKILL'); } catch { /* already dead */ }
      }, 10_000);
    }
  } catch {
    // Process already terminated
  }
}
