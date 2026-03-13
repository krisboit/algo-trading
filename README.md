# Algo Trading Platform

An AI-assisted trading strategy development and optimization platform. Strategies are implemented in MQL5 for MetaTrader 5, with a Firebase-based management system for running optimizations at scale across multiple Windows worker servers.

## Architecture

```
                    ┌─────────────────┐
                    │   Mac (Dev)     │
                    │                 │
                    │  MQL5 Editing   │
                    │  Compile (.ex5) │
                    │  Deploy CLI     │
                    └────────┬────────┘
                             │ deploy
                             ▼
                    ┌─────────────────┐
                    │    Firebase     │
                    │                 │
                    │  Firestore DB   │
                    │  Storage (.ex5) │
                    │  Hosting (UI)   │
                    └───┬─────────┬───┘
                        │         │
              UI access │         │ poll jobs
                        ▼         ▼
              ┌──────────┐  ┌──────────────┐
              │  Browser  │  │ Worker 1..N  │
              │  (React)  │  │  (Windows)   │
              │           │  │  Node.js +   │
              │  Manage   │  │  MT5 Runner  │
              │  strategies│  └──────────────┘
              │  jobs, etc │
              └──────────┘
```

**Three components:**

1. **Local Mac Tooling** — MQL5 strategy development, compilation (via Wine/Whisky), deploy CLI
2. **Firebase Platform (UI)** — React web app for managing strategies, optimization jobs, results, and workers
3. **Worker App** — Node.js service on Windows that runs MT5 optimizations and reports results back to Firebase

## Repository Structure

```
algo-trading/
├── MQL5/                          # MQL5 source & portable-mode structure
│   ├── Experts/                   # Strategy EAs (.mq5 source + .ex5 compiled)
│   └── Include/Framework/         # Shared framework (StrategyBase, TradeManager, TesterExport)
├── platform/                      # Firebase platform (npm workspaces)
│   ├── shared/                    # Shared TypeScript types & constants
│   ├── ui/                        # Management UI (React + Vite + Tailwind)
│   ├── cli/                       # Deploy CLI (uploads strategies to Firebase)
│   └── functions/                 # Cloud Functions (optional)
├── worker/                        # Worker app (Node.js, runs on Windows)
├── scripts/                       # Mac helper scripts (compile, mount, etc.)
├── dashboard/                     # DEPRECATED: old local dashboard
└── plan.md                        # Full architecture specification
```

## Quick Start

### Prerequisites

- Node.js 20+
- npm 9+ (workspaces support)
- Firebase project with Firestore, Storage, and Hosting enabled
- Firebase service account key (for CLI deploy and workers)

### Installation

```bash
# Clone and install all workspaces
git clone <repo-url>
cd algo-trading
npm install

# Build shared types (required before other packages)
npm run build:shared
```

### Development (UI)

```bash
# Copy environment template and fill in Firebase config
cp platform/ui/.env.example platform/ui/.env.local

# Start dev server
npm run dev:ui
```

### Deploy Strategies

```bash
# Compile a strategy (Mac with Wine/Whisky)
./scripts/compile.sh Experts/SessionBreakout.mq5

# Deploy all compiled strategies to Firebase
npm run deploy
```

This scans `MQL5/Experts/` for `.ex5` files, computes SHA-256 hashes for deduplication, uploads new versions to Firebase Storage, and creates version records in Firestore with parsed input parameters.

### Build All

```bash
npm run build:all
```

## MQL5 Framework

All strategies use a shared framework in `MQL5/Include/Framework/`:

| File | Purpose |
|------|---------|
| `StrategyBase.mqh` | `CalcFitness()` (PF * sqrt(Trades) * (1 - DD%/100)), `HasPosition()`, `CloseAllPositions()` |
| `TradeManager.mqh` | ATR trailing stops, breakeven, partial close |
| `TesterExport.mqh` | Per-pass optimization result export to CSV files |

**Rules:**
- No `iCustom()` calls — all indicators use built-in MT5 functions or `#include` files
- Each `.ex5` is fully self-contained
- All strategies use Framework includes for consistent `OnTester()` behavior

### Current Strategies

| Strategy | Description |
|----------|-------------|
| SessionBreakout | Asian session range breakout during London/NY kill zones |
| EMACrossoverPullback | EMA crossover with pullback entry confirmation |
| MeanReversionBBRSI | Bollinger Bands + RSI mean reversion |
| MomentumBreakout | ATR-based momentum breakout system |
| OrderBlockFVG | Order block + fair value gap strategy |
| KeltnerChannelBreakout | Keltner Channel breakout with trend filter |

## Firebase Management UI

React + Vite + Tailwind app hosted on Firebase Hosting.

| Page | Description |
|------|-------------|
| **Dashboard** | Overview stats: strategies, jobs by status, worker health |
| **Strategies** | List strategies with versions, inputs, git hash links. Cascade delete with warnings. |
| **Optimizations** | 5-step batch job creation wizard with form validation |
| **Jobs** | Queue view with status filters, cancel/retry actions |
| **Results** | Sortable pass table: profit, PF, DD%, trades, custom criterion, inputs |
| **Workers** | Worker status, symbol mapping config, stats |

### Authentication

Google Sign-in with Firestore security rules requiring authentication for all reads and writes.

## Worker Setup (Windows)

### Prerequisites

1. MetaTrader 5 installed (portable mode)
2. Broker account logged in, auto-updates disabled
3. Historical tick data pre-downloaded for all test symbols
4. Node.js 20+ installed

### Configuration

Create `worker/config.json`:

```json
{
  "firebaseCredentialsPath": "./firebase-service-account.json",
  "mt5Path": "C:\\Program Files\\MetaTrader 5"
}
```

Place your Firebase service account JSON file alongside it.

Everything else (worker name, symbol mapping, poll intervals) is configured in Firestore via the UI after first registration.

### Running

```bash
cd worker
npm install
npm start
```

For production, use PM2 or node-windows to run as a persistent service:

```bash
pm2 start dist/index.js --name algo-worker
```

### How Workers Operate

1. Register in Firestore on startup (hostname, status=online)
2. Heartbeat every 30s (lastPing update)
3. Poll for pending jobs every 10s
4. Claim jobs via Firestore transaction (prevents duplicate claims)
5. Download `.ex5` from Storage, generate `.ini`/`.set` configs
6. Launch MT5: `terminal64.exe /portable /config:job.ini`
7. Watchdog: timeout (8hr default), cancellation check (30s)
8. Collect results from agent sandbox directories
9. Upload profitable passes to Firestore (batched writes)
10. Stale job recovery: detect orphaned jobs from dead workers

### Symbol Mapping

Each worker has a symbol mapping in Firestore (configurable via UI):

```json
{
  "prefix": "",
  "suffix": "m",
  "overrides": { "DJ30": "US30m" }
}
```

Canonical symbol `XAUUSD` becomes `XAUUSDm` with the suffix. Override `DJ30` becomes `US30m`.

## Firestore Data Model

See `plan.md` for the complete Firestore schema. Key collections:

- `config/settings` — GitHub repo URL, default optimization settings
- `strategies/{name}/versions/{v}` — Strategy versions with inputs, hashes
- `optimization_jobs/{id}` — Job queue with status lifecycle
- `optimization_results/{jobId}/passes/{i}` — Per-pass optimization results
- `workers/{id}` — Worker registration, health, config

## NPM Scripts

| Script | Description |
|--------|-------------|
| `npm start` / `npm run dev:ui` | Start UI dev server |
| `npm run deploy` | Deploy strategies to Firebase |
| `npm run build:shared` | Build shared types package |
| `npm run build:ui` | Build UI for production |
| `npm run build:cli` | Build CLI tool |
| `npm run build:functions` | Build Cloud Functions |
| `npm run build:worker` | Build worker app |
| `npm run build:all` | Build everything (shared first) |

## Tech Stack

- **MQL5** — Strategy EAs for MetaTrader 5
- **TypeScript** — All Node.js/browser code
- **React + Vite + Tailwind** — Management UI
- **Firebase** — Firestore (database), Storage (EA files), Hosting (UI), Auth (Google)
- **Node.js** — Worker app, CLI tool
- **npm workspaces** — Monorepo management

## License

ISC
