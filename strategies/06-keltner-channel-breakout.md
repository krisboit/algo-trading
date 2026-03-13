# Strategy 6: Keltner Channel Breakout

## Overview

Captures mean-reversion entries when price briefly pierces a Keltner Channel band and snaps back inside. A candle that opens outside the channel and closes back inside signals rejection of the extreme, confirmed by minimum volatility (ATR filter) to avoid low-energy, choppy markets. Take profit targets the opposite band for a full channel traverse.

## Instruments & Timeframes

| Instrument | Primary TF | Expected Behavior |
|-----------|-----------|-------------------|
| XAUUSD | 5m, 15m, 1H | Good KC rejection signals during ranging sessions |
| DJ30 | 15m, 1H | Clean channel bounces during US session |
| NAS100 | 15m, 1H | Works well in intraday ranges, fails in strong trends |
| BTCUSD | 5m, 15m | Volatile enough to trigger ATR filter consistently |
| EURUSD | 15m, 1H, 4H | Classic forex mean-reversion on KC bands |

## Logic

### Indicators Required

1. **EMA** (period 20) on primary TF — Keltner Channel middle line
2. **ATR** (period 10) on primary TF — Keltner Channel band width (multiplied by 2.0)
3. **ATR** (period 5) on primary TF — Volatility filter (minimum activity threshold)

### Keltner Channel Calculation

- **Middle Line:** EMA(20, close)
- **Upper Band:** EMA + ATR(10) × 2.0
- **Lower Band:** EMA - ATR(10) × 2.0

### Entry Rules

**BUY (Long) Entry:**
- Signal candle opens **below** the lower KC band
- Signal candle closes **above** the lower KC band (rejection/snap-back)
- ATR(5) > 5 pips (sufficient volatility)
- No existing position
- Entry price = signal candle close + 3 pips

**SELL (Short) Entry:**
- Signal candle opens **above** the upper KC band
- Signal candle closes **below** the upper KC band (rejection/snap-back)
- ATR(5) > 5 pips (sufficient volatility)
- No existing position
- Entry price = signal candle close - 3 pips

### Exit Rules

**Stop Loss:**
- BUY: Signal candle low - spread (just below the wick)
- SELL: Signal candle high + spread (just above the wick)

**Take Profit:**
- BUY: Upper KC band (full channel traverse)
- SELL: Lower KC band (full channel traverse)

**Breakeven at 1RR:**
- When price reaches 1R profit (distance equal to SL distance), SL is moved to entry price
- Checked every tick to ensure the level is not missed
- Applied only once per trade

### Risk Management

- **Position size:** Calculated from 1% account risk and SL distance (uses `CalcLotSize`)
- **Max concurrent trades:** 1 (one position at a time per symbol)
- **Minimum stop validation:** Rejects trades where SL or TP distance is below broker minimum

## Input Parameters

| Parameter | Type | Default | Optimize Range | Step | Description |
|-----------|------|---------|---------------|------|-------------|
| InpKC_EMA_Period | int | 20 | 14-30 | 2 | KC EMA period (middle line) |
| InpKC_ATR_Period | int | 10 | 7-14 | 1 | KC ATR period (band width) |
| InpKC_ATR_Mult | double | 2.0 | 1.5-3.0 | 0.5 | KC ATR multiplier |
| InpATR_Filter_Period | int | 5 | 3-10 | 1 | ATR volatility filter period |
| InpATR_Min_Pips | double | 5.0 | 3.0-10.0 | 1.0 | Minimum ATR in pips |
| InpEntryOffset | double | 3.0 | 1.0-5.0 | 1.0 | Entry offset from candle close (pips) |
| InpRiskPercent | double | 1.0 | - | - | Risk per trade (% of balance) |
| InpMagicNumber | ulong | 100006 | - | - | Magic number |

## Edge & Rationale

- Keltner Channels use ATR-based bands, making them adaptive to current volatility (unlike fixed-deviation Bollinger Bands)
- The open-outside/close-inside pattern identifies genuine rejection candles, not just touches
- ATR(5) filter ensures trades only occur when the market has enough energy to follow through
- TP at the opposite band provides a naturally large R:R when the channel is wide
- Breakeven at 1RR protects capital while allowing the trade to reach full target

## Risks

- Strong trending markets will push price through the KC band without snapping back, causing the signal candle pattern to fail
- The 3-pip entry offset may cause entries at worse prices than the signal close during fast markets
- TP at the opposite band can be very far away — price may stall at the middle line (EMA)
- ATR(5) > 5 pips filter is instrument-dependent; may need adjustment per pair/index
- No time-based exit — positions can remain open indefinitely if neither SL, BE SL, nor TP is hit

## Optimization Priority

1. KC ATR multiplier (channel width — most impactful on signal quality)
2. ATR minimum pips (volatility filter threshold — controls trade frequency)
3. KC EMA period (middle line responsiveness)
4. Entry offset (balance between confirmation and slippage)
5. KC ATR period (band calculation smoothness)
