/**
 * Worker local configuration
 * Reads config.json from worker directory for Firebase credentials and MT5 path.
 * All other config (name, symbol mapping, intervals) comes from Firestore.
 */

import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

export interface LocalConfig {
  firebaseCredentialsPath: string;
  mt5Path: string;
}

const CONFIG_PATH = path.join(__dirname, '..', 'config.json');

export function loadLocalConfig(): LocalConfig {
  if (!fs.existsSync(CONFIG_PATH)) {
    console.error(`Config file not found: ${CONFIG_PATH}`);
    console.error('Create worker/config.json with:');
    console.error(JSON.stringify({
      firebaseCredentialsPath: './firebase-service-account.json',
      mt5Path: 'C:\\Program Files\\MetaTrader 5',
    }, null, 2));
    process.exit(1);
  }

  const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));

  if (!config.firebaseCredentialsPath || !config.mt5Path) {
    console.error('Config must include firebaseCredentialsPath and mt5Path');
    process.exit(1);
  }

  // Resolve relative credential path
  if (!path.isAbsolute(config.firebaseCredentialsPath)) {
    config.firebaseCredentialsPath = path.resolve(path.dirname(CONFIG_PATH), config.firebaseCredentialsPath);
  }

  // Validate Firebase credentials file exists and is valid JSON
  if (!fs.existsSync(config.firebaseCredentialsPath)) {
    console.error(`Firebase credentials file not found: ${config.firebaseCredentialsPath}`);
    process.exit(1);
  }

  try {
    const credsContent = fs.readFileSync(config.firebaseCredentialsPath, 'utf8');
    const creds = JSON.parse(credsContent);
    if (!creds.project_id || !creds.private_key || !creds.client_email) {
      console.error('Firebase credentials file is missing required fields (project_id, private_key, client_email)');
      process.exit(1);
    }
  } catch (err) {
    console.error(`Firebase credentials file is not valid JSON: ${config.firebaseCredentialsPath}`);
    process.exit(1);
  }

  return config;
}

export function getWorkerId(): string {
  return os.hostname().toLowerCase().replace(/[^a-z0-9-]/g, '-');
}
