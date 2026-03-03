/**
 * Generate realistic sample strategy data for dashboard testing
 * Run: node scripts/generate-sample.mjs
 */
import { writeFileSync } from 'fs';

const SYMBOL = 'EURUSD';
const DIGITS = 5;
const POINT = 0.00001;
const BASE_PRICE = 1.08500;
const SPREAD = 0.00010;
const START_TS = 1704067200; // 2024-01-01 00:00:00 UTC
const BAR_SECONDS = 3600; // H1
const NUM_BARS = 2000; // ~83 days of H1 data
const D1_BAR_SECONDS = 86400;

// ---- Price generation ----
function generateCandles(numBars, barSeconds, startTs, basePrice) {
  const candles = [];
  let price = basePrice;

  for (let i = 0; i < numBars; i++) {
    const time = startTs + i * barSeconds;
    const volatility = 0.0003 + Math.random() * 0.0005;
    const trend = Math.sin(i / 200) * 0.00005;

    const open = price;
    const change1 = (Math.random() - 0.48) * volatility + trend;
    const change2 = (Math.random() - 0.48) * volatility + trend;
    const close = round(open + change1 + change2, DIGITS);

    const highExtra = Math.random() * volatility * 0.5;
    const lowExtra = Math.random() * volatility * 0.5;

    const high = round(Math.max(open, close) + highExtra, DIGITS);
    const low = round(Math.min(open, close) - lowExtra, DIGITS);
    const volume = Math.floor(500 + Math.random() * 3000);

    candles.push([time, open, high, low, close, volume]);
    price = close;
  }
  return candles;
}

// ---- Indicator calculations ----
function calcSMA(candles, period) {
  const result = [];
  for (let i = 0; i < candles.length; i++) {
    if (i < period - 1) {
      result.push([candles[i][0], null]);
      continue;
    }
    let sum = 0;
    for (let j = i - period + 1; j <= i; j++) sum += candles[j][4]; // close
    result.push([candles[i][0], round(sum / period, DIGITS + 3)]);
  }
  return result;
}

function calcBB(candles, period, dev) {
  const result = [];
  for (let i = 0; i < candles.length; i++) {
    if (i < period - 1) {
      result.push([candles[i][0], null, null, null]);
      continue;
    }
    let sum = 0;
    for (let j = i - period + 1; j <= i; j++) sum += candles[j][4];
    const mean = sum / period;

    let sumSqDev = 0;
    for (let j = i - period + 1; j <= i; j++) sumSqDev += (candles[j][4] - mean) ** 2;
    const stdDev = Math.sqrt(sumSqDev / period);

    result.push([
      candles[i][0],
      round(mean, DIGITS + 3),
      round(mean + dev * stdDev, DIGITS + 3),
      round(mean - dev * stdDev, DIGITS + 3),
    ]);
  }
  return result;
}

function calcRSI(candles, period) {
  const result = [];
  const gains = [];
  const losses = [];

  for (let i = 0; i < candles.length; i++) {
    if (i === 0) {
      result.push([candles[i][0], null]);
      continue;
    }

    const change = candles[i][4] - candles[i - 1][4];
    gains.push(change > 0 ? change : 0);
    losses.push(change < 0 ? -change : 0);

    if (i < period) {
      result.push([candles[i][0], null]);
      continue;
    }

    let avgGain, avgLoss;
    if (i === period) {
      avgGain = gains.slice(0, period).reduce((a, b) => a + b, 0) / period;
      avgLoss = losses.slice(0, period).reduce((a, b) => a + b, 0) / period;
    } else {
      const prevRsi = result[result.length - 1];
      // Simplified - just recalculate
      const recentGains = gains.slice(-period);
      const recentLosses = losses.slice(-period);
      avgGain = recentGains.reduce((a, b) => a + b, 0) / period;
      avgLoss = recentLosses.reduce((a, b) => a + b, 0) / period;
    }

    const rs = avgLoss === 0 ? 100 : avgGain / avgLoss;
    const rsi = round(100 - 100 / (1 + rs), 3);
    result.push([candles[i][0], rsi]);
  }
  return result;
}

function calcEMA(values, period) {
  const result = [];
  const k = 2 / (period + 1);
  let ema = null;

  for (let i = 0; i < values.length; i++) {
    if (values[i] === null) {
      result.push(null);
      continue;
    }
    if (ema === null) {
      ema = values[i];
    } else {
      ema = values[i] * k + ema * (1 - k);
    }
    result.push(ema);
  }
  return result;
}

function calcMACD(candles, fast, slow, signal) {
  const closes = candles.map(c => c[4]);
  const emaFast = calcEMA(closes, fast);
  const emaSlow = calcEMA(closes, slow);

  const macdLine = [];
  for (let i = 0; i < candles.length; i++) {
    if (emaFast[i] === null || emaSlow[i] === null) {
      macdLine.push(null);
    } else {
      macdLine.push(emaFast[i] - emaSlow[i]);
    }
  }

  const signalLine = calcEMA(macdLine, signal);

  const result = [];
  for (let i = 0; i < candles.length; i++) {
    if (macdLine[i] === null || signalLine[i] === null) {
      result.push([candles[i][0], null, null, null]);
    } else {
      result.push([
        candles[i][0],
        round(macdLine[i], DIGITS + 3),
        round(signalLine[i], DIGITS + 3),
        round(macdLine[i] - signalLine[i], DIGITS + 3),
      ]);
    }
  }
  return result;
}

// ---- Trade generation ----
function generateTrades(candles, rsiData, bbData) {
  const orders = [];
  const equity = [];
  let balance = 10000;
  let positionOpen = false;
  let orderTicket = 1000;
  let dealTicket = 5000;

  for (let i = 50; i < candles.length; i++) {
    const [time, open, high, low, close, vol] = candles[i];
    const rsi = rsiData[i]?.[1];
    const bbMiddle = bbData[i]?.[1];
    const bbUpper = bbData[i]?.[2];
    const bbLower = bbData[i]?.[3];

    // Record equity
    equity.push([time, round(balance, 2), round(balance + (Math.random() - 0.5) * 20, 2)]);

    if (rsi === null || bbMiddle === null) continue;

    if (!positionOpen && Math.random() > 0.96) {
      // Open a trade
      const isBuy = rsi < 45 || (close < bbLower * 1.005 && Math.random() > 0.3);
      const isSell = rsi > 55 || (close > bbUpper * 0.995 && Math.random() > 0.3);

      if (!isBuy && !isSell) continue;

      const type = isBuy ? 'BUY' : 'SELL';
      const entryPrice = isBuy ? close + SPREAD : close;
      const sl = isBuy ? entryPrice - 0.0050 : entryPrice + 0.0050;
      const tp = isBuy ? entryPrice + 0.0100 : entryPrice - 0.0100;
      const volume = 0.10;

      // Find exit (random 5-30 bars later)
      const exitBars = 5 + Math.floor(Math.random() * 25);
      const exitIdx = Math.min(i + exitBars, candles.length - 1);
      const exitCandle = candles[exitIdx];
      const exitPrice = isBuy ? exitCandle[4] : exitCandle[4] + SPREAD;

      // Bias slightly towards profitable trades for realistic demo
      const biasedExitPrice = Math.random() > 0.4
        ? (isBuy ? exitPrice + 0.0008 : exitPrice - 0.0008)
        : exitPrice;
      const pips = isBuy ? (biasedExitPrice - entryPrice) / POINT : (entryPrice - biasedExitPrice) / POINT;
      const profit = round(pips * POINT * 100000 * volume, 2);

      const entryDealTicket = dealTicket++;
      const exitDealTicket = dealTicket++;

      // Check for partial close possibility
      const hasPartial = Math.random() > 0.7 && exitIdx - i > 10;
      const exits = [];
      const deals = [];

      // Entry deal
      deals.push([
        entryDealTicket, type, 'IN', time, round(entryPrice, DIGITS), volume, round(-0.35, 2), 0,
      ]);

      if (hasPartial) {
        // Partial exit
        const partialIdx = i + Math.floor((exitIdx - i) / 2);
        const partialCandle = candles[partialIdx];
        const partialPrice = isBuy ? partialCandle[4] : partialCandle[4] + SPREAD;
        const partialPips = isBuy ? (partialPrice - entryPrice) / POINT : (entryPrice - partialPrice) / POINT;
        const partialProfit = round(partialPips * POINT * 100000 * volume * 0.5, 2);

        exits.push({
          time: partialCandle[0],
          price: round(partialPrice, DIGITS),
          volume: round(volume * 0.5, 2),
          reason: partialProfit >= 0 ? 'PARTIAL_TP' : 'PARTIAL_SL',
          profit: partialProfit,
          commission: -0.18,
          swap: 0,
        });

        deals.push([
          dealTicket++, isBuy ? 'SELL' : 'BUY', 'OUT',
          partialCandle[0], round(partialPrice, DIGITS),
          round(volume * 0.5, 2), -0.18, partialProfit,
        ]);

        // Final exit
        const remainingPips = isBuy ? (exitPrice - entryPrice) / POINT : (entryPrice - exitPrice) / POINT;
        const finalProfit = round(remainingPips * POINT * 100000 * volume * 0.5, 2);

        exits.push({
          time: exitCandle[0],
          price: round(exitPrice, DIGITS),
          volume: round(volume * 0.5, 2),
          reason: Math.abs(exitPrice - tp) < 0.0003 ? 'TP' : Math.abs(exitPrice - sl) < 0.0003 ? 'SL' : 'MANUAL',
          profit: finalProfit,
          commission: -0.17,
          swap: -0.05,
        });

        deals.push([
          exitDealTicket, isBuy ? 'SELL' : 'BUY', 'OUT',
          exitCandle[0], round(exitPrice, DIGITS),
          round(volume * 0.5, 2), -0.17, finalProfit,
        ]);

        const totalProfit = partialProfit + finalProfit;
        const totalComm = -0.35 - 0.18 - 0.17;
        const totalSwap = -0.05;

        orders.push({
          ticket: orderTicket++,
          type,
          volume,
          openTime: time,
          openPrice: round(entryPrice, DIGITS),
          sl: round(sl, DIGITS),
          tp: round(tp, DIGITS),
          comment: `RSI_BB ${type}`,
          exits,
          totalProfit: round(totalProfit, 2),
          totalCommission: round(totalComm, 2),
          totalSwap: totalSwap,
          netProfit: round(totalProfit + totalComm + totalSwap, 2),
          closeTime: exitCandle[0],
          closePrice: round(exitPrice, DIGITS),
          deals,
          indEntry: {
            'RSI_14': [round(rsi, 3)],
            'SMA_50': [rsiData[i]?.[1] ? round(candles[i][4] * 0.999, DIGITS + 3) : null],
            'BB_20_2.0': [bbMiddle, bbUpper, bbLower].map(v => v ? round(v, DIGITS + 3) : null),
            'MACD_12_26_9': [round(Math.random() * 0.001 - 0.0005, 8), round(Math.random() * 0.001 - 0.0005, 8), round(Math.random() * 0.0005 - 0.00025, 8)],
          },
          indExit: {
            'RSI_14': [round(30 + Math.random() * 40, 3)],
            'SMA_50': [round(exitCandle[4] * 1.001, DIGITS + 3)],
            'BB_20_2.0': bbData[exitIdx] ? [bbData[exitIdx][1], bbData[exitIdx][2], bbData[exitIdx][3]].map(v => v ? round(v, DIGITS + 3) : null) : [null, null, null],
            'MACD_12_26_9': [round(Math.random() * 0.001 - 0.0005, 8), round(Math.random() * 0.001 - 0.0005, 8), round(Math.random() * 0.0005 - 0.00025, 8)],
          },
        });

        balance += totalProfit + totalComm + totalSwap;
      } else {
        // Single exit
        exits.push({
          time: exitCandle[0],
          price: round(exitPrice, DIGITS),
          volume,
          reason: Math.abs(exitPrice - tp) < 0.0005 ? 'TP' : Math.abs(exitPrice - sl) < 0.0005 ? 'SL' : 'MANUAL',
          profit,
          commission: -0.35,
          swap: -0.02,
        });

        deals.push([
          exitDealTicket, isBuy ? 'SELL' : 'BUY', 'OUT',
          exitCandle[0], round(exitPrice, DIGITS),
          volume, -0.35, profit,
        ]);

        const totalComm = -0.70;
        const totalSwap = -0.02;

        orders.push({
          ticket: orderTicket++,
          type,
          volume,
          openTime: time,
          openPrice: round(entryPrice, DIGITS),
          sl: round(sl, DIGITS),
          tp: round(tp, DIGITS),
          comment: `RSI_BB ${type}`,
          exits,
          totalProfit: profit,
          totalCommission: totalComm,
          totalSwap: totalSwap,
          netProfit: round(profit + totalComm + totalSwap, 2),
          closeTime: exitCandle[0],
          closePrice: round(exitPrice, DIGITS),
          deals,
          indEntry: {
            'RSI_14': [round(rsi, 3)],
            'SMA_50': [round(candles[i][4] * 0.999, DIGITS + 3)],
            'BB_20_2.0': [bbMiddle, bbUpper, bbLower].map(v => v ? round(v, DIGITS + 3) : null),
            'MACD_12_26_9': [round(Math.random() * 0.001 - 0.0005, 8), round(Math.random() * 0.001 - 0.0005, 8), round(Math.random() * 0.0005 - 0.00025, 8)],
          },
          indExit: {
            'RSI_14': [round(30 + Math.random() * 40, 3)],
            'SMA_50': [round(exitCandle[4] * 1.001, DIGITS + 3)],
            'BB_20_2.0': bbData[exitIdx] ? [bbData[exitIdx][1], bbData[exitIdx][2], bbData[exitIdx][3]].map(v => v ? round(v, DIGITS + 3) : null) : [null, null, null],
            'MACD_12_26_9': [round(Math.random() * 0.001 - 0.0005, 8), round(Math.random() * 0.001 - 0.0005, 8), round(Math.random() * 0.0005 - 0.00025, 8)],
          },
        });

        balance += profit + totalComm + totalSwap;
      }

      positionOpen = false; // simplified - allow rapid trades
    }
  }

  return { orders, equity };
}

// ---- Stats calculation ----
function calcStats(orders, initialBalance) {
  const wins = orders.filter(o => o.netProfit >= 0);
  const losses = orders.filter(o => o.netProfit < 0);

  const grossProfit = wins.reduce((s, o) => s + o.netProfit, 0);
  const grossLoss = losses.reduce((s, o) => s + o.netProfit, 0);
  const netProfit = grossProfit + grossLoss;

  // Max drawdown from equity
  let peak = initialBalance;
  let maxDD = 0;
  let bal = initialBalance;
  for (const o of orders) {
    bal += o.netProfit;
    if (bal > peak) peak = bal;
    const dd = peak - bal;
    if (dd > maxDD) maxDD = dd;
  }

  const avgWin = wins.length > 0 ? grossProfit / wins.length : 0;
  const avgLoss = losses.length > 0 ? Math.abs(grossLoss / losses.length) : 0;
  const winRate = orders.length > 0 ? wins.length / orders.length : 0;

  // Consecutive
  let maxConsW = 0, maxConsL = 0, curW = 0, curL = 0;
  for (const o of orders) {
    if (o.netProfit >= 0) { curW++; curL = 0; maxConsW = Math.max(maxConsW, curW); }
    else { curL++; curW = 0; maxConsL = Math.max(maxConsL, curL); }
  }

  // Monthly
  const monthlyMap = {};
  for (const o of orders) {
    const d = new Date(o.closeTime * 1000);
    const key = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
    if (!monthlyMap[key]) monthlyMap[key] = { profit: 0, trades: 0, wins: 0 };
    monthlyMap[key].profit += o.netProfit;
    monthlyMap[key].trades++;
    if (o.netProfit >= 0) monthlyMap[key].wins++;
  }

  let runBal = initialBalance;
  const monthly = Object.keys(monthlyMap).sort().map(m => {
    const d = monthlyMap[m];
    const pct = (d.profit / runBal) * 100;
    runBal += d.profit;
    return {
      month: m,
      profit: round(d.profit, 2),
      profitPct: round(pct, 2),
      trades: d.trades,
      winRate: round(d.wins / d.trades, 4),
    };
  });

  // Sharpe
  const returns = orders.map(o => o.netProfit);
  const mean = returns.reduce((a, b) => a + b, 0) / returns.length;
  const variance = returns.reduce((s, r) => s + (r - mean) ** 2, 0) / (returns.length - 1);
  const sharpe = variance > 0 ? mean / Math.sqrt(variance) : 0;

  // Avg duration
  const durations = orders.filter(o => o.closeTime > o.openTime).map(o => o.closeTime - o.openTime);
  const avgDuration = durations.length > 0 ? Math.floor(durations.reduce((a, b) => a + b, 0) / durations.length) : 0;

  return {
    netProfit: round(netProfit, 2),
    netProfitPct: round((netProfit / initialBalance) * 100, 2),
    grossProfit: round(grossProfit, 2),
    grossLoss: round(grossLoss, 2),
    totalTrades: orders.length,
    winningTrades: wins.length,
    losingTrades: losses.length,
    winRate: round(winRate, 4),
    profitFactor: round(grossLoss !== 0 ? Math.abs(grossProfit / grossLoss) : 999.99, 2),
    expectancy: round(winRate * avgWin - (1 - winRate) * avgLoss, 2),
    maxDrawdown: round(maxDD, 2),
    maxDrawdownPct: round(peak > 0 ? (maxDD / peak) * 100 : 0, 2),
    maxDrawdownDate: START_TS + Math.floor(NUM_BARS * 0.6) * BAR_SECONDS,
    sharpeRatio: round(sharpe, 2),
    recoveryFactor: round(maxDD > 0 ? netProfit / maxDD : 0, 2),
    avgWin: round(avgWin, 2),
    avgLoss: round(avgLoss, 2),
    largestWin: round(wins.length > 0 ? Math.max(...wins.map(o => o.netProfit)) : 0, 2),
    largestLoss: round(losses.length > 0 ? Math.min(...losses.map(o => o.netProfit)) : 0, 2),
    avgTradeDuration: avgDuration,
    maxConsecutiveWins: maxConsW,
    maxConsecutiveLosses: maxConsL,
    totalCommission: round(orders.reduce((s, o) => s + o.totalCommission, 0), 2),
    totalSwap: round(orders.reduce((s, o) => s + o.totalSwap, 0), 2),
    pendingOrdersFilled: Math.floor(orders.length * 0.8),
    pendingOrdersCancelled: Math.floor(orders.length * 0.1),
    pendingOrdersExpired: Math.floor(orders.length * 0.05),
    monthly,
  };
}

function round(val, dec) {
  if (val === null || val === undefined) return null;
  const f = 10 ** dec;
  return Math.round(val * f) / f;
}

// ---- Main ----
console.log('Generating sample data...');

// H1 candles
const h1Candles = generateCandles(NUM_BARS, BAR_SECONDS, START_TS, BASE_PRICE);
// D1 candles (fewer bars)
const d1NumBars = Math.ceil(NUM_BARS / 24);
const d1Candles = generateCandles(d1NumBars, D1_BAR_SECONDS, START_TS, BASE_PRICE);

// Indicators on H1
const sma50 = calcSMA(h1Candles, 50);
const bb20 = calcBB(h1Candles, 20, 2.0);
const rsi14 = calcRSI(h1Candles, 14);
const macd = calcMACD(h1Candles, 12, 26, 9);

// D1 SMA
const sma50D1 = calcSMA(d1Candles, 50);

// Generate trades
const { orders, equity } = generateTrades(h1Candles, rsi14, bb20);

console.log(`Generated ${orders.length} trades, ${h1Candles.length} H1 candles, ${d1Candles.length} D1 candles`);

// Calculate stats
const stats = calcStats(orders, 10000);

// Pending orders
const pendingOrders = orders.slice(0, Math.floor(orders.length * 0.8)).map((o, i) => ({
  ticket: 9000 + i,
  type: o.type === 'BUY' ? 'BUY_LIMIT' : 'SELL_LIMIT',
  volume: o.volume,
  price: o.openPrice,
  sl: o.sl,
  tp: o.tp,
  placedTime: o.openTime - 3600,
  expiration: o.openTime + 7200,
  status: 'FILLED',
  filledTime: o.openTime,
  filledPrice: o.openPrice,
  resultOrderTicket: o.ticket,
}));

// Build final JSON
const data = {
  meta: {
    version: '1.0',
    strategy: 'RSI_BB_MACD_Strategy',
    symbol: { name: SYMBOL, digits: DIGITS, point: POINT, contractSize: 100000 },
    timeframes: ['H1', 'D1'],
    primaryTimeframe: 'H1',
    start: START_TS,
    end: START_TS + NUM_BARS * BAR_SECONDS,
    initialBalance: 10000,
    finalBalance: round(10000 + stats.netProfit, 2),
    currency: 'USD',
    accountMode: 'HEDGING',
    magicNumber: 123456,
    timezone: 'UTC+2',
    exportedAt: Math.floor(Date.now() / 1000),
  },
  stats,
  data: {
    H1: {
      candles: h1Candles,
      indicators: {
        'SMA_50': { buffers: ['value'], data: sma50 },
        'BB_20_2.0': { buffers: ['middle', 'upper', 'lower'], data: bb20 },
        'RSI_14': { buffers: ['value'], data: rsi14 },
        'MACD_12_26_9': { buffers: ['main', 'signal', 'histogram'], data: macd },
      },
    },
    D1: {
      candles: d1Candles,
      indicators: {
        'SMA_50_D1': { buffers: ['value'], data: sma50D1 },
      },
    },
  },
  pendingOrders,
  orders,
  equity,
};

const json = JSON.stringify(data);
writeFileSync('public/sample-data.json', json);
console.log(`Written to public/sample-data.json (${(json.length / 1024 / 1024).toFixed(2)} MB)`);
console.log(`Stats: Net P/L: $${stats.netProfit}, Win Rate: ${(stats.winRate * 100).toFixed(1)}%, Trades: ${stats.totalTrades}`);
