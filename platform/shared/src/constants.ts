// ============================================================
// Shared Constants
// ============================================================

// --- Job Status ---

export const JOB_STATUSES = ['pending', 'claimed', 'running', 'completed', 'failed', 'cancelled'] as const;

export const JOB_STATUS_LABELS: Record<string, string> = {
  pending: 'Pending',
  claimed: 'Claimed',
  running: 'Running',
  completed: 'Completed',
  failed: 'Failed',
  cancelled: 'Cancelled',
};

export const JOB_STATUS_COLORS: Record<string, string> = {
  pending: 'yellow',
  claimed: 'blue',
  running: 'blue',
  completed: 'green',
  failed: 'red',
  cancelled: 'gray',
};

// --- Worker Status ---

export const WORKER_OFFLINE_THRESHOLD_MS = 2 * 60 * 1000; // 2 minutes

// --- Stale Job Recovery ---

export const STALE_JOB_THRESHOLD_MS = 30 * 60 * 1000; // 30 minutes
export const WORKER_DEAD_THRESHOLD_MS = 5 * 60 * 1000; // 5 minutes

// --- Defaults ---

export const DEFAULT_POLL_INTERVAL_MS = 10_000;
export const DEFAULT_HEARTBEAT_INTERVAL_MS = 30_000;
export const DEFAULT_MAX_JOB_DURATION_MS = 8 * 60 * 60 * 1000; // 8 hours
export const DEFAULT_MAX_RETRIES = 3;
export const DEFAULT_DEPOSIT = 10_000;
export const DEFAULT_LEVERAGE = 100;

// --- MT5 Timeframes ---

export const MT5_TIMEFRAMES = [
  'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M10', 'M12', 'M15', 'M20', 'M30',
  'H1', 'H2', 'H3', 'H4', 'H6', 'H8', 'H12',
  'D1', 'W1', 'MN1',
] as const;

export type MT5Timeframe = typeof MT5_TIMEFRAMES[number];

/** Map timeframe string to MT5 period constant (for .ini files) */
export const TIMEFRAME_TO_MT5_PERIOD: Record<string, number> = {
  M1: 1,
  M2: 2,
  M3: 3,
  M4: 4,
  M5: 5,
  M6: 6,
  M10: 10,
  M12: 12,
  M15: 15,
  M20: 20,
  M30: 30,
  H1: 16385,
  H2: 16386,
  H3: 16387,
  H4: 16388,
  H6: 16390,
  H8: 16392,
  H12: 16396,
  D1: 16408,
  W1: 32769,
  MN1: 49153,
};

// --- MT5 Optimization Modes ---

export const OPTIMIZATION_MODE_LABELS: Record<number, string> = {
  1: 'Full (Slow Complete)',
  2: 'Genetic (Fast)',
};

// --- MT5 Tick Models ---

export const TICK_MODEL_LABELS: Record<number, string> = {
  0: 'Every tick',
  1: '1 minute OHLC',
  2: 'Open prices only',
  3: 'Math calculations',
  4: 'Every tick based on real ticks',
};

// --- MT5 Optimization Criteria ---

export const OPTIMIZATION_CRITERION_LABELS: Record<number, string> = {
  0: 'Balance max',
  1: 'Balance + max Profit Factor',
  2: 'Balance + max Expected Payoff',
  3: 'Balance + min Drawdown',
  4: 'Balance + max Recovery Factor',
  5: 'Balance + max Sharpe Ratio',
  6: 'Custom (OnTester)',
};

// --- Default Symbols ---

export const DEFAULT_SYMBOLS = [
  { name: 'XAUUSD', description: 'Gold' },
  { name: 'NAS100', description: 'Nasdaq 100' },
  { name: 'DJ30', description: 'Dow Jones 30' },
  { name: 'BTCUSD', description: 'Bitcoin' },
  { name: 'EURUSD', description: 'Euro / US Dollar' },
  { name: 'GBPUSD', description: 'British Pound / US Dollar' },
  { name: 'USDJPY', description: 'US Dollar / Japanese Yen' },
] as const;

// --- Firestore Collection Paths ---

export const COLLECTIONS = {
  CONFIG: 'config',
  STRATEGIES: 'strategies',
  SYMBOLS: 'symbols',
  OPTIMIZATION_JOBS: 'optimization_jobs',
  OPTIMIZATION_RESULTS: 'optimization_results',
  WORKERS: 'workers',
} as const;

// --- Firebase Storage Paths ---

export const STORAGE_PATHS = {
  STRATEGIES: 'strategies',
} as const;

// --- Firestore Batch Limits ---

export const FIRESTORE_BATCH_LIMIT = 500;
