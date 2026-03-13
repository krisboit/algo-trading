# Strategy 5: Order Block + Fair Value Gap (Smart Money)

## Overview

Identifies institutional order blocks (supply/demand zones) and fair value gaps (imbalances) on a higher timeframe, then enters on the lower timeframe when price returns to fill these zones. Based on Smart Money Concepts (SMC/ICT methodology) — trades the idea that institutions leave "footprints" in the form of specific candle structures, and price tends to return to these zones before continuing.

## Instruments & Timeframes

| Instrument | Primary TF (Entry) | Structure TF (Zones) | Expected Behavior |
|-----------|-------------------|---------------------|-------------------|
| XAUUSD | 3m, 5m | H1 | Respects institutional zones well |
| DJ30 | 5m, 15m | H1, H4 | Clean order block reactions |
| NAS100 | 5m, 15m | H1, H4 | Strong FVG fills before continuation |
| BTCUSD | 5m, 15m | H1, H4 | Whale order blocks visible on H1+ |

## Key Concepts

### Order Block (OB)
The **last opposing candle before an impulsive move**. It represents the zone where institutional orders were placed.

- **Bullish OB:** Last bearish candle before a strong bullish impulse (demand zone)
- **Bearish OB:** Last bullish candle before a strong bearish impulse (supply zone)

**Detection criteria:**
1. Find an impulse move: N consecutive candles in one direction, OR a single candle with body > M * ATR
2. The candle immediately before the impulse start is the Order Block
3. The OB zone = [candle low, candle high]

### Fair Value Gap (FVG)
A **three-candle pattern** where the wicks of candle 1 and candle 3 don't overlap, leaving a "gap" that price tends to fill.

- **Bullish FVG:** candle_1.high < candle_3.low (gap up — price wants to come back down to fill)
- **Bearish FVG:** candle_1.low > candle_3.high (gap down — price wants to come back up to fill)

**The FVG zone** = the unfilled gap between the wicks.

### Liquidity Sweep
Price takes out a recent swing high/low (stops retail traders) before reversing. This confirms institutional activity.

## Logic

### Phase 1: Zone Identification (Higher TF)

On every new HTF bar, scan for:

1. **Fresh Order Blocks** in the last N bars:
   - Find impulse moves (close-to-close > ATR * impulse_multiplier)
   - Mark the pre-impulse candle as OB
   - Track OB as "fresh" until price returns to it (then it's "tested")
   - Max N active OBs at a time (oldest get removed)

2. **Fresh Fair Value Gaps** in the last N bars:
   - Scan 3-candle windows for non-overlapping wicks
   - Track FVG zone boundaries
   - FVG becomes "filled" when price passes through the zone

### Phase 2: Entry Trigger (Primary TF)

**BUY Entry (at Bullish OB or Bearish FVG fill):**
- Price enters a fresh Bullish Order Block zone (demand)
- OR price fills a Bearish FVG (comes back down into the gap)
- Confirm with: RSI showing oversold on entry TF (momentum exhaustion)
- HTF trend is bullish (price above HTF EMA)
- No existing position

**SELL Entry (at Bearish OB or Bullish FVG fill):**
- Price enters a fresh Bearish Order Block zone (supply)
- OR price fills a Bullish FVG (comes back up into the gap)
- Confirm with: RSI showing overbought on entry TF
- HTF trend is bearish (price below HTF EMA)
- No existing position

### Phase 3: Liquidity Sweep Bonus (Optional Enhancement)

- If price sweeps a recent swing high/low (takes out by N points) before entering the OB/FVG zone, increase confidence
- This is a boolean flag that can be used to filter or not

### Exit Rules

- **Stop Loss:** Beyond the OB zone (for OB entries) or beyond the FVG zone (for FVG entries) + buffer
- **Take Profit:** Next opposing zone, or fixed RR ratio (e.g., 2:1 or 3:1)
- **Partial close:** Close 50% at 1:1 RR, trail remainder

### Risk Management

- **Position size:** Calculated from 1% account risk and SL distance
- **Max concurrent trades:** 1
- **Zone expiry:** OBs and FVGs older than N HTF bars are discarded (stale zones)

## Input Parameters

| Parameter | Type | Default | Optimize Range | Step | Description |
|-----------|------|---------|---------------|------|-------------|
| InpHTF | ENUM_TIMEFRAMES | H1 | H1/H4 | - | Zone identification timeframe |
| InpOB_ImpulseATR | double | 1.5 | 1.0-3.0 | 0.5 | ATR multiple to qualify as impulse |
| InpOB_MaxAge | int | 50 | 30-100 | 10 | Max HTF bars before OB expires |
| InpOB_MaxZones | int | 5 | 3-8 | 1 | Max active OB zones tracked |
| InpFVG_Enabled | bool | true | - | - | Enable FVG detection |
| InpFVG_MinGapATR | double | 0.3 | 0.1-0.5 | 0.1 | Min FVG size as ATR fraction |
| InpRSI_Period | int | 14 | 7-21 | 7 | RSI period for entry confirmation |
| InpRSI_OB_Level | double | 30.0 | 25-40 | 5 | RSI oversold for buy entries |
| InpRSI_OS_Level | double | 70.0 | 60-75 | 5 | RSI overbought for sell entries |
| InpHTF_EMA | int | 50 | 30-100 | 20 | HTF EMA for trend direction |
| InpRiskReward | double | 2.0 | 1.5-3.0 | 0.5 | Risk-to-reward ratio |
| InpSL_Buffer | int | 10 | 5-30 | 5 | SL buffer beyond zone (points) |
| InpUsePartialClose | bool | true | - | - | Close 50% at 1:1 |
| InpUseLiqSweep | bool | false | true/false | - | Require liquidity sweep |
| InpSwingLookback | int | 20 | 10-40 | 10 | Bars to look back for swing H/L |
| InpRiskPercent | double | 1.0 | - | - | Risk per trade (% of balance) |
| InpMagicNumber | ulong | 100005 | - | - | Magic number |

## Indicators Registered for Export

| Indicator | Type | Buffers | Location |
|-----------|------|---------|----------|
| RSI_{period} | iRSI | 1 (value) | panel |
| EMA_{htf_period}_{htf} | iMA | 1 (value) | overlay |
| ATR_{period} | iATR (HTF) | 1 (value) | panel |

### Custom Data for Visualization

The OB and FVG zones will be stored as metadata in indicator-like arrays so they can be visualized as horizontal boxes on the chart:
- OB_Zones: [time_start, price_high, price_low, type (bull/bear), status (fresh/tested)]
- FVG_Zones: [time_start, price_high, price_low, type (bull/bear), status (fresh/filled)]

(This is a stretch goal — initially they'll just be tracked internally and not exported as visual data.)

## Edge & Rationale

- Order blocks represent actual institutional order flow footprints
- FVGs represent market inefficiency — price seeks efficiency by filling gaps
- Multi-timeframe approach: higher TF for structure, lower TF for entry = better RR
- RSI confirmation reduces false entries at zones
- Partial close at 1:1 locks in profit and lets remainder run

## Risks

- Zone identification is inherently approximate — edge of zone can vary
- Not all OBs hold — some get broken through (mitigated by SL)
- Complex logic with many parameters — overfitting risk during optimization
- Requires sufficient historical data for zone identification at HTF
- More subjective than pure indicator strategies — code must closely match SMC theory

## Optimization Priority

1. OB impulse ATR multiplier (defines what counts as institutional activity)
2. Risk-to-reward ratio
3. RSI levels (entry timing)
4. HTF EMA period (trend accuracy)
5. OB max age (zone relevance)
6. FVG minimum size
