// ============================================================
// TypeScript interfaces matching MQL5 JSON export format
// ============================================================

export interface StrategyData {
  meta: MetaData;
  stats: Stats;
  data: Record<string, TimeframeData>;
  pendingOrders: PendingOrder[];
  orders: Order[];
  equity: EquityPoint[];
}

export interface MetaData {
  version: string;
  strategy: string;
  symbol: SymbolInfo;
  timeframes: string[];
  primaryTimeframe: string;
  start: number;
  end: number;
  initialBalance: number;
  finalBalance: number;
  currency: string;
  accountMode: 'HEDGING' | 'NETTING';
  magicNumber: number;
  timezone: string;
  exportedAt: number;
}

export interface SymbolInfo {
  name: string;
  digits: number;
  point: number;
  contractSize: number;
}

export interface Stats {
  netProfit: number;
  netProfitPct: number;
  grossProfit: number;
  grossLoss: number;
  totalTrades: number;
  winningTrades: number;
  losingTrades: number;
  winRate: number;
  profitFactor: number;
  expectancy: number;
  maxDrawdown: number;
  maxDrawdownPct: number;
  maxDrawdownDate: number;
  sharpeRatio: number;
  recoveryFactor: number;
  avgWin: number;
  avgLoss: number;
  largestWin: number;
  largestLoss: number;
  avgTradeDuration: number;
  maxConsecutiveWins: number;
  maxConsecutiveLosses: number;
  totalCommission: number;
  totalSwap: number;
  pendingOrdersFilled: number;
  pendingOrdersCancelled: number;
  pendingOrdersExpired: number;
  monthly: MonthlyStats[];
}

export interface MonthlyStats {
  month: string;
  profit: number;
  profitPct: number;
  trades: number;
  winRate: number;
}

export interface TimeframeData {
  candles: CandleArray[];
  indicators: Record<string, IndicatorData>;
}

// [time, open, high, low, close, volume]
export type CandleArray = [number, number, number, number, number, number];

export interface IndicatorData {
  buffers: string[];
  data: number[][]; // [time, ...values]
}

export interface PendingOrder {
  ticket: number;
  type: string;
  volume: number;
  price: number;
  sl: number;
  tp: number;
  placedTime: number;
  expiration: number;
  status: 'ACTIVE' | 'FILLED' | 'CANCELLED' | 'EXPIRED';
  filledTime?: number;
  filledPrice?: number;
  resultOrderTicket?: number;
}

export interface OrderExit {
  time: number;
  price: number;
  volume: number;
  reason: string;
  profit: number;
  commission: number;
  swap: number;
}

export interface Order {
  ticket: number;
  type: 'BUY' | 'SELL';
  volume: number;
  openTime: number;
  openPrice: number;
  sl: number;
  tp: number;
  comment: string;
  exits: OrderExit[];
  totalProfit: number;
  totalCommission: number;
  totalSwap: number;
  netProfit: number;
  closeTime: number;
  closePrice: number;
  deals: DealArray[];
  indEntry: Record<string, number[]>;
  indExit: Record<string, number[]>;
  pendingOrderTicket?: number;
}

// [ticket, type, entry, time, price, volume, commission, profit]
export type DealArray = [number, string, string, number, number, number, number, number];

// [time, balance, equity]
export type EquityPoint = [number, number, number];

// ============================================================
// Chart-ready data types
// ============================================================

export interface CandlestickData {
  time: number;
  open: number;
  high: number;
  low: number;
  close: number;
}

export interface VolumeData {
  time: number;
  value: number;
  color: string;
}

export interface LineData {
  time: number;
  value: number;
}

export interface TradeMarker {
  orderTicket: number;
  type: 'BUY' | 'SELL';
  entryTime: number;
  entryPrice: number;
  exitTime: number;
  exitPrice: number;
  profit: number;
  isWin: boolean;
}

// Indicator classification
export type IndicatorLocation = 'overlay' | 'panel';

export interface IndicatorConfig {
  name: string;
  location: IndicatorLocation;
  visible: boolean;
  buffers: string[];
  colors: string[];
}
