import type {
  StrategyData, TimeframeData, CandlestickData, VolumeData,
  LineData, TradeMarker, IndicatorConfig, IndicatorLocation,
} from '../types/strategy';
import { getIndicatorColors, resetColorIndex } from './colors';

/**
 * Known overlay indicators (shown on main chart)
 */
const OVERLAY_PATTERNS = [
  /^SMA/i, /^EMA/i, /^WMA/i, /^DEMA/i, /^TEMA/i, /^FRAMA/i,
  /^BB/i, /^Bollinger/i,
  /^Envelope/i,
  /^Ichimoku/i,
  /^SAR/i, /^Parabolic/i,
  /^MA_/i, /^AMA/i,
  /^VWAP/i,
];

/**
 * Determine if indicator is overlay or panel
 */
export function classifyIndicator(name: string): IndicatorLocation {
  for (const pattern of OVERLAY_PATTERNS) {
    if (pattern.test(name)) return 'overlay';
  }
  return 'panel';
}

/**
 * Transform candle arrays to chart-ready format
 */
export function transformCandles(tfData: TimeframeData): CandlestickData[] {
  return tfData.candles.map(([time, open, high, low, close]) => ({
    time,
    open,
    high,
    low,
    close,
  }));
}

/**
 * Transform candle arrays to volume data
 */
export function transformVolume(tfData: TimeframeData): VolumeData[] {
  return tfData.candles.map(([time, open, , , close, volume]) => ({
    time,
    value: volume,
    color: close >= open
      ? 'rgba(34, 197, 94, 0.3)'
      : 'rgba(239, 68, 68, 0.3)',
  }));
}

/**
 * Transform indicator data to line series
 * Returns an array of LineData[] (one per buffer)
 */
export function transformIndicator(
  data: number[][],
  bufferIndex: number
): LineData[] {
  return data
    .filter(row => {
      const val = row[bufferIndex + 1];
      return val !== null && val !== undefined && isFinite(val);
    })
    .map(row => ({
      time: row[0],
      value: row[bufferIndex + 1],
    }));
}

/**
 * Build indicator configs from strategy data for a specific timeframe
 */
export function buildIndicatorConfigs(
  data: StrategyData,
  timeframe: string
): IndicatorConfig[] {
  resetColorIndex();
  const tfData = data.data[timeframe];
  if (!tfData) return [];

  const configs: IndicatorConfig[] = [];

  for (const [name, indData] of Object.entries(tfData.indicators)) {
    const location = classifyIndicator(name);
    const colors = getIndicatorColors(indData.buffers.length);

    configs.push({
      name,
      location,
      visible: true,
      buffers: indData.buffers,
      colors,
    });
  }

  return configs;
}

/**
 * Transform orders to trade markers
 */
export function transformTradeMarkers(data: StrategyData): TradeMarker[] {
  return data.orders
    .filter(order => order.closeTime > 0)
    .map(order => ({
      orderTicket: order.ticket,
      type: order.type,
      entryTime: order.openTime,
      entryPrice: order.openPrice,
      exitTime: order.closeTime,
      exitPrice: order.closePrice,
      profit: order.netProfit,
      isWin: order.netProfit >= 0,
    }));
}

/**
 * Transform equity array to line data
 */
export function transformEquityBalance(data: StrategyData): LineData[] {
  return data.equity.map(([time, balance]) => ({ time, value: balance }));
}

export function transformEquityEquity(data: StrategyData): LineData[] {
  return data.equity.map(([time, , equity]) => ({ time, value: equity }));
}

/**
 * Calculate drawdown series from equity curve
 */
export function calculateDrawdownSeries(data: StrategyData): LineData[] {
  let peak = 0;
  return data.equity.map(([time, , equity]) => {
    if (equity > peak) peak = equity;
    const dd = peak > 0 ? ((peak - equity) / peak) * 100 : 0;
    return { time, value: -dd };
  });
}
