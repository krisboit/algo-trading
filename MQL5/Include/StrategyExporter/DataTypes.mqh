//+------------------------------------------------------------------+
//|                                                    DataTypes.mqh |
//|                                          Strategy Exporter v1.0  |
//|                           Data structures for strategy export    |
//+------------------------------------------------------------------+
#property copyright "Strategy Exporter"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Exit reason enum                                                 |
//+------------------------------------------------------------------+
enum ENUM_EXIT_REASON
{
   EXIT_REASON_TP = 0,           // Take profit
   EXIT_REASON_SL,               // Stop loss
   EXIT_REASON_PARTIAL_TP,       // Partial close at profit
   EXIT_REASON_PARTIAL_SL,       // Partial close at loss
   EXIT_REASON_MANUAL,           // Manual close
   EXIT_REASON_EXPIRED,          // Expired
   EXIT_REASON_UNKNOWN           // Unknown
};

//+------------------------------------------------------------------+
//| Pending order status enum                                        |
//+------------------------------------------------------------------+
enum ENUM_PENDING_STATUS
{
   PENDING_STATUS_ACTIVE = 0,    // Still active
   PENDING_STATUS_FILLED,        // Triggered and filled
   PENDING_STATUS_CANCELLED,     // Manually cancelled
   PENDING_STATUS_EXPIRED        // Hit expiration time
};

//+------------------------------------------------------------------+
//| Candle data structure                                            |
//+------------------------------------------------------------------+
struct SCandle
{
   datetime time;
   double   open;
   double   high;
   double   low;
   double   close;
   long     volume;
};

//+------------------------------------------------------------------+
//| Single indicator value at a point in time                        |
//+------------------------------------------------------------------+
struct SIndicatorValue
{
   datetime time;
   double   values[];

   void Init(int bufferCount)
   {
      ArrayResize(values, bufferCount);
      ArrayInitialize(values, EMPTY_VALUE);
   }
};

//+------------------------------------------------------------------+
//| Indicator registration info                                      |
//+------------------------------------------------------------------+
struct SIndicatorInfo
{
   int               handle;
   string            name;
   string            bufferNames[];
   int               bufferCount;
   ENUM_TIMEFRAMES   timeframe;
   SIndicatorValue   data[];
   int               dataCount;

   void Init(int _handle, string _name, int _bufferCount, ENUM_TIMEFRAMES _tf)
   {
      handle = _handle;
      name = _name;
      bufferCount = _bufferCount;
      timeframe = _tf;
      dataCount = 0;
      ArrayResize(bufferNames, _bufferCount);
      ArrayResize(data, 0, 10000);
   }

   void SetBufferNames(string &names[])
   {
      int count = MathMin(ArraySize(names), bufferCount);
      for(int i = 0; i < count; i++)
         bufferNames[i] = names[i];
   }

   void SetDefaultBufferNames()
   {
      if(bufferCount == 1)
      {
         bufferNames[0] = "value";
      }
      else if(bufferCount == 2)
      {
         bufferNames[0] = "main";
         bufferNames[1] = "signal";
      }
      else if(bufferCount == 3)
      {
         bufferNames[0] = "main";
         bufferNames[1] = "signal";
         bufferNames[2] = "histogram";
      }
      else
      {
         for(int i = 0; i < bufferCount; i++)
            bufferNames[i] = "buffer_" + IntegerToString(i);
      }
   }

   void AddValue(datetime time, double &vals[])
   {
      int idx = dataCount;
      dataCount++;
      ArrayResize(data, dataCount, 10000);
      data[idx].Init(bufferCount);
      data[idx].time = time;
      int count = MathMin(ArraySize(vals), bufferCount);
      for(int i = 0; i < count; i++)
         data[idx].values[i] = vals[i];
   }
};

//+------------------------------------------------------------------+
//| Timeframe data collector                                         |
//+------------------------------------------------------------------+
struct STimeframeData
{
   ENUM_TIMEFRAMES   timeframe;
   string            timeframeName;
   SCandle           candles[];
   int               candleCount;
   datetime          lastBarTime;

   void Init(ENUM_TIMEFRAMES _tf)
   {
      // Resolve PERIOD_CURRENT (value 0) to actual timeframe
      timeframe = (_tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : _tf;
      timeframeName = TimeframeToString(timeframe);
      candleCount = 0;
      lastBarTime = 0;
      ArrayResize(candles, 0, 50000);
   }

   void AddCandle(datetime time, double open, double high, double low, double close, long volume)
   {
      int idx = candleCount;
      candleCount++;
      ArrayResize(candles, candleCount, 50000);
      candles[idx].time = time;
      candles[idx].open = open;
      candles[idx].high = high;
      candles[idx].low = low;
      candles[idx].close = close;
      candles[idx].volume = volume;
   }

   static string TimeframeToString(ENUM_TIMEFRAMES tf)
   {
      switch(tf)
      {
         case PERIOD_M1:  return "M1";
         case PERIOD_M2:  return "M2";
         case PERIOD_M3:  return "M3";
         case PERIOD_M4:  return "M4";
         case PERIOD_M5:  return "M5";
         case PERIOD_M6:  return "M6";
         case PERIOD_M10: return "M10";
         case PERIOD_M12: return "M12";
         case PERIOD_M15: return "M15";
         case PERIOD_M20: return "M20";
         case PERIOD_M30: return "M30";
         case PERIOD_H1:  return "H1";
         case PERIOD_H2:  return "H2";
         case PERIOD_H3:  return "H3";
         case PERIOD_H4:  return "H4";
         case PERIOD_H6:  return "H6";
         case PERIOD_H8:  return "H8";
         case PERIOD_H12: return "H12";
         case PERIOD_D1:  return "D1";
         case PERIOD_W1:  return "W1";
         case PERIOD_MN1: return "MN1";
         default:         return "UNKNOWN";
      }
   }
};

//+------------------------------------------------------------------+
//| Deal data structure                                              |
//+------------------------------------------------------------------+
struct SDeal
{
   ulong    ticket;
   string   type;       // "BUY" or "SELL"
   string   entry;      // "IN", "OUT", "INOUT"
   datetime time;
   double   price;
   double   volume;
   double   commission;
   double   profit;
   double   swap;
};

//+------------------------------------------------------------------+
//| Exit data structure (for partial closes)                         |
//+------------------------------------------------------------------+
struct SExit
{
   datetime          time;
   double            price;
   double            volume;
   ENUM_EXIT_REASON  reason;
   double            profit;
   double            commission;
   double            swap;

   static string ReasonToString(ENUM_EXIT_REASON reason)
   {
      switch(reason)
      {
         case EXIT_REASON_TP:         return "TP";
         case EXIT_REASON_SL:         return "SL";
         case EXIT_REASON_PARTIAL_TP: return "PARTIAL_TP";
         case EXIT_REASON_PARTIAL_SL: return "PARTIAL_SL";
         case EXIT_REASON_MANUAL:     return "MANUAL";
         case EXIT_REASON_EXPIRED:    return "EXPIRED";
         default:                     return "UNKNOWN";
      }
   }
};

//+------------------------------------------------------------------+
//| Indicator snapshot at trade moment                               |
//+------------------------------------------------------------------+
struct SIndicatorSnapshot
{
   string   name;
   double   values[];
};

//+------------------------------------------------------------------+
//| Order data structure                                             |
//+------------------------------------------------------------------+
struct SOrder
{
   ulong                ticket;
   string               type;        // "BUY" or "SELL"
   double               volume;
   datetime             openTime;
   double               openPrice;
   double               sl;
   double               tp;
   string               comment;

   // Exits array
   SExit                exits[];
   int                  exitCount;

   // Aggregated P&L
   double               totalProfit;
   double               totalCommission;
   double               totalSwap;
   double               netProfit;

   // Raw deals
   SDeal                deals[];
   int                  dealCount;

   // Indicator snapshots
   SIndicatorSnapshot   indEntry[];
   SIndicatorSnapshot   indExit[];
   int                  indEntryCount;
   int                  indExitCount;

   // Link to pending order
   ulong                pendingOrderTicket;

   // Computed close values (from last exit)
   datetime             closeTime;
   double               closePrice;

   void Init()
   {
      exitCount = 0;
      dealCount = 0;
      indEntryCount = 0;
      indExitCount = 0;
      totalProfit = 0;
      totalCommission = 0;
      totalSwap = 0;
      netProfit = 0;
      pendingOrderTicket = 0;
      closeTime = 0;
      closePrice = 0;
      ArrayResize(exits, 0, 10);
      ArrayResize(deals, 0, 10);
      ArrayResize(indEntry, 0, 20);
      ArrayResize(indExit, 0, 20);
   }

   void AddDeal(SDeal &deal)
   {
      int idx = dealCount;
      dealCount++;
      ArrayResize(deals, dealCount, 10);
      deals[idx] = deal;
   }

   void AddExit(SExit &exit)
   {
      int idx = exitCount;
      exitCount++;
      ArrayResize(exits, exitCount, 10);
      exits[idx] = exit;

      // Update aggregated values
      totalProfit += exit.profit;
      totalCommission += exit.commission;
      totalSwap += exit.swap;
      netProfit = totalProfit + totalCommission + totalSwap;

      // Update close time/price to latest exit
      if(exit.time > closeTime)
      {
         closeTime = exit.time;
         closePrice = exit.price;
      }
   }

   void AddIndicatorSnapshot(bool isEntry, string name, double &values[])
   {
      if(isEntry)
      {
         int idx = indEntryCount;
         indEntryCount++;
         ArrayResize(indEntry, indEntryCount, 20);
         indEntry[idx].name = name;
         ArrayResize(indEntry[idx].values, ArraySize(values));
         ArrayCopy(indEntry[idx].values, values);
      }
      else
      {
         int idx = indExitCount;
         indExitCount++;
         ArrayResize(indExit, indExitCount, 20);
         indExit[idx].name = name;
         ArrayResize(indExit[idx].values, ArraySize(values));
         ArrayCopy(indExit[idx].values, values);
      }
   }
};

//+------------------------------------------------------------------+
//| Pending order data structure                                     |
//+------------------------------------------------------------------+
struct SPendingOrder
{
   ulong                ticket;
   string               type;        // "BUY_LIMIT", "SELL_STOP", etc.
   double               volume;
   double               price;
   double               sl;
   double               tp;
   datetime             placedTime;
   datetime             expiration;
   ENUM_PENDING_STATUS  status;
   datetime             filledTime;
   double               filledPrice;
   ulong                resultOrderTicket;

   void Init()
   {
      filledTime = 0;
      filledPrice = 0;
      resultOrderTicket = 0;
      status = PENDING_STATUS_ACTIVE;
   }

   static string StatusToString(ENUM_PENDING_STATUS status)
   {
      switch(status)
      {
         case PENDING_STATUS_ACTIVE:    return "ACTIVE";
         case PENDING_STATUS_FILLED:    return "FILLED";
         case PENDING_STATUS_CANCELLED: return "CANCELLED";
         case PENDING_STATUS_EXPIRED:   return "EXPIRED";
         default:                       return "UNKNOWN";
      }
   }

   static string OrderTypeToString(ENUM_ORDER_TYPE type)
   {
      switch(type)
      {
         case ORDER_TYPE_BUY_LIMIT:       return "BUY_LIMIT";
         case ORDER_TYPE_SELL_LIMIT:      return "SELL_LIMIT";
         case ORDER_TYPE_BUY_STOP:        return "BUY_STOP";
         case ORDER_TYPE_SELL_STOP:       return "SELL_STOP";
         case ORDER_TYPE_BUY_STOP_LIMIT:  return "BUY_STOP_LIMIT";
         case ORDER_TYPE_SELL_STOP_LIMIT: return "SELL_STOP_LIMIT";
         default:                         return "UNKNOWN";
      }
   }
};

//+------------------------------------------------------------------+
//| Equity point structure                                           |
//+------------------------------------------------------------------+
struct SEquityPoint
{
   datetime time;
   double   balance;
   double   equity;
};

//+------------------------------------------------------------------+
//| Monthly stats structure                                          |
//+------------------------------------------------------------------+
struct SMonthlyStats
{
   string   month;        // "2024-01"
   double   profit;
   double   profitPct;
   int      trades;
   int      winningTrades;
   int      losingTrades;
   double   winRate;
};

//+------------------------------------------------------------------+
//| Aggregated stats structure                                       |
//+------------------------------------------------------------------+
struct SStats
{
   double   netProfit;
   double   netProfitPct;
   double   grossProfit;
   double   grossLoss;
   int      totalTrades;
   int      winningTrades;
   int      losingTrades;
   double   winRate;
   double   profitFactor;
   double   expectancy;
   double   maxDrawdown;
   double   maxDrawdownPct;
   datetime maxDrawdownDate;
   double   sharpeRatio;
   double   recoveryFactor;
   double   avgWin;
   double   avgLoss;
   double   largestWin;
   double   largestLoss;
   int      avgTradeDuration;
   int      maxConsecutiveWins;
   int      maxConsecutiveLosses;
   double   totalCommission;
   double   totalSwap;
   int      pendingOrdersFilled;
   int      pendingOrdersCancelled;
   int      pendingOrdersExpired;

   // Monthly breakdown
   SMonthlyStats monthly[];
   int           monthlyCount;

   void Init()
   {
      netProfit = 0;
      netProfitPct = 0;
      grossProfit = 0;
      grossLoss = 0;
      totalTrades = 0;
      winningTrades = 0;
      losingTrades = 0;
      winRate = 0;
      profitFactor = 0;
      expectancy = 0;
      maxDrawdown = 0;
      maxDrawdownPct = 0;
      maxDrawdownDate = 0;
      sharpeRatio = 0;
      recoveryFactor = 0;
      avgWin = 0;
      avgLoss = 0;
      largestWin = 0;
      largestLoss = -99999999;
      avgTradeDuration = 0;
      maxConsecutiveWins = 0;
      maxConsecutiveLosses = 0;
      totalCommission = 0;
      totalSwap = 0;
      pendingOrdersFilled = 0;
      pendingOrdersCancelled = 0;
      pendingOrdersExpired = 0;
      monthlyCount = 0;
      ArrayResize(monthly, 0, 24);
   }
};

//+------------------------------------------------------------------+
