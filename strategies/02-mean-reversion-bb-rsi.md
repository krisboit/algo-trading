# Strategy 2: Mean Reversion (Bollinger Bands + RSI)

## Overview

Fades price extremes by entering counter-trend when price touches Bollinger Band boundaries with RSI confirmation. A trend filter (ADX or HTF SMA) prevents trading against strong trends, ensuring the strategy only operates during ranging/consolidating market conditions where mean reversion has the highest probability.

## Instruments & Timeframes

| Instrument | Primary TF | Expected Behavior |
|-----------|-----------|-------------------|
| XAUUSD | 3m, 5m, 15m | Mean-reverts well in consolidation, strong trends kill it |
| DJ30 | 5m, 15m | Good intraday ranges during low-news periods |
| NAS100 | 5m, 15m | Ranges before US open, trends during session |
| BTCUSD | 3m, 5m | Good range-bound behavior during Asian/European hours |

## Logic

### Indicators Required

1. **Bollinger Bands** (period, deviation) on primary TF — defines overbought/oversold zones
2. **RSI** (period) on primary TF — confirms momentum exhaustion
3. **ADX** (period) on primary TF — trend strength filter (only trade when ADX < threshold)
4. **SMA** on higher TF (optional) — additional trend direction context

### Entry Rules

**BUY (Long) Entry:**
- Close price <= Lower Bollinger Band (or within tolerance)
- RSI < Buy Level (e.g., 30 = oversold)
- ADX < ADX Threshold (e.g., 25 = no strong trend)
- No existing position

**SELL (Short) Entry:**
- Close price >= Upper Bollinger Band (or within tolerance)
- RSI > Sell Level (e.g., 70 = overbought)
- ADX < ADX Threshold (e.g., 25 = no strong trend)
- No existing position

### Exit Rules

**Primary Exit (configurable mode):**
- **Mode 1 — Fixed SL/TP:** SL = N points from entry, TP = M points from entry
- **Mode 2 — BB Middle:** TP at middle Bollinger Band (mean reversion target), SL = outer band + buffer
- **Mode 3 — ATR-based:** SL = entry +/- ATR * multiplier, TP = entry +/- ATR * multiplier

**Additional Exits:**
- **Max hold time:** Close after N bars if still open (prevents stuck positions)
- **Reversal exit:** Close if RSI crosses the opposite extreme (e.g., was long, RSI > 70)

### Risk Management

- **Position size:** Calculated from 1% account risk and SL distance
- **Max concurrent trades:** 1 (one position at a time)

## Input Parameters

| Parameter | Type | Default | Optimize Range | Step | Description |
|-----------|------|---------|---------------|------|-------------|
| InpBB_Period | int | 20 | 14-30 | 2 | Bollinger Bands period |
| InpBB_Deviation | double | 2.0 | 1.5-3.0 | 0.5 | BB standard deviation |
| InpRSI_Period | int | 14 | 7-21 | 7 | RSI period |
| InpRSI_BuyLevel | double | 30.0 | 20-40 | 5 | RSI oversold level |
| InpRSI_SellLevel | double | 70.0 | 60-80 | 5 | RSI overbought level |
| InpADX_Period | int | 14 | 10-20 | 5 | ADX period |
| InpADX_Threshold | double | 25.0 | 20-35 | 5 | Max ADX for entry (range filter) |
| InpExitMode | int | 2 | 1-3 | 1 | Exit mode (1=Fixed, 2=BB Middle, 3=ATR) |
| InpFixedSL | int | 50 | 30-100 | 10 | Fixed SL in points (mode 1) |
| InpFixedTP | int | 50 | 30-100 | 10 | Fixed TP in points (mode 1) |
| InpATR_Period | int | 14 | 10-20 | 5 | ATR period (mode 3) |
| InpATR_SL_Mult | double | 1.5 | 1.0-2.5 | 0.5 | ATR SL multiplier (mode 3) |
| InpATR_TP_Mult | double | 1.0 | 0.5-2.0 | 0.5 | ATR TP multiplier (mode 3) |
| InpMaxBarsHold | int | 20 | 10-50 | 10 | Max bars to hold position |
| InpRiskPercent | double | 1.0 | - | - | Risk per trade (% of balance) |
| InpMagicNumber | ulong | 100002 | - | - | Magic number |

## Indicators Registered for Export

| Indicator | Type | Buffers | Location |
|-----------|------|---------|----------|
| BB_{period}_{dev} | iBands | 3 (middle, upper, lower) | overlay |
| RSI_{period} | iRSI | 1 (value) | panel |
| ADX_{period} | iADX | 3 (main, +DI, -DI) | panel |
| SMA_{period}_HTF | iMA (optional) | 1 (value) | overlay |

## Edge & Rationale

- Markets spend ~60-70% of time in ranges — high base rate for mean-reversion signals
- Bollinger Bands provide dynamic S/R based on recent volatility
- RSI filters out touches that still have momentum (only take exhaustion touches)
- ADX filter is critical — prevents catastrophic losses during trends
- High win rate expected (70-80%) but smaller average win than average loss

## Risks

- Sudden trend emergence can cause multiple consecutive losses before ADX catches up
- ADX is a lagging indicator — may allow 1-2 bad trades at trend start
- In very low volatility, BB bands tighten and signals fire too frequently
- Exit mode 2 (BB middle) may give back profits if price reverses before reaching middle

## Optimization Priority

1. ADX threshold (most important — determines when strategy is active)
2. BB period and deviation (defines the range boundaries)
3. RSI levels (entry timing)
4. Exit mode comparison (run each mode separately to find best per instrument)
