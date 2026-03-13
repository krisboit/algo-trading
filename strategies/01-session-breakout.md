# Strategy 1: Session Breakout

## Overview

Trades the breakout of the Asian session consolidation range during the high-volume London and New York sessions ("kill zones"). Markets tend to consolidate during low-volume Asian hours then make directional moves when European and American institutions begin trading.

## Instruments & Timeframes

| Instrument | Primary TF | Expected Behavior |
|-----------|-----------|-------------------|
| XAUUSD | 5m, 15m | Strong London/NY session moves, respects Asian range |
| DJ30 | 5m, 15m | Clean US session breakouts |
| NAS100 | 5m, 15m | Strong momentum after range break |
| BTCUSD | 5m, 15m | Less session-dependent but still shows Asian lull |

## Logic

### Range Definition (Asian Session)

1. Define the Asian session window: **00:00 - 08:00 GMT** (configurable)
2. Track the **high** and **low** of this window
3. Require minimum range size (filter out too-tight ranges = no volatility)
4. Require maximum range size (filter out already-trending days = range already broken)

### Entry Rules

**Kill Zone Windows (configurable):**
- London Kill Zone: **08:00 - 11:00 GMT**
- New York Kill Zone: **13:00 - 16:00 GMT**

**BUY Entry:**
- Price breaks **above** Asian High + buffer (in points)
- Current time is within a Kill Zone
- No existing position open

**SELL Entry:**
- Price breaks **below** Asian Low - buffer (in points)
- Current time is within a Kill Zone
- No existing position open

### Exit Rules

- **Stop Loss:** Opposite side of the Asian range (if entered long on break of high, SL = Asian Low minus buffer)
- **Take Profit:** Risk-to-Reward ratio applied to SL distance (default 1.5:1)
- **Time Exit:** Close any open position at end of NY session (configurable, e.g., 21:00 GMT)
- **Max trades per day:** 1 or 2 (configurable) — prevents overtrading on whipsaw days

### Risk Management

- **Position size:** Calculated from 1% account risk and SL distance
- **Max SL distance filter:** Skip trade if SL would exceed N points (instrument-dependent)

## Input Parameters

| Parameter | Type | Default | Optimize Range | Step | Description |
|-----------|------|---------|---------------|------|-------------|
| InpAsianStart | int | 0 | - | - | Asian session start hour (GMT) |
| InpAsianEnd | int | 8 | 7-9 | 1 | Asian session end hour (GMT) |
| InpLondonStart | int | 8 | 7-9 | 1 | London KZ start (GMT) |
| InpLondonEnd | int | 11 | 10-12 | 1 | London KZ end (GMT) |
| InpNYStart | int | 13 | 12-14 | 1 | NY KZ start (GMT) |
| InpNYEnd | int | 16 | 15-17 | 1 | NY KZ end (GMT) |
| InpSessionClose | int | 21 | - | - | Force close hour (GMT) |
| InpBreakoutBuffer | int | 5 | 0-20 | 5 | Buffer above/below range (points) |
| InpRiskReward | double | 1.5 | 1.0-3.0 | 0.5 | Take Profit as multiple of SL |
| InpMinRangePoints | int | 50 | 20-100 | 10 | Min Asian range size (points) |
| InpMaxRangePoints | int | 500 | 200-1000 | 100 | Max Asian range size (points) |
| InpMaxTradesPerDay | int | 2 | 1-3 | 1 | Max entries per day |
| InpRiskPercent | double | 1.0 | - | - | Risk per trade (% of balance) |
| InpMagicNumber | ulong | 100001 | - | - | Magic number |

## Indicators Used

- None required (pure price action / session-based)
- **Optional overlay:** Asian range box visualization (High/Low horizontal lines)

## Edge & Rationale

- Institutional order flow creates predictable volatility expansion at session opens
- Asian range acts as natural support/resistance (liquidity pool)
- Limited daily exposure (only trade during kill zones = ~6 hours max)
- Natural stop loss placement (opposite side of range)
- Well-documented statistical edge in forex and commodities

## Risks

- Whipsaw days where price breaks both sides (mitigated by max trades per day)
- News events can cause false breakouts (could add news filter later)
- Range too tight on low-volatility days (mitigated by minimum range filter)
- BTCUSD is 24/7 so Asian session is less defined (may underperform)

## Optimization Priority

1. Kill zone hours (most impactful — aligns with actual institutional activity)
2. Risk-to-reward ratio
3. Breakout buffer size
4. Min/max range filters
