//+------------------------------------------------------------------+
//|                                            StrategyExporter.mqh  |
//|                                          Strategy Exporter v1.0  |
//|              Main class: collects data and exports to JSON       |
//+------------------------------------------------------------------+
#property copyright "Strategy Exporter"
#property version   "1.00"
#property strict

#include "DataTypes.mqh"
#include "StatsCalculator.mqh"
#include "JsonBuilder.mqh"

//+------------------------------------------------------------------+
//| Main Strategy Exporter Class                                     |
//+------------------------------------------------------------------+
class CStrategyExporter
{
private:
   // Configuration
   string            m_strategyName;
   string            m_symbol;
   ulong             m_magicNumber;
   double            m_initialBalance;
   ENUM_TIMEFRAMES   m_primaryTimeframe;

   // Timeframe data
   STimeframeData    m_timeframes[];
   int               m_tfCount;

   // Indicators
   SIndicatorInfo    m_indicators[];
   int               m_indCount;

   // Orders & deals
   SOrder            m_orders[];
   int               m_orderCount;

   // Pending orders
   SPendingOrder     m_pendingOrders[];
   int               m_pendingCount;

   // Equity curve
   SEquityPoint      m_equity[];
   int               m_equityCount;

   // Internal
   CStatsCalculator  m_statsCalc;
   CJsonBuilder      m_jsonBuilder;
    bool              m_initialized;
   bool              m_isOptimization;
   datetime          m_startDate;

   // Drawdown circuit breaker
   double            m_peakEquity;
   bool              m_stopped;
   static const double MAX_DRAWDOWN_PCT;  // 30%

   // Position tracking
   ulong             m_trackedPositions[];
   int               m_trackedPosCount;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CStrategyExporter()
   {
      m_initialized = false;
      m_isOptimization = false;
      m_tfCount = 0;
      m_indCount = 0;
      m_orderCount = 0;
      m_pendingCount = 0;
      m_equityCount = 0;
      m_trackedPosCount = 0;
      m_magicNumber = 0;
      m_startDate = 0;
      m_peakEquity = 0;
      m_stopped = false;
   }

   //+------------------------------------------------------------------+
   //| Initialize the exporter                                          |
   //+------------------------------------------------------------------+
   bool Init(string strategyName, ulong magicNumber = 0)
   {
      // Only work in tester or allow live usage
      m_strategyName = strategyName;
      m_symbol = _Symbol;
      m_magicNumber = magicNumber;
      m_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_primaryTimeframe = (ENUM_TIMEFRAMES)_Period;
      m_startDate = TimeCurrent();

      // Init arrays
      ArrayResize(m_timeframes, 0, 5);
      ArrayResize(m_indicators, 0, 20);
      ArrayResize(m_orders, 0, 500);
      ArrayResize(m_pendingOrders, 0, 100);
      ArrayResize(m_equity, 0, 50000);
      ArrayResize(m_trackedPositions, 0, 50);

      m_initialized = true;
      m_isOptimization = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
      m_peakEquity = m_initialBalance;
      m_stopped = false;

      if(m_isOptimization)
      {
         Print("[StrategyExporter] Optimization mode - data collection disabled");
         return true;
      }

      Print("[StrategyExporter] Initialized: ", strategyName, " on ", m_symbol,
            " TF=", STimeframeData::TimeframeToString(m_primaryTimeframe));

      return true;
   }

   //+------------------------------------------------------------------+
   //| Add a timeframe to track                                         |
   //+------------------------------------------------------------------+
   void AddTimeframe(ENUM_TIMEFRAMES tf)
   {
      int idx = m_tfCount;
      m_tfCount++;
      ArrayResize(m_timeframes, m_tfCount, 5);
      m_timeframes[idx].Init(tf);
   }

   //+------------------------------------------------------------------+
   //| Register an indicator with custom buffer names                   |
   //+------------------------------------------------------------------+
   void RegisterIndicator(int handle, string name, int bufferCount, string &bufferNames[])
   {
      if(handle == INVALID_HANDLE)
      {
         Print("[StrategyExporter] Warning: Invalid handle for indicator ", name);
         return;
      }

      int idx = m_indCount;
      m_indCount++;
      ArrayResize(m_indicators, m_indCount, 20);

      // Determine timeframe from chart if not specified
      ENUM_TIMEFRAMES tf = m_primaryTimeframe;
      m_indicators[idx].Init(handle, name, bufferCount, tf);
      m_indicators[idx].SetBufferNames(bufferNames);

      Print("[StrategyExporter] Registered indicator: ", name,
            " (", bufferCount, " buffers, handle=", handle, ")");
   }

   //+------------------------------------------------------------------+
   //| Register an indicator with default buffer names                  |
   //+------------------------------------------------------------------+
   void RegisterIndicator(int handle, string name, int bufferCount,
                          ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
   {
      if(handle == INVALID_HANDLE)
      {
         Print("[StrategyExporter] Warning: Invalid handle for indicator ", name);
         return;
      }

      if(tf == PERIOD_CURRENT)
         tf = m_primaryTimeframe;

      int idx = m_indCount;
      m_indCount++;
      ArrayResize(m_indicators, m_indCount, 20);
      m_indicators[idx].Init(handle, name, bufferCount, tf);
      m_indicators[idx].SetDefaultBufferNames();

      Print("[StrategyExporter] Registered indicator: ", name,
            " (", bufferCount, " buffers, handle=", handle, ", tf=",
            STimeframeData::TimeframeToString(tf), ")");
   }

   //+------------------------------------------------------------------+
   //| Call on every tick - collects data & checks drawdown             |
   //+------------------------------------------------------------------+
   void OnTick()
   {
      if(!m_initialized || m_stopped)
         return;

      // --- Drawdown circuit breaker (runs in ALL modes incl. optimization) ---
      if(MQLInfoInteger(MQL_TESTER))
         CheckDrawdown();

      // Skip data collection during optimization
      if(m_isOptimization)
         return;

      // Check each timeframe for new bar
      for(int t = 0; t < m_tfCount; t++)
      {
         if(IsNewBar(t))
         {
            CollectCandle(t);
            CollectIndicators(t);
         }
      }

      // Collect equity on primary timeframe bar close
      // (already handled above, but we also track equity)
      CollectEquity();
   }

   //+------------------------------------------------------------------+
   //| Call from EA's OnTradeTransaction                                |
   //+------------------------------------------------------------------+
   void OnTradeTransaction(const MqlTradeTransaction &trans,
                           const MqlTradeRequest &request,
                           const MqlTradeResult &result)
   {
      if(!m_initialized || m_isOptimization)
         return;

      // Filter by magic number if set
      if(m_magicNumber > 0)
      {
         // Check magic on deal add
         if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
         {
            if(HistoryDealSelect(trans.deal))
            {
               ulong dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
               if(dealMagic != m_magicNumber)
                  return;
            }
         }
      }

      switch(trans.type)
      {
         case TRADE_TRANSACTION_DEAL_ADD:
            ProcessDeal(trans.deal);
            break;

         case TRADE_TRANSACTION_ORDER_ADD:
            ProcessOrderAdd(trans.order, trans.order_type);
            break;

         case TRADE_TRANSACTION_ORDER_DELETE:
            ProcessOrderDelete(trans.order);
            break;

         default:
            break;
      }
   }

   //+------------------------------------------------------------------+
   //| Export all collected data to JSON file                           |
   //|                                                                  |
   //| v2.0: Opens file FIRST, passes handle to JsonBuilder.WriteTo()  |
   //|       so JSON is streamed directly to disk. No giant string.     |
   //+------------------------------------------------------------------+
   void Export()
   {
      if(!m_initialized)
      {
         Print("[StrategyExporter] Error: Not initialized");
         return;
      }

      // Skip export during optimization
      if(m_isOptimization)
      {
         Print("[StrategyExporter] Optimization mode - export skipped");
         return;
      }

      uint t0 = GetTickCount();

      // Step 1: Finalize history
      Print("[StrategyExporter] Step 1/4: Finalizing history...");
      FinalizeHistory();
      Print("[StrategyExporter] Step 1/4 done (", (GetTickCount() - t0), " ms)");

      // Step 2: Calculate statistics
      uint t1 = GetTickCount();
      Print("[StrategyExporter] Step 2/4: Calculating stats...");
      SStats stats;
      m_statsCalc.Calculate(stats, m_orders, m_orderCount,
                            m_equity, m_equityCount,
                            m_pendingOrders, m_pendingCount,
                            m_initialBalance);
      Print("[StrategyExporter] Step 2/4 done (", (GetTickCount() - t1), " ms)");

      double finalBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      datetime endDate = TimeCurrent();
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      string currency = AccountInfoString(ACCOUNT_CURRENCY);

      // Generate filename
      MqlDateTime dt;
      TimeToStruct(m_startDate, dt);
      MqlDateTime dt2;
      TimeToStruct(endDate, dt2);

      string filename = StringFormat("%s_%s_%s_%04d%02d%02d_%04d%02d%02d.json",
                                     m_strategyName, m_symbol,
                                     STimeframeData::TimeframeToString(m_primaryTimeframe),
                                     dt.year, dt.mon, dt.day,
                                     dt2.year, dt2.mon, dt2.day);

      // Step 3: Open file and stream JSON directly
      uint t2 = GetTickCount();
      Print("[StrategyExporter] Step 3/4: Streaming JSON to file ", filename, " (",
            m_orderCount, " orders, ",
            m_equityCount, " equity pts, ",
            m_tfCount, " timeframes)...");
      for(int t = 0; t < m_tfCount; t++)
         Print("[StrategyExporter]   TF ", m_timeframes[t].timeframeName,
               ": ", m_timeframes[t].candleCount, " candles");
      for(int i = 0; i < m_indCount; i++)
         Print("[StrategyExporter]   Ind ", m_indicators[i].name,
               ": ", m_indicators[i].dataCount, " values");

      int fileHandle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(fileHandle == INVALID_HANDLE)
      {
         Print("[StrategyExporter] Error: Cannot open file ", filename,
               " Error=", GetLastError());
         return;
      }

      m_jsonBuilder.WriteTo(
         fileHandle,
         m_strategyName, m_symbol, digits, point, contractSize, currency,
         m_primaryTimeframe,
         m_timeframes, m_tfCount,
         m_indicators, m_indCount,
         m_orders, m_orderCount,
         m_pendingOrders, m_pendingCount,
         m_equity, m_equityCount,
         stats,
         m_initialBalance, finalBalance,
         m_magicNumber,
         m_startDate, endDate
      );

      FileClose(fileHandle);
      Print("[StrategyExporter] Step 3/4 done (", (GetTickCount() - t2), " ms)");

      // Step 4: Done
      Print("[StrategyExporter] Step 4/4: Export complete! Total time: ",
            (GetTickCount() - t0), " ms");
      Print("[StrategyExporter] Exported to: MQL5/Files/", filename);
   }

private:
   //+------------------------------------------------------------------+
   //| Drawdown circuit breaker - stops test if DD > 30%                |
   //| Tracks peak equity and calls TesterStop() on breach.             |
   //| Works in both optimization (fast reject) and single test modes.  |
   //+------------------------------------------------------------------+
   void CheckDrawdown()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      if(equity > m_peakEquity)
         m_peakEquity = equity;

      if(m_peakEquity <= 0)
         return;

      double ddPct = (m_peakEquity - equity) / m_peakEquity * 100.0;

      if(ddPct > MAX_DRAWDOWN_PCT)
      {
         Print("[StrategyExporter] Drawdown ", DoubleToString(ddPct, 1),
               "% exceeded ", DoubleToString(MAX_DRAWDOWN_PCT, 0),
               "% limit. Stopping test.");
         m_stopped = true;
         TesterStop();
      }
   }

   //+------------------------------------------------------------------+
   //| Check if a new bar has formed on timeframe                       |
   //+------------------------------------------------------------------+
   bool IsNewBar(int tfIndex)
   {
      datetime currentBarTime = iTime(m_symbol, m_timeframes[tfIndex].timeframe, 0);
      if(currentBarTime == 0)
         return false;

      if(currentBarTime != m_timeframes[tfIndex].lastBarTime)
      {
         m_timeframes[tfIndex].lastBarTime = currentBarTime;
         return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Collect candle data for timeframe                                |
   //+------------------------------------------------------------------+
   void CollectCandle(int tfIndex)
   {
      // We collect the previous (completed) bar
      double open  = iOpen(m_symbol, m_timeframes[tfIndex].timeframe, 1);
      double high  = iHigh(m_symbol, m_timeframes[tfIndex].timeframe, 1);
      double low   = iLow(m_symbol, m_timeframes[tfIndex].timeframe, 1);
      double close = iClose(m_symbol, m_timeframes[tfIndex].timeframe, 1);
      long   vol   = iVolume(m_symbol, m_timeframes[tfIndex].timeframe, 1);
      datetime time = iTime(m_symbol, m_timeframes[tfIndex].timeframe, 1);

      if(time == 0)
         return;

      m_timeframes[tfIndex].AddCandle(time, open, high, low, close, vol);
   }

   //+------------------------------------------------------------------+
   //| Collect indicator values for completed bar                       |
   //+------------------------------------------------------------------+
   void CollectIndicators(int tfIndex)
   {
      ENUM_TIMEFRAMES tf = m_timeframes[tfIndex].timeframe;
      datetime barTime = iTime(m_symbol, tf, 1);

      if(barTime == 0)
         return;

      for(int i = 0; i < m_indCount; i++)
      {
         if(m_indicators[i].timeframe != tf)
            continue;

         double values[];
         ArrayResize(values, m_indicators[i].bufferCount);

         bool valid = true;
         for(int b = 0; b < m_indicators[i].bufferCount; b++)
         {
            double buf[];
            if(CopyBuffer(m_indicators[i].handle, b, 1, 1, buf) == 1)
               values[b] = buf[0];
            else
            {
               values[b] = EMPTY_VALUE;
               valid = false;
            }
         }

         m_indicators[i].AddValue(barTime, values);
      }
   }

   //+------------------------------------------------------------------+
   //| Collect equity snapshot                                          |
   //+------------------------------------------------------------------+
   void CollectEquity()
   {
      // Only collect on primary TF bar close to avoid too many points
      static datetime lastEquityTime = 0;
      datetime currentTime = iTime(m_symbol, m_primaryTimeframe, 0);

      if(currentTime == lastEquityTime || currentTime == 0)
         return;

      lastEquityTime = currentTime;

      int idx = m_equityCount;
      m_equityCount++;
      ArrayResize(m_equity, m_equityCount, 50000);
      m_equity[idx].time = currentTime;
      m_equity[idx].balance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_equity[idx].equity = AccountInfoDouble(ACCOUNT_EQUITY);
   }

   //+------------------------------------------------------------------+
   //| Process a deal that was added                                    |
   //+------------------------------------------------------------------+
   void ProcessDeal(ulong dealTicket)
   {
      if(!HistoryDealSelect(dealTicket))
         return;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);

      // Only process buy/sell deals
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
         return;

      ulong posId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      ulong orderTicket = HistoryDealGetInteger(dealTicket, DEAL_ORDER);

      // Build deal struct
      SDeal deal;
      deal.ticket = dealTicket;
      deal.type = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
      deal.time = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      deal.price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      deal.volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      deal.commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      deal.profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      deal.swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);

      switch(entry)
      {
         case DEAL_ENTRY_IN:
            deal.entry = "IN";
            ProcessEntryDeal(deal, posId, orderTicket);
            break;

         case DEAL_ENTRY_OUT:
         case DEAL_ENTRY_OUT_BY:
            deal.entry = (entry == DEAL_ENTRY_OUT) ? "OUT" : "OUT_BY";
            ProcessExitDeal(deal, posId);
            break;

         case DEAL_ENTRY_INOUT:
            deal.entry = "INOUT";
            ProcessExitDeal(deal, posId);
            break;

         default:
            break;
      }
   }

   //+------------------------------------------------------------------+
   //| Process entry deal - create new order record                     |
   //+------------------------------------------------------------------+
   void ProcessEntryDeal(SDeal &deal, ulong posId, ulong orderTicket)
   {
      int idx = m_orderCount;
      m_orderCount++;
      ArrayResize(m_orders, m_orderCount, 500);
      m_orders[idx].Init();

      m_orders[idx].ticket = posId;
      m_orders[idx].type = deal.type;
      m_orders[idx].volume = deal.volume;
      m_orders[idx].openTime = deal.time;
      m_orders[idx].openPrice = deal.price;
      m_orders[idx].comment = HistoryDealGetString(deal.ticket, DEAL_COMMENT);

      // Get SL/TP from position if still open
      if(PositionSelectByTicket(posId))
      {
         m_orders[idx].sl = PositionGetDouble(POSITION_SL);
         m_orders[idx].tp = PositionGetDouble(POSITION_TP);
      }

      // Add the entry deal
      m_orders[idx].AddDeal(deal);

      // Link to pending order if applicable
      if(orderTicket > 0)
      {
         for(int p = 0; p < m_pendingCount; p++)
         {
            if(m_pendingOrders[p].ticket == orderTicket)
            {
               m_pendingOrders[p].status = PENDING_STATUS_FILLED;
               m_pendingOrders[p].filledTime = deal.time;
               m_pendingOrders[p].filledPrice = deal.price;
               m_pendingOrders[p].resultOrderTicket = posId;
               m_orders[idx].pendingOrderTicket = orderTicket;
               break;
            }
         }
      }

      // Snapshot indicators at entry
      SnapshotIndicators(idx, true);

      // Track position
      m_trackedPosCount++;
      ArrayResize(m_trackedPositions, m_trackedPosCount, 50);
      m_trackedPositions[m_trackedPosCount - 1] = posId;
   }

   //+------------------------------------------------------------------+
   //| Process exit deal - add to existing order                        |
   //+------------------------------------------------------------------+
   void ProcessExitDeal(SDeal &deal, ulong posId)
   {
      // Find the order by position ID
      int orderIdx = -1;
      for(int i = m_orderCount - 1; i >= 0; i--)
      {
         if(m_orders[i].ticket == posId)
         {
            orderIdx = i;
            break;
         }
      }

      if(orderIdx < 0)
         return;

      // Add deal to order
      m_orders[orderIdx].AddDeal(deal);

      // Determine exit reason
      ENUM_EXIT_REASON reason = EXIT_REASON_MANUAL;

      // Check if it's a partial close
      double remainingVolume = m_orders[orderIdx].volume;
      for(int e = 0; e < m_orders[orderIdx].exitCount; e++)
         remainingVolume -= m_orders[orderIdx].exits[e].volume;

      bool isPartial = (deal.volume < remainingVolume - 0.0001);

      // Try to determine if SL or TP hit
      double slPrice = m_orders[orderIdx].sl;
      double tpPrice = m_orders[orderIdx].tp;
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double tolerance = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 3;

      if(tpPrice > 0 && MathAbs(deal.price - tpPrice) < tolerance)
         reason = isPartial ? EXIT_REASON_PARTIAL_TP : EXIT_REASON_TP;
      else if(slPrice > 0 && MathAbs(deal.price - slPrice) < tolerance)
         reason = isPartial ? EXIT_REASON_PARTIAL_SL : EXIT_REASON_SL;
      else if(deal.profit >= 0)
         reason = isPartial ? EXIT_REASON_PARTIAL_TP : EXIT_REASON_MANUAL;
      else
         reason = isPartial ? EXIT_REASON_PARTIAL_SL : EXIT_REASON_MANUAL;

      // Build exit
      SExit exit;
      exit.time = deal.time;
      exit.price = deal.price;
      exit.volume = deal.volume;
      exit.reason = reason;
      exit.profit = deal.profit;
      exit.commission = deal.commission;
      exit.swap = deal.swap;

      m_orders[orderIdx].AddExit(exit);

      // Check if position fully closed
      double closedVolume = 0;
      for(int e = 0; e < m_orders[orderIdx].exitCount; e++)
         closedVolume += m_orders[orderIdx].exits[e].volume;

      if(closedVolume >= m_orders[orderIdx].volume - 0.0001)
      {
         // Position fully closed - snapshot indicators at exit
         SnapshotIndicators(orderIdx, false);

         // Remove from tracked positions
         RemoveTrackedPosition(posId);
      }
   }

   //+------------------------------------------------------------------+
   //| Process new pending order                                        |
   //+------------------------------------------------------------------+
   void ProcessOrderAdd(ulong orderTicket, ENUM_ORDER_TYPE orderType)
   {
      // Only track pending order types
      if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT &&
         orderType != ORDER_TYPE_BUY_STOP && orderType != ORDER_TYPE_SELL_STOP &&
         orderType != ORDER_TYPE_BUY_STOP_LIMIT && orderType != ORDER_TYPE_SELL_STOP_LIMIT)
         return;

      // Check if order is still in the order book
      if(!OrderSelect(orderTicket))
         return;

      int idx = m_pendingCount;
      m_pendingCount++;
      ArrayResize(m_pendingOrders, m_pendingCount, 100);
      m_pendingOrders[idx].Init();

      m_pendingOrders[idx].ticket = orderTicket;
      m_pendingOrders[idx].type = SPendingOrder::OrderTypeToString(orderType);
      m_pendingOrders[idx].volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      m_pendingOrders[idx].price = OrderGetDouble(ORDER_PRICE_OPEN);
      m_pendingOrders[idx].sl = OrderGetDouble(ORDER_SL);
      m_pendingOrders[idx].tp = OrderGetDouble(ORDER_TP);
      m_pendingOrders[idx].placedTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      m_pendingOrders[idx].expiration = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
   }

   //+------------------------------------------------------------------+
   //| Process deleted/expired pending order                            |
   //+------------------------------------------------------------------+
   void ProcessOrderDelete(ulong orderTicket)
   {
      for(int i = 0; i < m_pendingCount; i++)
      {
         if(m_pendingOrders[i].ticket == orderTicket &&
            m_pendingOrders[i].status == PENDING_STATUS_ACTIVE)
         {
            // Check history to see if it was filled or deleted
            if(HistoryOrderSelect(orderTicket))
            {
               ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)HistoryOrderGetInteger(orderTicket, ORDER_STATE);
               if(state == ORDER_STATE_EXPIRED)
                  m_pendingOrders[i].status = PENDING_STATUS_EXPIRED;
               else if(state == ORDER_STATE_CANCELED)
                  m_pendingOrders[i].status = PENDING_STATUS_CANCELLED;
               else if(state == ORDER_STATE_FILLED)
               {
                  // Already handled in ProcessDeal
               }
               else
                  m_pendingOrders[i].status = PENDING_STATUS_CANCELLED;
            }
            else
            {
               m_pendingOrders[i].status = PENDING_STATUS_CANCELLED;
            }
            break;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Snapshot current indicator values for a trade                    |
   //+------------------------------------------------------------------+
   void SnapshotIndicators(int orderIdx, bool isEntry)
   {
      for(int i = 0; i < m_indCount; i++)
      {
         double values[];
         ArrayResize(values, m_indicators[i].bufferCount);
         bool valid = true;

         for(int b = 0; b < m_indicators[i].bufferCount; b++)
         {
            double buf[];
            if(CopyBuffer(m_indicators[i].handle, b, 0, 1, buf) == 1)
               values[b] = buf[0];
            else
            {
               values[b] = 0;
               valid = false;
            }
         }

         m_orders[orderIdx].AddIndicatorSnapshot(isEntry, m_indicators[i].name, values);
      }
   }

   //+------------------------------------------------------------------+
   //| Remove position from tracking array                              |
   //+------------------------------------------------------------------+
   void RemoveTrackedPosition(ulong posId)
   {
      for(int i = 0; i < m_trackedPosCount; i++)
      {
         if(m_trackedPositions[i] == posId)
         {
            // Shift remaining elements
            for(int j = i; j < m_trackedPosCount - 1; j++)
               m_trackedPositions[j] = m_trackedPositions[j + 1];
            m_trackedPosCount--;
            ArrayResize(m_trackedPositions, m_trackedPosCount, 50);
            break;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Finalize history - process remaining deals from history          |
   //+------------------------------------------------------------------+
   void FinalizeHistory()
   {
      // Select all history
      HistorySelect(m_startDate, TimeCurrent());

      // Update SL/TP from history for orders that might have been modified
      for(int i = 0; i < m_orderCount; i++)
      {
         // If order still has no SL/TP, try to get from history
         if(m_orders[i].sl == 0 || m_orders[i].tp == 0)
         {
            // Look through deals for this position
            for(int d = 0; d < m_orders[i].dealCount; d++)
            {
               ulong dealTicket = m_orders[i].deals[d].ticket;
               if(HistoryDealSelect(dealTicket))
               {
                  ulong dealOrder = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
                  if(HistoryOrderSelect(dealOrder))
                  {
                     if(m_orders[i].sl == 0)
                        m_orders[i].sl = HistoryOrderGetDouble(dealOrder, ORDER_SL);
                     if(m_orders[i].tp == 0)
                        m_orders[i].tp = HistoryOrderGetDouble(dealOrder, ORDER_TP);
                  }
               }
            }
         }
      }

      Print("[StrategyExporter] Finalized: ", m_orderCount, " orders, ",
            m_pendingCount, " pending orders");
   }
};

// Static const initialization
const double CStrategyExporter::MAX_DRAWDOWN_PCT = 30.0;

//+------------------------------------------------------------------+
