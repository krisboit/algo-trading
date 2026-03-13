# Strategy 4: Momentum Breakout with Trailing Stop

## Overview

Catches strong intraday momentum moves by entering when price shows clear directional force — breaking recent highs/lows with increasing volume and MACD confirmation. Uses an ATR-based trailing stop to ride the move as far as possible. Designed for instruments that make large intraday swings (NAS100, BTCUSD, XAUUSD).

## Instruments & Timeframes

| Instrument | Primary TF | Expected Behavior |
|-----------|-----------|-------------------|
| XAUUSD | 5m, 15m | Large directional moves on news/sessions |
| DJ30 | 15m | Steady trends, less volatile than NAS100 |
| NAS100 | 5m, 15m | Large momentum moves, gap fills |
| BTCUSD | 5m, 15m | Extended trending phases with high ATR |

## Logic

### Indicators Required

1. **Donchian Channel** (period) — defines breakout levels (highest high / lowest low of N bars)
2. **MACD** (fast, slow, signal) — momentum confirmation
3. **ATR** (period) — volatility-based stop loss and trailing
4. **Volume SMA** (period) — volume confirmation (optional, not available on all symbols)

### Entry Rules

**BUY Entry (Bullish Momentum):**
- Price closes above the upper Donchian Channel (N-bar high breakout)
- MACD histogram > 0 AND histogram increasing (momentum accelerating)
- ATR > minimum threshold (sufficient volatility for profit potential)
- No existing position

**SELL Entry (Bearish Momentum):**
- Price closes below the lower Donchian Channel (N-bar low breakout)
- MACD histogram < 0 AND histogram decreasing (momentum accelerating)
- ATR > minimum threshold
- No existing position

### Exit Rules

**Primary: ATR Trailing Stop**
- Initial SL: Entry +/- ATR * SL multiplier
- Trailing: After price moves ATR * activation distance in profit, begin trailing at ATR * trail multiplier
- Trail updates every bar close (not tick-by-tick)

**Secondary Exits:**
- **Momentum fade:** MACD histogram reverses direction for N consecutive bars
- **Fixed TP (optional):** ATR * TP multiplier (can be disabled for pure trailing)
- **Breakeven move:** After N*ATR profit, move SL to breakeven + buffer

### Risk Management

- **Position size:** Calculated from 1% account risk and SL distance
- **Max concurrent trades:** 1
- **ATR minimum filter:** Skip trades when ATR is below threshold (dead market)

## Input Parameters

| Parameter | Type | Default | Optimize Range | Step | Description |
|-----------|------|---------|---------------|------|-------------|
| InpDonchian_Period | int | 20 | 10-30 | 5 | Donchian Channel period (breakout lookback) |
| InpMACD_Fast | int | 12 | 8-16 | 4 | MACD fast period |
| InpMACD_Slow | int | 26 | 20-34 | 4 | MACD slow period |
| InpMACD_Signal | int | 9 | 5-13 | 4 | MACD signal period |
| InpATR_Period | int | 14 | 10-20 | 5 | ATR period |
| InpATR_SL_Mult | double | 2.0 | 1.0-3.0 | 0.5 | ATR multiplier for initial SL |
| InpATR_TP_Mult | double | 0.0 | 0-5.0 | 1.0 | ATR multiplier for TP (0=trailing only) |
| InpATR_Trail_Mult | double | 1.5 | 1.0-3.0 | 0.5 | ATR trailing stop distance |
| InpATR_Activation | double | 1.0 | 0.5-2.0 | 0.5 | ATR distance to activate trailing |
| InpBreakevenATR | double | 1.0 | 0.5-2.0 | 0.5 | ATR profit to move SL to breakeven (0=disabled) |
| InpMomentumFadeBars | int | 3 | 2-5 | 1 | Consecutive bars of fading momentum to exit |
| InpMinATR | double | 0.0 | - | - | Minimum ATR to allow entry (instrument-specific) |
| InpRiskPercent | double | 1.0 | - | - | Risk per trade (% of balance) |
| InpMagicNumber | ulong | 100004 | - | - | Magic number |

## Indicators Registered for Export

| Indicator | Type | Buffers | Location |
|-----------|------|---------|----------|
| Donchian_{period} | Custom (iCustom or manual) | 2 (upper, lower) | overlay |
| MACD_{fast}_{slow}_{signal} | iMACD | 3 (main, signal, histogram) | panel |
| ATR_{period} | iATR | 1 (value) | panel |

### Note on Donchian Channel

MT5 doesn't have a built-in Donchian Channel indicator. We'll compute it manually using `iHighest()` and `iLowest()` functions, then register it as a custom overlay for the exporter by storing the values in arrays.

## Edge & Rationale

- Momentum breakouts capture the initial phase of large moves
- Donchian Channel is a classic trend-following tool (Turtle Traders)
- MACD confirms that momentum is accelerating, not just a price spike
- ATR trailing stop adapts to volatility and lets winners run
- Breakeven move protects capital once trade is in profit

## Risks

- False breakouts in ranging markets (mitigated by MACD confirmation)
- Slippage on fast breakouts can worsen entry price
- Trailing stop may be too tight in volatile markets (ATR multiplier tuning)
- BTCUSD weekend gaps can jump past stop loss

## Optimization Priority

1. Donchian period (defines breakout sensitivity)
2. ATR SL/Trail multipliers (risk calibration)
3. MACD parameters (momentum filter sensitivity)
4. Breakeven and activation distances
