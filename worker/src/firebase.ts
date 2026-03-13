/**
 * Firebase Admin SDK initialization for worker
 */

import * as admin from 'firebase-admin';
import * as fs from 'fs';
import { LocalConfig } from './config';

export function initFirebase(config: LocalConfig): void {
  if (!fs.existsSync(config.firebaseCredentialsPath)) {
    console.error(`Firebase credentials not found: ${config.firebaseCredentialsPath}`);
    process.exit(1);
  }

  const serviceAccount = JSON.parse(
    fs.readFileSync(config.firebaseCredentialsPath, 'utf8')
  );

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: `${serviceAccount.project_id}.firebasestorage.app`,
  });
}

export function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

export function getBucket(): ReturnType<typeof admin.storage.prototype.bucket> {
  return admin.storage().bucket();
}

export { admin };
