# Algo Trading Platform

## Overview

An AI-assisted trading strategy development and optimization platform. Strategies are implemented in MQL5 for MetaTrader 5, with a Firebase-based management system for running optimizations at scale across multiple Windows worker servers.

**Three components:**

1. **Local Mac Tooling** — MQL5 strategy development, compilation (Wine/Whisky), deploy CLI
2. **Firebase Platform (UI)** — Web app for managing strategies (versioned), optimization jobs (queued), results, and worker monitoring
3. **Worker App** — Node.js service on Windows servers that runs MT5 optimizations and reports results

**Current focus:** Optimization runs only — discover profitable strategies by running genetic optimizations across symbols/timeframes. Detailed single-backtest analysis deferred to a future phase.

---

## Repository Structure

```
algo-trading/
├── MQL5/                              # MQL5 source & portable-mode structure
│   ├── Experts/                       # Strategy EAs (.mq5 + .ex5 committed)
│   ├── Include/
│   │   ├── Framework/                 # Strategy framework
│   │   │   ├── StrategyBase.mqh       # OnTester(), HasPosition(), CloseAllPositions()
│   │   │   ├── TradeManager.mqh       # Trailing stops, breakeven, partial close
│   │   │   └── TesterExport.mqh       # Write per-pass optimization results
│   │   └── StrategyExporter/          # Existing (kept for future detailed backtests)
│   ├── Indicators/                    # Custom indicators (.mq5 source only, no iCustom)
│   └── Profiles/Tester/               # Local .ini/.set files (for Mac testing)
│
├── strategies/                        # Strategy documentation (markdown)
├── scripts/                           # Mac scripts (compile, mt5, mount — existing)
│
├── platform/                          # Firebase platform
│   ├── firebase.json
│   ├── .firebaserc
│   ├── firestore.rules
│   ├── firestore.indexes.json
│   ├── storage.rules
│   ├── shared/                        # Shared TypeScript types
│   │   ├── package.json
│   │   └── src/
│   │       ├── types.ts               # Strategy, Job, Worker, Result interfaces
│   │       └── constants.ts           # Status enums, timeframe mappings
│   ├── ui/                            # Management UI (React + Vite + Tailwind)
│   │   ├── package.json
│   │   ├── vite.config.ts
│   │   ├── index.html
│   │   └── src/
│   │       ├── App.tsx
│   │       ├── main.tsx
│   │       ├── services/
│   │       │   └── firebase.ts        # Firebase client SDK init + helpers
│   │       ├── pages/
│   │       │   ├── Dashboard.tsx       # Overview stats, recent jobs, worker health
│   │       │   ├── Strategies.tsx      # Strategy list, versions, inputs, delete
│   │       │   ├── Optimizations.tsx   # Batch job creation wizard
│   │       │   ├── Jobs.tsx            # Job queue with status filters
│   │       │   ├── Results.tsx         # Optimization pass results table
│   │       │   └── Workers.tsx         # Worker status, config, health
│   │       └── components/
│   ├── functions/                     # Cloud Functions (optional, scheduled tasks)
│   │   ├── package.json
│   │   └── src/
│   │       └── index.ts
│   └── cli/                           # Deploy CLI tool (runs on Mac)
│       ├── package.json
│       └── src/
│           ├── deploy.ts              # Main deploy command
│           └── parse-mq5.ts           # Extract input params from .mq5 source
│
├── worker/                            # Worker app (Node.js, runs on Windows)
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       ├── index.ts                   # Entry point, startup, graceful shutdown
│       ├── config.ts                  # Local config (Firebase creds + MT5 path)
│       ├── firebase.ts                # Firebase admin SDK init
│       ├── heartbeat.ts               # Periodic lastPing update (30s)
│       ├── job-poller.ts              # Poll for pending jobs, claim with transaction
│       ├── job-processor.ts           # Download EA, generate configs, run MT5, parse results
│       ├── mt5-runner.ts              # Spawn MT5 process, watchdog, cancellation check
│       ├── config-generator.ts        # Generate .ini + .set (UTF-16LE) from job data
│       ├── result-parser.ts           # Parse per-pass optimization results from EA output
│       └── stale-recovery.ts          # Detect and reset orphaned/stuck jobs
│
├── dashboard/                         # ARCHIVED: old local dashboard (kept for reference)
├── package.json                       # Root: npm workspaces
└── plan.md                            # This file
```

---

## Strategy Development

### MQL5 Framework (`Include/Framework/`)

All strategies use a shared framework for consistency. No `iCustom()` calls — all indicator logic uses built-in MT5 indicators (iMA, iATR, iRSI, etc.) or `#include` files. Each compiled .ex5 is fully self-contained.

**StrategyBase.mqh** — Common utilities included by all EAs:
- Standard `OnTester()` fitness function: `ProfitFactor * sqrt(Trades) * (1 - DD%/100)` with min trade filter (< 10 trades = 0), PF cap at 5, losing strategy = 0
- `HasPosition(symbol, magic)` — check for open position
- `CloseAllPositions(symbol, magic)` — close all positions for this EA

**TradeManager.mqh** — Trade management utilities:
- `ManageTrailingStopATR(magic, atrHandle, multiplier)` — ATR-based trailing stop
- `CheckBreakEven(magic)` — move SL to breakeven at 1R profit
- `ApplyPartialClose(magic, percent, atLevel)` — partial position close

**TesterExport.mqh** — Optimization result export:
- Called from each EA's `OnTester()` function
- Writes per-pass results to a file: all TesterStatistics + input parameter values
- Only writes passes that are profitable AND have drawdown < 30%
- Framework provides the file-writing helpers; each EA lists its own input parameters
- Output files land in agent sandbox directories; worker collects them after MT5 exits

**RiskManager.mqh** — Already exists (CalcLotSize, NormPrice), kept as-is.

### Strategy Rules

- All indicator logic uses built-in MT5 indicators or `#include` files — never `iCustom()`
- Each strategy = one self-contained .ex5 file
- When improving a strategy: add a parameter to change behavior (keeps backward compat), or create a new version
- All strategies use the Framework includes for consistent trade/risk management and OnTester()

---

## Deployment Model

### Flow

```
Mac (Developer):
  1. Create/edit strategy .mq5 file
  2. Compile: ./scripts/compile.sh Experts/StrategyName.mq5
  3. Commit .mq5 + .ex5 to git, push
  4. Deploy: npm run deploy

Deploy command (platform/cli):
  For each .ex5 in MQL5/Experts/:
    1. Compute SHA-256 hash of .ex5
    2. Check Firestore — does any version of this strategy have this hash?
       → YES: skip ("SessionBreakout: unchanged")
       → NO:  continue
    3. Upload .ex5 to Firebase Storage
    4. Parse matching .mq5 for input parameters
    5. Create new version in Firestore (auto-increment: v1, v2, v3...)
    6. Store git commit hash for traceability

  Output example:
    SessionBreakout: v4 (new)
    EMACrossoverPullback: v2 (unchanged)
    KeltnerChannelBreakout: v3 (new)
```

### Strategy Versioning

| Concept | How it works |
|---------|-------------|
| **Name** | Derived from filename: `SessionBreakout.ex5` → "SessionBreakout" |
| **Version** | Auto-incremented: v1, v2, v3... |
| **Identity** | SHA-256 hash of .ex5 file (dedup: same hash = same version, skip upload) |
| **Traceability** | Git commit hash stored per version → clickable link to GitHub commit in UI |
| **Deletion** | UI shows warning with count of linked jobs/results → cascade delete on confirm (Firestore doc + Storage file + linked jobs + results) |

### Input Parsing from .mq5 Source

The deploy CLI parses `input` declarations from .mq5 files:

```mql5
input group "=== Session Settings (GMT Hours) ==="
input int    InpAsianEnd   = 8;    // Asian Session End Hour
input double InpRiskReward = 1.5;  // Risk-to-Reward Ratio
```

Extracted as:
```json
{
  "name": "InpAsianEnd",
  "type": "int",
  "default": 8,
  "label": "Asian Session End Hour",
  "group": "Session Settings (GMT Hours)",
  "optimize": { "enabled": false, "min": 0, "max": 0, "step": 0 }
}
```

Optimization ranges can be set/overridden in the UI when creating jobs.

---

## Firestore Data Model

```
config/settings
  ├── githubRepoUrl: "https://github.com/user/algo-trading"
  └── defaultOptimizationSettings: {
        deposit: 10000,
        leverage: 100,
        optimizationMode: 2,          // 2 = genetic
        model: 4,                     // every tick based on real ticks
        optimizationCriterion: 6      // custom = OnTester()
      }

strategies/{strategyName}
  ├── name: "SessionBreakout"
  ├── description: "Asian session range breakout during London/NY kill zones"
  ├── latestVersion: 4
  ├── createdAt: timestamp
  ├── updatedAt: timestamp
  │
  └── versions/{versionNumber}                    (subcollection)
      ├── version: 4
      ├── ex5Hash: "sha256:abc123..."
      ├── gitHash: "def456789..."
      ├── ex5StoragePath: "strategies/SessionBreakout/v4.ex5"
      ├── inputs: [
      │     {
      │       name: "InpAsianEnd",
      │       type: "int",
      │       default: 8,
      │       label: "Asian Session End Hour",
      │       group: "Session Settings (GMT Hours)",
      │       optimize: { enabled: true, min: 7, max: 9, step: 1 }
      │     },
      │     ...
      │   ]
      └── createdAt: timestamp

symbols/{symbolId}
  ├── name: "XAUUSD"
  ├── description: "Gold"
  └── active: true

optimization_jobs/{jobId}
  ├── strategyName: "SessionBreakout"
  ├── strategyVersion: 4
  ├── symbol: "XAUUSD"                            (canonical name)
  ├── timeframe: "M15"
  ├── fromDate: "2025.01.01"
  ├── toDate: "2026.03.01"
  ├── deposit: 10000
  ├── leverage: 100
  ├── optimizationMode: 2                         (1=full, 2=genetic)
  ├── model: 4                                    (tick model)
  ├── optimizationCriterion: 6                    (custom = OnTester)
  ├── inputOverrides: { ... }                     (optional per-job range overrides)
  │
  ├── status: "pending" | "claimed" | "running" | "completed" | "failed" | "cancelled"
  ├── claimedBy: "worker-1" | null
  ├── claimedAt: timestamp | null
  ├── startedAt: timestamp | null
  ├── completedAt: timestamp | null
  ├── duration: number (seconds) | null
  ├── error: string | null
  ├── retryCount: 0
  ├── maxRetries: 3
  │
  ├── resultSummary: {
  │     totalPasses: 5200,
  │     profitablePasses: 340,
  │     bestProfit: 5234.50,
  │     bestProfitFactor: 2.15,
  │     bestCustomCriterion: 18.7,
  │     bestDrawdown: 8.2
  │   } | null
  │
  ├── deploymentGitHash: "def456789..."           (git hash at time of execution)
  ├── createdAt: timestamp
  ├── createdBy: "cli" | "ui"
  └── priority: 0                                 (lower = higher priority)

optimization_results/{jobId}/passes/{passIndex}           (subcollection)
  ├── profit: 1234.56
  ├── profitFactor: 1.85
  ├── expectedPayoff: 12.34
  ├── recoveryFactor: 3.2
  ├── sharpeRatio: 1.1
  ├── drawdownPercent: 8.5
  ├── trades: 142
  ├── customCriterion: 15.6                       (OnTester() result)
  └── inputs: {
        "InpAsianEnd": 8,
        "InpBreakoutBuffer": 10,
        "InpRiskReward": 2.0,
        ...
      }

workers/{workerId}
  ├── name: "Windows Server 1"
  ├── hostname: "WIN-ABC123"
  ├── status: "online" | "offline"
  ├── lastPing: timestamp
  ├── currentJobId: "job-xyz" | null
  ├── mt5Version: "5.00 build 4710"
  ├── symbolMapping: {
  │     prefix: "",
  │     suffix: "m",
  │     overrides: { "DJ30": "US30m" }
  │   }
  ├── supportedSymbols: ["XAUUSDm", "NAS100m", ...]
  ├── stats: {
  │     jobsCompleted: 45,
  │     jobsFailed: 2,
  │     totalRuntime: 86400
  │   }
  ├── config: {
  │     pollInterval: 10000,
  │     heartbeatInterval: 30000,
  │     maxJobDuration: 28800000       (8 hours in ms)
  │   }
  └── registeredAt: timestamp
```

---

## Worker App

### Bootstrap Sequence

1. Read local `config.json`: Firebase service account credentials path + MT5 installation path
2. Initialize Firebase Admin SDK
3. Register/update worker document in Firestore (status=online, lastPing=now)
4. Read remaining config from Firestore (name, symbol mapping, intervals)
5. Start heartbeat loop (every 30s: update lastPing)
6. Start job polling loop
7. Register graceful shutdown handler (SIGINT/SIGTERM → status=offline, finish current job)

### Job Polling Loop (every 10s)

```
1. Run stale job recovery check
2. Query: optimization_jobs where status="pending", ordered by priority ASC, createdAt ASC, limit 1
   Filter: only jobs whose symbol this worker supports
3. If job found → claim with Firestore transaction:
     runTransaction:
       read job → verify still "pending" → update status="claimed", claimedBy=me, claimedAt=now
4. If claim succeeds → process job
5. If no jobs → sleep pollInterval, repeat
```

### Job Processing

```
 1. Update job status → "running", startedAt=now
 2. Update worker currentJobId
 3. Download .ex5 from Firebase Storage → place in MT5's MQL5/Experts/
 4. Generate .ini file from job config (symbol, timeframe, dates, optimization mode)
    - Translate canonical symbol to broker symbol via worker's symbolMapping
 5. Generate .set file from strategy input definitions + any inputOverrides
    - UTF-16LE encoding, format: InpParam=default||start||step||stop||Y/N
 6. Launch: terminal64.exe /portable /config:path\to\job.ini
 7. Watchdog loop while MT5 running:
    - Check process still alive
    - Check elapsed time < maxJobDuration (8hr default), kill if exceeded
    - Every 30s: check Firestore if job was cancelled, kill MT5 if so
 8. MT5 exits → collect result files from Tester/Agent-*/MQL5/Files/
 9. Parse results: each pass with profit > 0 and DD < 30%
10. Upload passes to Firestore: optimization_results/{jobId}/passes/...
    - Batch writes (Firestore limit: 500 per batch)
11. Update job: status="completed", completedAt=now, resultSummary={...}
12. Cleanup: remove temporary .ini, .set, result files
13. Update worker: currentJobId=null
```

### Error Handling

- MT5 exits with error → status="failed", error=message
- Process timeout (> 8hr) → kill MT5, status="failed", error="timeout after 8 hours"
- Worker crash mid-job → job stays "running", stale recovery resets it
- Firestore write fails → retry with exponential backoff
- Job cancelled during run → kill MT5, status="cancelled"

### Stale Job Recovery (runs on each poll cycle)

```
1. Query: optimization_jobs where status IN ["claimed", "running"]
          AND claimedAt < (now - 30 minutes)
2. For each stale job:
   a. Look up assigned worker's lastPing
   b. If worker lastPing > 5 minutes ago (worker is dead):
      - If retryCount < maxRetries:
        → Transaction: reset status="pending", clear claimedBy/claimedAt, increment retryCount
      - If retryCount >= maxRetries:
        → Set status="failed", error="Max retries exceeded — worker unresponsive"
```

### Symbol Translation

Workers have a symbol mapping configuration in Firestore:

```json
{
  "prefix": "",
  "suffix": "m",
  "overrides": { "DJ30": "US30m" }
}
```

Translation: canonical "XAUUSD" → apply suffix → "XAUUSDm". Override "DJ30" → "US30m".

Worker only claims jobs for symbols it can translate and has data for. Historical tick data must be pre-downloaded manually during worker setup.

---

## Firebase Management UI

### Authentication

Google Sign-in with whitelisted email. Firestore security rules require authentication for all reads and writes.

### Pages

| Page | Description |
|------|-------------|
| **Dashboard** | Overview: total strategies, jobs by status (pending/running/completed/failed), worker health summary |
| **Strategies** | List all strategies. Click into a strategy → see all versions with: version number, git hash (clickable link to GitHub commit), .ex5 hash, inputs (expandable), created date, # of linked optimization jobs. Delete version: warning with cascade confirmation. |
| **Optimizations** | **Batch job creation wizard:** Select strategy + version → multi-select symbols → multi-select timeframes → set date range → optimization settings (genetic/full, deposit, leverage) → review/edit input optimization ranges (pre-filled from strategy metadata) → preview "This will create N jobs" → submit |
| **Jobs** | Queue view with status filters (pending, running, completed, failed, cancelled). Columns: strategy, symbol, timeframe, status, worker, duration. Actions: cancel pending, retry failed. |
| **Results** | Per-job optimization results: sortable/filterable table of passes. Columns: profit, profit factor, drawdown %, trades, custom criterion, Sharpe ratio, and all input parameter values. |
| **Workers** | List workers: name, hostname, status indicator (green=online, red=offline), last ping (relative time), current job, symbol mapping, stats (jobs completed, failed, total runtime). A worker is "offline" if lastPing > 2 minutes ago. Symbol mapping and other config editable in UI. |

### Key UI Flows

**Optimization batch creation:**
1. Select strategy (dropdown) → select version
2. Multi-select symbols from configured list (XAUUSD, NAS100, DJ30, BTCUSD, ...)
3. Multi-select timeframes (M5, M15, H1, ...)
4. Set date range (from date, to date)
5. Optimization settings (genetic vs full, deposit, leverage, optimization criterion)
6. Review input optimization ranges (pre-filled from strategy version metadata, editable)
7. Preview: "This will create **12 jobs** (1 strategy x 4 symbols x 3 timeframes)"
8. Submit → creates 12 job documents in Firestore with status="pending"

**Strategy version deletion:**
1. Click delete on a version
2. Warning dialog: "Delete SessionBreakout v2? This will also delete 8 optimization jobs and 2,400 result passes."
3. On confirm → cascade delete: Firestore version doc + .ex5 from Storage + all linked optimization_jobs + all linked optimization_results passes

---

## Local Mac Setup

### Existing Scripts (kept as-is)

- `scripts/compile.sh` — Compile .mq5 via Wine/Whisky MetaEditor
- `scripts/mt5.sh` — Launch MT5 terminal via Wine
- `scripts/mount.sh` — Symlink repo's MQL5/ folder into Wine bottle's MT5 installation
- `scripts/strategy-tester.sh` — Run a single strategy test via CLI
- `scripts/run-optimizations.sh` — Batch run optimizations locally
- `scripts/generate-configs.py` — Generate .ini/.set files for local testing

### New: Deploy CLI (`platform/cli/`)

**Command:** `npm run deploy`

Uses firebase-admin SDK with a service account key stored locally on Mac. Scans MQL5/Experts/ for all compiled .ex5 files, compares hashes with Firestore, uploads new versions, and parses .mq5 source for input metadata.

Requires: Firebase service account key file (not committed to git, added to .gitignore).

---

## Windows Worker Setup

### Prerequisites

1. MetaTrader 5 installed and configured for portable mode (launch with `/portable` once)
2. Broker account logged in, auto-updates disabled
3. Historical tick data pre-downloaded for all symbols to be tested
4. Node.js 20+ installed
5. Worker app from repo (`worker/` directory) with `npm install`
6. Firebase service account credentials file
7. Local `config.json` with Firebase project info + MT5 installation path

### Local Config (`worker/config.json`)

```json
{
  "firebaseCredentialsPath": "./firebase-service-account.json",
  "mt5Path": "C:\\Program Files\\MetaTrader 5"
}
```

Everything else (worker name, symbol mapping, poll/heartbeat intervals, max job duration) is configured in Firestore via the UI after first registration.

### Running

Run directly: `npm start`

For production: use PM2 or node-windows to run as a persistent service with auto-restart.

---

## Optimization Results Extraction

### Approach: EA writes per-pass data via Framework

Each strategy's `OnTester()` function uses `TesterExport.mqh` from the framework:

1. Collects `TesterStatistics()` values: profit, PF, DD%, trades, expected payoff, etc.
2. Reads the current input parameter values (global variables in the pass context)
3. Filters: only writes if profit > 0 AND drawdown < 30%
4. Appends one line to a CSV/JSON file in MQL5/Files/

During optimization, each pass runs in a separate MT5 agent process. Each agent has its own `MQL5/Files/` sandbox directory (`Tester/Agent-127.0.0.1-300X/MQL5/Files/`). Multiple agents run in parallel but each writes to its own directory — no file conflicts.

After optimization completes:
1. Worker scans all `Tester/Agent-*/MQL5/Files/` directories for result files
2. Merges results from all agents
3. Uploads to Firestore as individual pass documents (batched writes, 500 per batch)
4. Computes resultSummary for the job document

### Per-EA Boilerplate (minimal)

Each strategy has a small block in OnTester() listing its own input parameters:

```mql5
double OnTester()
{
    double fitness = CalcFitness();  // from StrategyBase.mqh

    string names[]  = {"InpAsianEnd", "InpBreakoutBuffer", "InpRiskReward"};
    double values[] = {InpAsianEnd,    InpBreakoutBuffer,   InpRiskReward};
    TesterExportPass(names, values, fitness);  // from TesterExport.mqh

    return fitness;
}
```

---

## Decisions Log

| Topic | Decision | Rationale |
|-------|----------|-----------|
| UI Framework | React + Vite + Tailwind | Consistent with existing dashboard, fast DX |
| Worker runtime | Node.js | Same ecosystem as Firebase, firebase-admin SDK |
| Job queue | Firestore transactions | Simple, reliable at this scale, no extra infra |
| Results storage | Individual Firestore docs per pass | Only profitable + DD<30% passes stored, keeps volume manageable |
| Results extraction | EA writes via TesterExport.mqh | Pragmatic, EA controls the data, worker collects after |
| Strategy deployment | Per-strategy .ex5 upload to Firebase Storage | Simple, granular, each strategy independently versioned |
| Versioning | Auto by .ex5 hash, auto-increment number | Hash-based dedup, git hash for code traceability |
| Custom indicators | Avoid iCustom() entirely | All logic via #include or built-in indicators, .ex5 is self-contained |
| Symbol mapping | Per-worker config in Firestore | Prefix/suffix/overrides, managed via UI |
| Authentication | Google Sign-in | Simple, secure, whitelist user email |
| Worker config | Local: Firebase creds + MT5 path only | Everything else in Firestore, managed via UI |
| Broker data | Pre-download manually | Simple, reliable, done once per worker setup |
| Max job duration | 8 hours default | Configurable, watchdog kills MT5 if exceeded |
| Job cancellation | Worker checks every 30s | Kills MT5 process if job cancelled in UI |
| Batch grouping | No (individual jobs) | Keep data model simple |
| Version deletion | Cascade with warning | Deletes Firestore doc + Storage file + linked jobs + results |
| Notifications | Deferred | Not in MVP, add later |
| CSV export | Deferred | Not in MVP, add later |
| Old dashboard | Archived | Kept in repo for reference, not maintained |

---

## Implementation Phases

### Phase 1: Foundation & Project Setup
- Restructure repo: create `platform/`, `worker/` directories
- Set up npm workspaces in root `package.json`
- Create `platform/shared/` with TypeScript types and constants
- Create new Firebase project, initialize (Hosting, Firestore, Storage)
- Write Firestore security rules and indexes
- Write Storage security rules
- Configure Firebase Auth (Google Sign-in provider)

### Phase 2: MQL5 Framework
- Create `Include/Framework/StrategyBase.mqh` (shared OnTester, HasPosition, CloseAllPositions)
- Create `Include/Framework/TradeManager.mqh` (trailing stop, breakeven, partial close)
- Create `Include/Framework/TesterExport.mqh` (per-pass result writing)
- Update existing EAs to use framework includes (remove duplicated code)
- Compile and verify all strategies still work

### Phase 3: Deploy CLI
- Build `platform/cli/` with firebase-admin SDK
- Implement .mq5 input parser (regex-based, extracts name/type/default/label/group)
- Implement .ex5 hash computation + dedup check
- Implement Firebase Storage upload
- Implement Firestore strategy/version document creation
- Implement git hash capture
- Add `npm run deploy` script to root package.json
- Test: deploy all existing strategies

### Phase 4: Firebase Management UI
- Set up `platform/ui/` (React + Vite + Tailwind + Firebase client SDK)
- Implement auth (Google Sign-in, protected routes)
- Build Dashboard page
- Build Strategies page (list, versions, inputs, delete with cascade)
- Build Optimizations page (batch job creation wizard)
- Build Jobs page (queue view, filters, cancel, retry)
- Build Results page (pass table, sorting, filtering)
- Build Workers page (status, config, symbol mapping)
- Deploy to Firebase Hosting

### Phase 5: Worker App
- Build `worker/` Node.js app with TypeScript
- Implement Firebase Admin SDK connection
- Implement worker registration and heartbeat
- Implement job poller with Firestore transaction-based claiming
- Implement .ini and .set file generation (UTF-16LE encoding)
- Implement MT5 process runner with watchdog (timeout, cancellation check)
- Implement result file collection from agent directories
- Implement result parsing and Firestore upload (batched writes)
- Implement stale job recovery
- Implement graceful shutdown
- Test end-to-end: create job in UI → worker claims → MT5 runs → results appear in UI

### Phase 6: Integration & Hardening
- End-to-end testing with real MT5 optimization
- Windows worker setup documentation / script
- Error handling polish (network failures, MT5 edge cases)
- UI polish (loading states, error messages, empty states)
- Verify cascade delete works correctly
- Verify stale job recovery works correctly
- Verify multi-worker scenario (two workers, no duplicate job claims)
