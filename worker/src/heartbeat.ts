/**
 * Worker heartbeat - periodic lastPing update to Firestore
 */

import { getDb, admin } from './firebase';
import { COLLECTIONS } from '@algo-trading/shared';

let heartbeatInterval: ReturnType<typeof setInterval> | null = null;

export function startHeartbeat(workerId: string, intervalMs: number = 30_000): void {
  const db = getDb();
  const workerRef = db.collection(COLLECTIONS.WORKERS).doc(workerId);

  const ping = async () => {
    try {
      await workerRef.update({
        lastPing: admin.firestore.FieldValue.serverTimestamp(),
        status: 'online',
      });
    } catch (err) {
      console.error('Heartbeat failed:', err);
    }
  };

  // Immediate first ping
  ping();

  heartbeatInterval = setInterval(ping, intervalMs);
  console.log(`Heartbeat started (every ${intervalMs / 1000}s)`);
}

export function stopHeartbeat(): void {
  if (heartbeatInterval) {
    clearInterval(heartbeatInterval);
    heartbeatInterval = null;
    console.log('Heartbeat stopped');
  }
}
