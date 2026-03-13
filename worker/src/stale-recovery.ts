/**
 * Stale Job Recovery
 * Detects jobs stuck in "claimed" or "running" state and resets them.
 * Uses transactions to prevent race conditions between workers.
 */

import { getDb, admin } from './firebase';
import {
  COLLECTIONS,
  STALE_JOB_THRESHOLD_MS,
  WORKER_DEAD_THRESHOLD_MS,
  DEFAULT_MAX_RETRIES,
} from '@algo-trading/shared';

/**
 * Check for and recover stale jobs.
 * A job is stale if:
 * - Status is "claimed" or "running"
 * - claimedAt is older than STALE_JOB_THRESHOLD (30 min)
 * - The assigned worker's lastPing is older than WORKER_DEAD_THRESHOLD (5 min)
 */
export async function recoverStaleJobs(): Promise<void> {
  const db = getDb();
  const now = Date.now();
  const staleThreshold = new Date(now - STALE_JOB_THRESHOLD_MS);

  try {
    const jobsRef = db.collection(COLLECTIONS.OPTIMIZATION_JOBS);

    // Query for potentially stale claimed jobs
    const claimedSnap = await jobsRef
      .where('status', '==', 'claimed')
      .where('claimedAt', '<', admin.firestore.Timestamp.fromDate(staleThreshold))
      .get();

    // Query for potentially stale running jobs
    const runningSnap = await jobsRef
      .where('status', '==', 'running')
      .where('claimedAt', '<', admin.firestore.Timestamp.fromDate(staleThreshold))
      .get();

    const staleDocs = [...claimedSnap.docs, ...runningSnap.docs];
    if (staleDocs.length === 0) return;

    for (const jobDoc of staleDocs) {
      const jobData = jobDoc.data();
      const claimedBy = jobData.claimedBy;

      if (!claimedBy) continue;

      // Check if the worker is dead
      const workerDoc = await db.collection(COLLECTIONS.WORKERS).doc(claimedBy).get();

      let workerDead = true;
      if (workerDoc.exists) {
        const workerData = workerDoc.data();
        const lastPing = workerData?.lastPing?.toDate?.()?.getTime() || 0;
        workerDead = (now - lastPing > WORKER_DEAD_THRESHOLD_MS);
      }

      if (workerDead) {
        await resetJobWithTransaction(db, jobDoc.ref, jobData);
      }
    }
  } catch (err) {
    console.error('Stale job recovery error:', err);
  }
}

async function resetJobWithTransaction(
  db: FirebaseFirestore.Firestore,
  jobRef: FirebaseFirestore.DocumentReference,
  jobData: FirebaseFirestore.DocumentData,
): Promise<void> {
  try {
    await db.runTransaction(async (transaction) => {
      const freshDoc = await transaction.get(jobRef);
      if (!freshDoc.exists) return;

      const freshData = freshDoc.data()!;
      // Verify job is still in a stale state (another worker may have already reset it)
      if (freshData.status !== 'claimed' && freshData.status !== 'running') return;

      const retryCount = (freshData.retryCount || 0) + 1;
      const maxRetries = freshData.maxRetries || DEFAULT_MAX_RETRIES;

      if (retryCount > maxRetries) {
        transaction.update(jobRef, {
          status: 'failed',
          error: `Max retries exceeded (${maxRetries}) - worker unresponsive`,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Job ${jobRef.id}: max retries exceeded, marked as failed`);
      } else {
        transaction.update(jobRef, {
          status: 'pending',
          claimedBy: null,
          claimedAt: null,
          startedAt: null,
          retryCount,
          error: null,
        });
        console.log(`Job ${jobRef.id}: reset to pending (retry ${retryCount}/${maxRetries})`);
      }
    });
  } catch (err) {
    console.error(`Failed to reset job ${jobRef.id}:`, err);
  }
}
