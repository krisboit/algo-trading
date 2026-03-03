//+------------------------------------------------------------------+
//|                                                  JsonBuilder.mqh |
//|                                          Strategy Exporter v1.0  |
//|                         JSON serialization for strategy export   |
//+------------------------------------------------------------------+
#property copyright "Strategy Exporter"
#property version   "1.00"
#property strict

#include "DataTypes.mqh"
#include <JAson.mqh>

//+------------------------------------------------------------------+
//| JSON Builder class - converts data structures to JSON            |
//+------------------------------------------------------------------+
class CJsonBuilder
{
private:
   int m_digits;

public:
   CJsonBuilder() : m_digits(5) {}

   void SetDigits(int digits) { m_digits = digits; }

   //+------------------------------------------------------------------+
   //| Build complete JSON document                                     |
   //+------------------------------------------------------------------+
   string Build(string strategyName, string symbol, int digits, double point,
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

      CJAVal root;
      root.Clear(jtOBJ);

      // Build metadata
      BuildMeta(root, strategyName, symbol, digits, point, contractSize,
                currency, primaryTF, timeframes, tfCount,
                initialBalance, finalBalance, magicNumber,
                startDate, endDate);

      // Build stats
      BuildStats(root, stats);

      // Build timeframe data (candles + indicators)
      BuildData(root, timeframes, tfCount, indicators, indCount);

      // Build pending orders
      BuildPendingOrders(root, pending, pendingCount);

      // Build orders
      BuildOrders(root, orders, orderCount);

      // Build equity curve
      BuildEquity(root, equity, equityCount);

      return root.Serialize();
   }

private:
   //+------------------------------------------------------------------+
   //| Build metadata section                                           |
   //+------------------------------------------------------------------+
   void BuildMeta(CJAVal &root, string strategyName, string symbol,
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

      // Symbol info
      CJAVal sym;
      sym.Clear(jtOBJ);
      sym["name"] = symbol;
      sym["digits"] = digits;
      sym["point"] = point;
      sym["contractSize"] = contractSize;
      meta["symbol"].Copy(sym);

      // Timeframes array
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

      // Account mode
      ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
         meta["accountMode"] = "HEDGING";
      else
         meta["accountMode"] = "NETTING";

      meta["magicNumber"] = (long)magicNumber;

      // Timezone
      long gmtOffset = (long)(TimeLocal() - TimeGMT());
      int hours = (int)(gmtOffset / 3600);
      meta["timezone"] = StringFormat("UTC%s%d", hours >= 0 ? "+" : "", hours);

      meta["exportedAt"] = (long)TimeCurrent();

      root["meta"].Copy(meta);
   }

   //+------------------------------------------------------------------+
   //| Build stats section                                              |
   //+------------------------------------------------------------------+
   void BuildStats(CJAVal &root, SStats &stats)
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

      root["stats"].Copy(s);
   }

   //+------------------------------------------------------------------+
   //| Build timeframe data (candles + indicators)                      |
   //+------------------------------------------------------------------+
   void BuildData(CJAVal &root, STimeframeData &timeframes[], int tfCount,
                  SIndicatorInfo &indicators[], int indCount)
   {
      CJAVal data;
      data.Clear(jtOBJ);

      for(int t = 0; t < tfCount; t++)
      {
         CJAVal tfData;
         tfData.Clear(jtOBJ);

         // Candles array: [time, o, h, l, c, v]
         CJAVal candles;
         candles.Clear(jtARRAY);
         for(int i = 0; i < timeframes[t].candleCount; i++)
         {
            CJAVal c;
            c.Clear(jtARRAY);
            c[0] = (long)timeframes[t].candles[i].time;
            c[1] = NormalizeDouble(timeframes[t].candles[i].open, m_digits);
            c[2] = NormalizeDouble(timeframes[t].candles[i].high, m_digits);
            c[3] = NormalizeDouble(timeframes[t].candles[i].low, m_digits);
            c[4] = NormalizeDouble(timeframes[t].candles[i].close, m_digits);
            c[5] = timeframes[t].candles[i].volume;
            candles[i].Copy(c);
         }
         tfData["candles"].Copy(candles);

         // Indicators for this timeframe
         CJAVal inds;
         inds.Clear(jtOBJ);
         for(int j = 0; j < indCount; j++)
         {
            if(indicators[j].timeframe != timeframes[t].timeframe)
               continue;

            CJAVal ind;
            ind.Clear(jtOBJ);

            // Buffer names
            CJAVal bufNames;
            bufNames.Clear(jtARRAY);
            for(int b = 0; b < indicators[j].bufferCount; b++)
               bufNames[b] = indicators[j].bufferNames[b];
            ind["buffers"].Copy(bufNames);

            // Data: [time, val1, val2, ...]
            CJAVal indData;
            indData.Clear(jtARRAY);
            for(int d = 0; d < indicators[j].dataCount; d++)
            {
               CJAVal row;
               row.Clear(jtARRAY);
               row[0] = (long)indicators[j].data[d].time;
               for(int b = 0; b < indicators[j].bufferCount; b++)
               {
                  double val = indicators[j].data[d].values[b];
                  // Replace EMPTY_VALUE with null
                  if(val == EMPTY_VALUE || val >= DBL_MAX / 2)
                     row[b + 1] = (string)NULL;
                  else
                     row[b + 1] = NormalizeDouble(val, m_digits + 3);
               }
               indData[d].Copy(row);
            }
            ind["data"].Copy(indData);

            inds[indicators[j].name].Copy(ind);
         }
         tfData["indicators"].Copy(inds);

         data[timeframes[t].timeframeName].Copy(tfData);
      }

      root["data"].Copy(data);
   }

   //+------------------------------------------------------------------+
   //| Build pending orders section                                     |
   //+------------------------------------------------------------------+
   void BuildPendingOrders(CJAVal &root, SPendingOrder &pending[], int count)
   {
      CJAVal arr;
      arr.Clear(jtARRAY);

      for(int i = 0; i < count; i++)
      {
         CJAVal p;
         p.Clear(jtOBJ);
         p["ticket"] = (long)pending[i].ticket;
         p["type"] = pending[i].type;
         p["volume"] = NormalizeDouble(pending[i].volume, 2);
         p["price"] = NormalizeDouble(pending[i].price, m_digits);
         p["sl"] = NormalizeDouble(pending[i].sl, m_digits);
         p["tp"] = NormalizeDouble(pending[i].tp, m_digits);
         p["placedTime"] = (long)pending[i].placedTime;
         p["expiration"] = (long)pending[i].expiration;
         p["status"] = SPendingOrder::StatusToString(pending[i].status);

         if(pending[i].status == PENDING_STATUS_FILLED)
         {
            p["filledTime"] = (long)pending[i].filledTime;
            p["filledPrice"] = NormalizeDouble(pending[i].filledPrice, m_digits);
            p["resultOrderTicket"] = (long)pending[i].resultOrderTicket;
         }

         arr[i].Copy(p);
      }

      root["pendingOrders"].Copy(arr);
   }

   //+------------------------------------------------------------------+
   //| Build orders section                                             |
   //+------------------------------------------------------------------+
   void BuildOrders(CJAVal &root, SOrder &orders[], int count)
   {
      CJAVal arr;
      arr.Clear(jtARRAY);

      for(int i = 0; i < count; i++)
      {
         CJAVal o;
         o.Clear(jtOBJ);
         o["ticket"] = (long)orders[i].ticket;
         o["type"] = orders[i].type;
         o["volume"] = NormalizeDouble(orders[i].volume, 2);
         o["openTime"] = (long)orders[i].openTime;
         o["openPrice"] = NormalizeDouble(orders[i].openPrice, m_digits);
         o["sl"] = NormalizeDouble(orders[i].sl, m_digits);
         o["tp"] = NormalizeDouble(orders[i].tp, m_digits);
         o["comment"] = orders[i].comment;

         // Exits
         CJAVal exits;
         exits.Clear(jtARRAY);
         for(int e = 0; e < orders[i].exitCount; e++)
         {
            CJAVal ex;
            ex.Clear(jtOBJ);
            ex["time"] = (long)orders[i].exits[e].time;
            ex["price"] = NormalizeDouble(orders[i].exits[e].price, m_digits);
            ex["volume"] = NormalizeDouble(orders[i].exits[e].volume, 2);
            ex["reason"] = SExit::ReasonToString(orders[i].exits[e].reason);
            ex["profit"] = NormalizeDouble(orders[i].exits[e].profit, 2);
            ex["commission"] = NormalizeDouble(orders[i].exits[e].commission, 2);
            ex["swap"] = NormalizeDouble(orders[i].exits[e].swap, 2);
            exits[e].Copy(ex);
         }
         o["exits"].Copy(exits);

         // Aggregated P&L
         o["totalProfit"] = NormalizeDouble(orders[i].totalProfit, 2);
         o["totalCommission"] = NormalizeDouble(orders[i].totalCommission, 2);
         o["totalSwap"] = NormalizeDouble(orders[i].totalSwap, 2);
         o["netProfit"] = NormalizeDouble(orders[i].netProfit, 2);

         // Close values
         o["closeTime"] = (long)orders[i].closeTime;
         o["closePrice"] = NormalizeDouble(orders[i].closePrice, m_digits);

         // Deals: [ticket, type, entry, time, price, volume, commission, profit]
         CJAVal deals;
         deals.Clear(jtARRAY);
         for(int d = 0; d < orders[i].dealCount; d++)
         {
            CJAVal deal;
            deal.Clear(jtARRAY);
            deal[0] = (long)orders[i].deals[d].ticket;
            deal[1] = orders[i].deals[d].type;
            deal[2] = orders[i].deals[d].entry;
            deal[3] = (long)orders[i].deals[d].time;
            deal[4] = NormalizeDouble(orders[i].deals[d].price, m_digits);
            deal[5] = NormalizeDouble(orders[i].deals[d].volume, 2);
            deal[6] = NormalizeDouble(orders[i].deals[d].commission, 2);
            deal[7] = NormalizeDouble(orders[i].deals[d].profit, 2);
            deals[d].Copy(deal);
         }
         o["deals"].Copy(deals);

         // Indicator snapshots at entry
         CJAVal indEntry;
         indEntry.Clear(jtOBJ);
         for(int ie = 0; ie < orders[i].indEntryCount; ie++)
         {
            CJAVal vals;
            vals.Clear(jtARRAY);
            for(int v = 0; v < ArraySize(orders[i].indEntry[ie].values); v++)
               vals[v] = NormalizeDouble(orders[i].indEntry[ie].values[v], m_digits + 3);
            indEntry[orders[i].indEntry[ie].name].Copy(vals);
         }
         o["indEntry"].Copy(indEntry);

         // Indicator snapshots at exit
         CJAVal indExit;
         indExit.Clear(jtOBJ);
         for(int ix = 0; ix < orders[i].indExitCount; ix++)
         {
            CJAVal vals;
            vals.Clear(jtARRAY);
            for(int v = 0; v < ArraySize(orders[i].indExit[ix].values); v++)
               vals[v] = NormalizeDouble(orders[i].indExit[ix].values[v], m_digits + 3);
            indExit[orders[i].indExit[ix].name].Copy(vals);
         }
         o["indExit"].Copy(indExit);

         // Link to pending order
         if(orders[i].pendingOrderTicket > 0)
            o["pendingOrderTicket"] = (long)orders[i].pendingOrderTicket;

         arr[i].Copy(o);
      }

      root["orders"].Copy(arr);
   }

   //+------------------------------------------------------------------+
   //| Build equity curve section                                       |
   //+------------------------------------------------------------------+
   void BuildEquity(CJAVal &root, SEquityPoint &equity[], int count)
   {
      CJAVal arr;
      arr.Clear(jtARRAY);

      for(int i = 0; i < count; i++)
      {
         CJAVal point;
         point.Clear(jtARRAY);
         point[0] = (long)equity[i].time;
         point[1] = NormalizeDouble(equity[i].balance, 2);
         point[2] = NormalizeDouble(equity[i].equity, 2);
         arr[i].Copy(point);
      }

      root["equity"].Copy(arr);
   }
};

//+------------------------------------------------------------------+
