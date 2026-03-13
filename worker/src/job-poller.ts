/**
 * Job Poller
 * Polls Firestore for pending optimization jobs, claims them with transactions.
 */

import { getDb, admin } from './firebase';
import { COLLECTIONS, DEFAULT_POLL_INTERVAL_MS } from '@algo-trading/shared';
import type { OptimizationJob } from '@algo-trading/shared';
import { recoverStaleJobs } from './stale-recovery';

let pollInterval: ReturnType<typeof setInterval> | null = null;
let isProcessing = false;

export type JobHandler = (jobId: string, job: OptimizationJob) => Promise<void>;

/**
 * Start polling for jobs.
 * @param workerId This worker's ID
 * @param supportedSymbols List of symbols this worker can handle
 * @param handler Callback to process a claimed job
 * @param intervalMs Poll interval (default 10s)
 */
export function startPolling(
  workerId: string,
  supportedSymbols: string[],
  handler: JobHandler,
  intervalMs: number = DEFAULT_POLL_INTERVAL_MS,
): void {
  const poll = async () => {
    if (isProcessing) return;

    try {
      // Run stale recovery first
      await recoverStaleJobs();

      // Find and claim a pending job
      const claimed = await claimJob(workerId, supportedSymbols);

      if (claimed) {
        isProcessing = true;
        const { jobId, job } = claimed;
        console.log(`Claimed job ${jobId}: ${job.strategyName} v${job.strategyVersion} ${job.symbol} ${job.timeframe}`);

        try {
          await handler(jobId, job);
        } catch (err) {
          console.error(`Job ${jobId} failed:`, err);
          await markJobFailed(jobId, String(err));
        } finally {
          isProcessing = false;
        }
      }
    } catch (err) {
      console.error('Poll error:', err);
    }
  };

  // Run immediately, then on interval
  poll();
  pollInterval = setInterval(poll, intervalMs);
  console.log(`Job polling started (every ${intervalMs / 1000}s)`);
}

export function stopPolling(): void {
  if (pollInterval) {
    clearInterval(pollInterval);
    pollInterval = null;
    console.log('Job polling stopped');
  }
}

export function isCurrentlyProcessing(): boolean {
  return isProcessing;
}

/**
 * Claim a pending job using a Firestore transaction
 */
async function claimJob(
  workerId: string,
  supportedSymbols: string[],
): Promise<{ jobId: string; job: OptimizationJob } | null> {
  const db = getDb();

  // Query for pending jobs, ordered by priority then creation time
  const pendingQuery = db.collection(COLLECTIONS.OPTIMIZATION_JOBS)
    .where('status', '==', 'pending')
    .orderBy('priority', 'asc')
    .orderBy('createdAt', 'asc')
    .limit(10); // Fetch a few to find one we support

  const snapshot = await pendingQuery.get();

  if (snapshot.empty) return null;

  // Find first job whose symbol we support
  for (const jobDoc of snapshot.docs) {
    const jobData = jobDoc.data() as OptimizationJob;

    // Check if we support this symbol
    if (supportedSymbols.length > 0 && !supportedSymbols.includes(jobData.symbol)) {
      continue;
    }

    // Try to claim with transaction
    try {
      const claimed = await db.runTransaction(async (transaction) => {
        const freshDoc = await transaction.get(jobDoc.ref);

        if (!freshDoc.exists || freshDoc.data()?.status !== 'pending') {
          return false; // Already claimed by another worker
        }

        transaction.update(jobDoc.ref, {
          status: 'claimed',
          claimedBy: workerId,
          claimedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return true;
      });

      if (claimed) {
        return { jobId: jobDoc.id, job: jobData };
      }
    } catch {
      // Transaction failed (contention), try next job
      continue;
    }
  }

  return null;
}

async function markJobFailed(jobId: string, error: string): Promise<void> {
  const db = getDb();
  try {
    await db.collection(COLLECTIONS.OPTIMIZATION_JOBS).doc(jobId).update({
      status: 'failed',
      error: error.substring(0, 1000), // Truncate long errors
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    console.error(`Failed to mark job ${jobId} as failed:`, err);
  }
}
