// ============================================================
// Firestore Data Model Types
// ============================================================

// --- Config ---

export interface DefaultOptimizationSettings {
  deposit: number;
  leverage: number;
  optimizationMode: OptimizationMode;
  model: TickModel;
  optimizationCriterion: OptimizationCriterion;
}

export interface AppConfig {
  githubRepoUrl: string;
  defaultOptimizationSettings: DefaultOptimizationSettings;
}

// --- Strategy ---

export interface StrategyInputOptimize {
  enabled: boolean;
  min: number;
  max: number;
  step: number;
}

export interface StrategyInput {
  name: string;
  type: 'int' | 'double' | 'bool' | 'string' | 'enum';
  default: number | string | boolean;
  label: string;
  group: string;
  optimize: StrategyInputOptimize;
}

export interface StrategyVersion {
  version: number;
  ex5Hash: string;
  gitHash: string;
  ex5StoragePath: string;
  inputs: StrategyInput[];
  createdAt: FirestoreTimestamp;
}

export interface Strategy {
  name: string;
  description: string;
  latestVersion: number;
  createdAt: FirestoreTimestamp;
  updatedAt: FirestoreTimestamp;
}

// --- Symbol ---

export interface TradingSymbol {
  name: string;
  description: string;
  active: boolean;
}

// --- Optimization Job ---

export type JobStatus = 'pending' | 'claimed' | 'running' | 'completed' | 'failed' | 'cancelled';

export interface JobResultSummary {
  totalPasses: number;
  profitablePasses: number;
  bestProfit: number;
  bestProfitFactor: number;
  bestCustomCriterion: number;
  bestDrawdown: number;
}

export interface InputOverride {
  min: number;
  max: number;
  step: number;
  enabled: boolean;
}

export interface OptimizationJob {
  strategyName: string;
  strategyVersion: number;
  symbol: string;
  timeframe: string;
  fromDate: string;
  toDate: string;
  deposit: number;
  leverage: number;
  optimizationMode: OptimizationMode;
  model: TickModel;
  optimizationCriterion: OptimizationCriterion;
  inputOverrides: Record<string, InputOverride>;

  status: JobStatus;
  claimedBy: string | null;
  claimedAt: FirestoreTimestamp | null;
  startedAt: FirestoreTimestamp | null;
  completedAt: FirestoreTimestamp | null;
  duration: number | null;
  error: string | null;
  retryCount: number;
  maxRetries: number;

  resultSummary: JobResultSummary | null;

  deploymentGitHash: string | null;
  createdAt: FirestoreTimestamp;
  createdBy: 'cli' | 'ui';
  priority: number;
}

// --- Optimization Result Pass ---

export interface OptimizationPass {
  profit: number;
  profitFactor: number;
  expectedPayoff: number;
  recoveryFactor: number;
  sharpeRatio: number;
  drawdownPercent: number;
  trades: number;
  customCriterion: number;
  inputs: Record<string, number | string | boolean>;
}

// --- Worker ---

export interface SymbolMapping {
  prefix: string;
  suffix: string;
  overrides: Record<string, string>;
}

export interface WorkerStats {
  jobsCompleted: number;
  jobsFailed: number;
  totalRuntime: number;
}

export interface WorkerConfig {
  pollInterval: number;
  heartbeatInterval: number;
  maxJobDuration: number;
}

export interface Worker {
  name: string;
  hostname: string;
  status: 'online' | 'offline';
  lastPing: FirestoreTimestamp;
  currentJobId: string | null;
  mt5Version: string;
  symbolMapping: SymbolMapping;
  supportedSymbols: string[];
  stats: WorkerStats;
  config: WorkerConfig;
  registeredAt: FirestoreTimestamp;
}

// --- Firestore Timestamp (generic, works with both client and admin SDK) ---

export interface FirestoreTimestamp {
  seconds: number;
  nanoseconds: number;
  toDate(): Date;
}

// --- Enums as numeric types (matching MT5 constants) ---

export type OptimizationMode = 1 | 2; // 1=full, 2=genetic
export type TickModel = 0 | 1 | 2 | 3 | 4; // 0=every tick, 1=1min OHLC, 2=open only, 3=math, 4=every tick based on real ticks
export type OptimizationCriterion = 0 | 1 | 2 | 3 | 4 | 5 | 6; // 0=balance max, ..., 6=custom (OnTester)
