# Strategy 3: EMA Crossover with Pullback Entry

## Overview

Uses a fast/slow EMA crossover to establish trend direction, then waits for a pullback to the EMA zone before entering. This avoids the classic whipsaw problem of entering directly on crossover. A higher-timeframe trend filter ensures we only trade in the direction of the larger trend.

## Instruments & Timeframes

| Instrument | Primary TF | Expected Behavior |
|-----------|-----------|-------------------|
| XAUUSD | 5m, 15m | Strong trends, good pullback structure |
| DJ30 | 5m, 15m | Clean intraday trends during US session |
| NAS100 | 5m, 15m | Strong momentum, deep pullbacks to fill gaps |
| BTCUSD | 5m, 15m | Extended trends with regular pullbacks |

## Logic

### Indicators Required

1. **Fast EMA** (e.g., 8-period) on primary TF
2. **Slow EMA** (e.g., 21-period) on primary TF
3. **Trend EMA** on higher TF (e.g., 50-period on H1/H4) — direction filter
4. **ATR** on primary TF — for trailing stop calculation

### Phase 1: Trend Detection (EMA Crossover)

- **Bullish trend:** Fast EMA crosses above Slow EMA
- **Bearish trend:** Fast EMA crosses below Slow EMA
- Trend remains valid until opposite crossover occurs

### Phase 2: Pullback Detection

After a bullish crossover, wait for price to pull back:

**BUY Pullback Conditions:**
- Trend is bullish (Fast EMA > Slow EMA)
- Price pulls back and touches or crosses below Fast EMA (enters the EMA zone)
- Price then closes back above Fast EMA (pullback complete, momentum resuming)
- HTF Trend EMA confirms direction (close > HTF EMA for buys)
- No existing position

**SELL Pullback Conditions:**
- Trend is bearish (Fast EMA < Slow EMA)
- Price pulls back and touches or crosses above Fast EMA
- Price then closes back below Fast EMA
- HTF Trend EMA confirms (close < HTF EMA for sells)
- No existing position

### Exit Rules

**Primary: ATR Trailing Stop**
- Initial SL: Entry price +/- ATR * SL multiplier
- Trail: Move SL to lock in profits as price moves favorably
- Trail step: Every N points of profit, move SL by N points (or ATR-based)

**Secondary Exits:**
- Opposite EMA crossover (trend reversal)
- Fixed TP at ATR * TP multiplier (optional, can disable for pure trend-following)

### Risk Management

- **Position size:** Calculated from 1% account risk and initial SL distance
- **Max concurrent trades:** 1
- **Session filter (optional):** Only trade during active sessions

## Input Parameters

| Parameter | Type | Default | Optimize Range | Step | Description |
|-----------|------|---------|---------------|------|-------------|
| InpFastEMA | int | 8 | 5-13 | 2 | Fast EMA period |
| InpSlowEMA | int | 21 | 15-30 | 3 | Slow EMA period |
| InpHTF | ENUM_TIMEFRAMES | H1 | H1/H4 | - | Higher timeframe for trend filter |
| InpHTF_EMA | int | 50 | 30-100 | 10 | HTF trend EMA period |
| InpATR_Period | int | 14 | 10-20 | 5 | ATR period |
| InpATR_SL_Mult | double | 1.5 | 1.0-3.0 | 0.5 | ATR multiplier for initial SL |
| InpATR_TP_Mult | double | 3.0 | 2.0-5.0 | 1.0 | ATR multiplier for TP (0=disabled) |
| InpTrailATR_Mult | double | 1.0 | 0.5-2.0 | 0.5 | ATR multiplier for trailing stop |
| InpPullbackMode | int | 1 | 1-2 | 1 | 1=Touch FastEMA, 2=Cross into EMA zone |
| InpRiskPercent | double | 1.0 | - | - | Risk per trade (% of balance) |
| InpMagicNumber | ulong | 100003 | - | - | Magic number |

## Indicators Registered for Export

| Indicator | Type | Buffers | Location |
|-----------|------|---------|----------|
| EMA_{fast} | iMA | 1 (value) | overlay |
| EMA_{slow} | iMA | 1 (value) | overlay |
| EMA_{htf_period}_{htf} | iMA | 1 (value) | overlay |
| ATR_{period} | iATR | 1 (value) | panel |

## Edge & Rationale

- Crossover establishes trend, pullback provides better entry price (lower risk)
- Entering on pullback instead of crossover dramatically reduces whipsaws
- ATR trailing stop adapts to market volatility automatically
- HTF filter keeps you on the right side of the larger trend
- Trend-following captures the "fat tail" moves

## Risks

- Choppy/ranging markets generate crossovers that never develop into trends
- Pullback may continue into a full reversal (mitigated by SL)
- Trailing stop may get hit on volatile pullbacks within a valid trend
- HTF filter can be slow to react on TF changes

## Optimization Priority

1. Fast/Slow EMA periods (defines the trend sensitivity)
2. ATR SL/TP multipliers (risk/reward calibration)
3. HTF and HTF EMA period (trend direction accuracy)
4. Pullback mode (touch vs cross)
