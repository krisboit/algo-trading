//+------------------------------------------------------------------+
//|                                                  JsonBuilder.mqh |
//|                                          Strategy Exporter v2.0  |
//|          Streaming JSON writer - writes directly to file handle  |
//+------------------------------------------------------------------+
#property copyright "Strategy Exporter"
#property version   "2.00"
#property strict

#include "DataTypes.mqh"
#include <JAson.mqh>

//+------------------------------------------------------------------+
//| JSON Builder class - streams JSON directly to file               |
//|                                                                  |
//| v2.0: Rewrote to avoid CJAVal.Serialize() on large trees.       |
//| CJAVal's Serialize() uses recursive js+=str which is O(n^2)     |
//| for large datasets (82K candles = hangs forever).                |
//|                                                                  |
//| Now:                                                             |
//|  - Small sections (meta, stats): CJAVal → Serialize() (tiny)    |
//|  - Large sections (candles, indicators, equity): row-by-row      |
//|    FileWriteString() with small pre-formatted strings            |
//|  - Orders: each order formatted individually                     |
//+------------------------------------------------------------------+
class CJsonBuilder
{
private:
   int m_digits;
   int m_fh;   // file handle for streaming writes

   //--- helpers
   void W(string s)             { FileWriteString(m_fh, s); }
   string D(double v, int d)    { return DoubleToString(NormalizeDouble(v, d), d); }
   string D2(double v)          { return D(v, 2); }
   string Dp(double v)          { return D(v, m_digits); }
   string Dp3(double v)         { return D(v, m_digits + 3); }
   string L(long v)             { return IntegerToString(v); }

   // Escape a string for JSON (handle quotes, backslashes, control chars)
   string JsonEsc(string s)
   {
      string r = "";
      int len = StringLen(s);
      for(int i = 0; i < len; i++)
      {
         ushort ch = StringGetCharacter(s, i);
         if(ch == '\\')      r += "\\\\";
         else if(ch == '"')  r += "\\\"";
         else if(ch == '\n') r += "\\n";
         else if(ch == '\r') r += "\\r";
         else if(ch == '\t') r += "\\t";
         else                r += ShortToString(ch);
      }
      return r;
   }

   string QS(string s) { return "\"" + JsonEsc(s) + "\""; }  // quoted string

public:
   CJsonBuilder() : m_digits(5), m_fh(INVALID_HANDLE) {}

   void SetDigits(int digits) { m_digits = digits; }

   //+------------------------------------------------------------------+
   //| Write complete JSON document to an open file handle               |
   //+------------------------------------------------------------------+
   void WriteTo(int fileHandle,
                string strategyName, string symbol, int digits, double point,
                double contractSize, string currency,
                ENUM_TIMEFRAMES primaryTF,
                STimeframeData &timeframes[], int tfCount,
                SIndicatorInfo &indicators[], int indCount,
                SOrder &orders[], int orderCount,
                SPendingOrder &pending[], int pendingCount,
                SEquityPoint &equity[], int equityCount,
                SStats &stats,
                double initialBalance, double finalBalance,
                ulong magicNumber,
                datetime startDate, datetime endDate)
   {
      m_digits = digits;
      m_fh = fileHandle;

      uint t0;

      W("{");

      // --- Meta (small, use CJAVal) ---
      t0 = GetTickCount();
      WriteMeta(strategyName, symbol, digits, point, contractSize,
                currency, primaryTF, timeframes, tfCount,
                initialBalance, finalBalance, magicNumber,
                startDate, endDate);
      Print("[JsonBuilder] Meta: ", (GetTickCount() - t0), " ms");

      W(",");

      // --- Stats (small, use CJAVal) ---
      t0 = GetTickCount();
      WriteStats(stats);
      Print("[JsonBuilder] Stats: ", (GetTickCount() - t0), " ms");

      W(",");

      // --- Data: candles + indicators (LARGE, stream row-by-row) ---
      t0 = GetTickCount();
      WriteData(timeframes, tfCount, indicators, indCount);
      Print("[JsonBuilder] Data (candles+indicators): ", (GetTickCount() - t0), " ms");

      W(",");

      // --- Pending orders (small-ish, stream individually) ---
      t0 = GetTickCount();
      WritePendingOrders(pending, pendingCount);
      Print("[JsonBuilder] PendingOrders: ", (GetTickCount() - t0), " ms");

      W(",");

      // --- Orders (moderate, stream individually) ---
      t0 = GetTickCount();
      WriteOrders(orders, orderCount);
      Print("[JsonBuilder] Orders: ", (GetTickCount() - t0), " ms");

      W(",");

      // --- Equity (LARGE, stream row-by-row) ---
      t0 = GetTickCount();
      WriteEquity(equity, equityCount);
      Print("[JsonBuilder] Equity: ", (GetTickCount() - t0), " ms");

      W("}");
   }

private:
   //+------------------------------------------------------------------+
   //| Write metadata section (small, CJAVal is fine)                   |
   //+------------------------------------------------------------------+
   void WriteMeta(string strategyName, string symbol,
                  int digits, double point, double contractSize,
                  string currency, ENUM_TIMEFRAMES primaryTF,
                  STimeframeData &timeframes[], int tfCount,
                  double initialBalance, double finalBalance,
                  ulong magicNumber,
                  datetime startDate, datetime endDate)
   {
      CJAVal meta;
      meta.Clear(jtOBJ);
      meta["version"] = "1.0";
      meta["strategy"] = strategyName;

      CJAVal sym;
      sym.Clear(jtOBJ);
      sym["name"] = symbol;
      sym["digits"] = digits;
      sym["point"] = point;
      sym["contractSize"] = contractSize;
      meta["symbol"].Copy(sym);

      CJAVal tfs;
      tfs.Clear(jtARRAY);
      for(int i = 0; i < tfCount; i++)
         tfs[i] = timeframes[i].timeframeName;
      meta["timeframes"].Copy(tfs);

      meta["primaryTimeframe"] = STimeframeData::TimeframeToString(primaryTF);
      meta["start"] = (long)startDate;
      meta["end"] = (long)endDate;
      meta["initialBalance"] = NormalizeDouble(initialBalance, 2);
      meta["finalBalance"] = NormalizeDouble(finalBalance, 2);
      meta["currency"] = currency;

      ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
         meta["accountMode"] = "HEDGING";
      else
         meta["accountMode"] = "NETTING";

      meta["magicNumber"] = (long)magicNumber;

      long gmtOffset = (long)(TimeLocal() - TimeGMT());
      int hours = (int)(gmtOffset / 3600);
      meta["timezone"] = StringFormat("UTC%s%d", hours >= 0 ? "+" : "", hours);

      meta["exportedAt"] = (long)TimeCurrent();

      // Serialize just this small object and write
      string metaJson = meta.Serialize();
      W("\"meta\":" + metaJson);
   }

   //+------------------------------------------------------------------+
   //| Write stats section (small, CJAVal is fine)                      |
   //+------------------------------------------------------------------+
   void WriteStats(SStats &stats)
   {
      CJAVal s;
      s.Clear(jtOBJ);

      s["netProfit"] = NormalizeDouble(stats.netProfit, 2);
      s["netProfitPct"] = NormalizeDouble(stats.netProfitPct, 2);
      s["grossProfit"] = NormalizeDouble(stats.grossProfit, 2);
      s["grossLoss"] = NormalizeDouble(stats.grossLoss, 2);
      s["totalTrades"] = stats.totalTrades;
      s["winningTrades"] = stats.winningTrades;
      s["losingTrades"] = stats.losingTrades;
      s["winRate"] = NormalizeDouble(stats.winRate, 4);
      s["profitFactor"] = NormalizeDouble(stats.profitFactor, 2);
      s["expectancy"] = NormalizeDouble(stats.expectancy, 2);
      s["maxDrawdown"] = NormalizeDouble(stats.maxDrawdown, 2);
      s["maxDrawdownPct"] = NormalizeDouble(stats.maxDrawdownPct, 2);
      s["maxDrawdownDate"] = (long)stats.maxDrawdownDate;
      s["sharpeRatio"] = NormalizeDouble(stats.sharpeRatio, 2);
      s["recoveryFactor"] = NormalizeDouble(stats.recoveryFactor, 2);
      s["avgWin"] = NormalizeDouble(stats.avgWin, 2);
      s["avgLoss"] = NormalizeDouble(stats.avgLoss, 2);
      s["largestWin"] = NormalizeDouble(stats.largestWin, 2);
      s["largestLoss"] = NormalizeDouble(stats.largestLoss, 2);
      s["avgTradeDuration"] = stats.avgTradeDuration;
      s["maxConsecutiveWins"] = stats.maxConsecutiveWins;
      s["maxConsecutiveLosses"] = stats.maxConsecutiveLosses;
      s["totalCommission"] = NormalizeDouble(stats.totalCommission, 2);
      s["totalSwap"] = NormalizeDouble(stats.totalSwap, 2);
      s["pendingOrdersFilled"] = stats.pendingOrdersFilled;
      s["pendingOrdersCancelled"] = stats.pendingOrdersCancelled;
      s["pendingOrdersExpired"] = stats.pendingOrdersExpired;

      // Monthly breakdown
      CJAVal monthly;
      monthly.Clear(jtARRAY);
      for(int i = 0; i < stats.monthlyCount; i++)
      {
         CJAVal m;
         m.Clear(jtOBJ);
         m["month"] = stats.monthly[i].month;
         m["profit"] = NormalizeDouble(stats.monthly[i].profit, 2);
         m["profitPct"] = NormalizeDouble(stats.monthly[i].profitPct, 2);
         m["trades"] = stats.monthly[i].trades;
         m["winRate"] = NormalizeDouble(stats.monthly[i].winRate, 4);
         monthly[i].Copy(m);
      }
      s["monthly"].Copy(monthly);

      string statsJson = s.Serialize();
      W("\"stats\":" + statsJson);
   }

   //+------------------------------------------------------------------+
   //| Write data section: candles + indicators (STREAMING)             |
   //+------------------------------------------------------------------+
   void WriteData(STimeframeData &timeframes[], int tfCount,
                  SIndicatorInfo &indicators[], int indCount)
   {
      W("\"data\":{");

      for(int t = 0; t < tfCount; t++)
      {
         if(t > 0) W(",");

         W(QS(timeframes[t].timeframeName) + ":{");

         // --- Candles: stream row-by-row ---
         W("\"candles\":[");
         for(int i = 0; i < timeframes[t].candleCount; i++)
         {
            if(i > 0) W(",");
            W("[" + L((long)timeframes[t].candles[i].time) + ","
                  + Dp(timeframes[t].candles[i].open) + ","
                  + Dp(timeframes[t].candles[i].high) + ","
                  + Dp(timeframes[t].candles[i].low) + ","
                  + Dp(timeframes[t].candles[i].close) + ","
                  + L(timeframes[t].candles[i].volume) + "]");
         }
         W("]");

         // --- Indicators for this timeframe ---
         W(",\"indicators\":{");
         bool firstInd = true;
         for(int j = 0; j < indCount; j++)
         {
            if(indicators[j].timeframe != timeframes[t].timeframe)
               continue;

            if(!firstInd) W(",");
            firstInd = false;

            W(QS(indicators[j].name) + ":{");

            // Buffer names (small array)
            W("\"buffers\":[");
            for(int b = 0; b < indicators[j].bufferCount; b++)
            {
               if(b > 0) W(",");
               W(QS(indicators[j].bufferNames[b]));
            }
            W("]");

            // Data: stream row-by-row [time, val1, val2, ...]
            W(",\"data\":[");
            for(int d = 0; d < indicators[j].dataCount; d++)
            {
               if(d > 0) W(",");
               W("[" + L((long)indicators[j].data[d].time));
               for(int b = 0; b < indicators[j].bufferCount; b++)
               {
                  double val = indicators[j].data[d].values[b];
                  if(val == EMPTY_VALUE || val >= DBL_MAX / 2)
                     W(",null");
                  else
                     W("," + Dp3(val));
               }
               W("]");
            }
            W("]");

            W("}"); // end indicator object
         }
         W("}"); // end indicators

         W("}"); // end timeframe object
      }

      W("}"); // end data
   }

   //+------------------------------------------------------------------+
   //| Write pending orders section                                     |
   //+------------------------------------------------------------------+
   void WritePendingOrders(SPendingOrder &pending[], int count)
   {
      W("\"pendingOrders\":[");

      for(int i = 0; i < count; i++)
      {
         if(i > 0) W(",");

         W("{");
         W("\"ticket\":" + L((long)pending[i].ticket));
         W(",\"type\":" + QS(pending[i].type));
         W(",\"volume\":" + D2(pending[i].volume));
         W(",\"price\":" + Dp(pending[i].price));
         W(",\"sl\":" + Dp(pending[i].sl));
         W(",\"tp\":" + Dp(pending[i].tp));
         W(",\"placedTime\":" + L((long)pending[i].placedTime));
         W(",\"expiration\":" + L((long)pending[i].expiration));
         W(",\"status\":" + QS(SPendingOrder::StatusToString(pending[i].status)));

         if(pending[i].status == PENDING_STATUS_FILLED)
         {
            W(",\"filledTime\":" + L((long)pending[i].filledTime));
            W(",\"filledPrice\":" + Dp(pending[i].filledPrice));
            W(",\"resultOrderTicket\":" + L((long)pending[i].resultOrderTicket));
         }

         W("}");
      }

      W("]");
   }

   //+------------------------------------------------------------------+
   //| Write orders section (each order streamed individually)          |
   //+------------------------------------------------------------------+
   void WriteOrders(SOrder &orders[], int count)
   {
      W("\"orders\":[");

      for(int i = 0; i < count; i++)
      {
         if(i > 0) W(",");

         W("{");
         W("\"ticket\":" + L((long)orders[i].ticket));
         W(",\"type\":" + QS(orders[i].type));
         W(",\"volume\":" + D2(orders[i].volume));
         W(",\"openTime\":" + L((long)orders[i].openTime));
         W(",\"openPrice\":" + Dp(orders[i].openPrice));
         W(",\"sl\":" + Dp(orders[i].sl));
         W(",\"tp\":" + Dp(orders[i].tp));
         W(",\"comment\":" + QS(orders[i].comment));

         // Exits
         W(",\"exits\":[");
         for(int e = 0; e < orders[i].exitCount; e++)
         {
            if(e > 0) W(",");
            W("{");
            W("\"time\":" + L((long)orders[i].exits[e].time));
            W(",\"price\":" + Dp(orders[i].exits[e].price));
            W(",\"volume\":" + D2(orders[i].exits[e].volume));
            W(",\"reason\":" + QS(SExit::ReasonToString(orders[i].exits[e].reason)));
            W(",\"profit\":" + D2(orders[i].exits[e].profit));
            W(",\"commission\":" + D2(orders[i].exits[e].commission));
            W(",\"swap\":" + D2(orders[i].exits[e].swap));
            W("}");
         }
         W("]");

         // Aggregated P&L
         W(",\"totalProfit\":" + D2(orders[i].totalProfit));
         W(",\"totalCommission\":" + D2(orders[i].totalCommission));
         W(",\"totalSwap\":" + D2(orders[i].totalSwap));
         W(",\"netProfit\":" + D2(orders[i].netProfit));

         // Close values
         W(",\"closeTime\":" + L((long)orders[i].closeTime));
         W(",\"closePrice\":" + Dp(orders[i].closePrice));

         // Deals: [ticket, type, entry, time, price, volume, commission, profit]
         W(",\"deals\":[");
         for(int d = 0; d < orders[i].dealCount; d++)
         {
            if(d > 0) W(",");
            W("[" + L((long)orders[i].deals[d].ticket)
              + "," + QS(orders[i].deals[d].type)
              + "," + QS(orders[i].deals[d].entry)
              + "," + L((long)orders[i].deals[d].time)
              + "," + Dp(orders[i].deals[d].price)
              + "," + D2(orders[i].deals[d].volume)
              + "," + D2(orders[i].deals[d].commission)
              + "," + D2(orders[i].deals[d].profit)
              + "]");
         }
         W("]");

         // Indicator snapshots at entry
         W(",\"indEntry\":{");
         for(int ie = 0; ie < orders[i].indEntryCount; ie++)
         {
            if(ie > 0) W(",");
            W(QS(orders[i].indEntry[ie].name) + ":[");
            for(int v = 0; v < ArraySize(orders[i].indEntry[ie].values); v++)
            {
               if(v > 0) W(",");
               W(Dp3(orders[i].indEntry[ie].values[v]));
            }
            W("]");
         }
         W("}");

         // Indicator snapshots at exit
         W(",\"indExit\":{");
         for(int ix = 0; ix < orders[i].indExitCount; ix++)
         {
            if(ix > 0) W(",");
            W(QS(orders[i].indExit[ix].name) + ":[");
            for(int v = 0; v < ArraySize(orders[i].indExit[ix].values); v++)
            {
               if(v > 0) W(",");
               W(Dp3(orders[i].indExit[ix].values[v]));
            }
            W("]");
         }
         W("}");

         // Link to pending order
         if(orders[i].pendingOrderTicket > 0)
            W(",\"pendingOrderTicket\":" + L((long)orders[i].pendingOrderTicket));

         W("}"); // end order
      }

      W("]"); // end orders array
   }

   //+------------------------------------------------------------------+
   //| Write equity curve (STREAMING, row-by-row)                       |
   //+------------------------------------------------------------------+
   void WriteEquity(SEquityPoint &equity[], int count)
   {
      W("\"equity\":[");

      for(int i = 0; i < count; i++)
      {
         if(i > 0) W(",");
         W("[" + L((long)equity[i].time) + ","
               + D2(equity[i].balance) + ","
               + D2(equity[i].equity) + "]");
      }

      W("]");
   }
};

//+------------------------------------------------------------------+
