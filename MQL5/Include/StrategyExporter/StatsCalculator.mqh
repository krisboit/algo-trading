//+------------------------------------------------------------------+
//|                                              StatsCalculator.mqh |
//|                                          Strategy Exporter v1.0  |
//|                   Statistics computation for strategy export     |
//+------------------------------------------------------------------+
#property copyright "Strategy Exporter"
#property version   "1.00"
#property strict

#include "DataTypes.mqh"

//+------------------------------------------------------------------+
//| Stats calculator class                                           |
//+------------------------------------------------------------------+
class CStatsCalculator
{
public:
   //+------------------------------------------------------------------+
   //| Calculate all stats from orders, equity, and pending orders      |
   //+------------------------------------------------------------------+
   void Calculate(SStats &stats,
                  SOrder &orders[], int orderCount,
                  SEquityPoint &equity[], int equityCount,
                  SPendingOrder &pending[], int pendingCount,
                  double initialBalance)
   {
      stats.Init();

      if(orderCount == 0)
         return;

      CalculateTradeStats(stats, orders, orderCount, initialBalance);
      CalculateDrawdown(stats, equity, equityCount);
      CalculateSharpe(stats, orders, orderCount);
      CalculateConsecutive(stats, orders, orderCount);
      CalculateDuration(stats, orders, orderCount);
      CalculateMonthly(stats, orders, orderCount, initialBalance);
      CalculatePendingStats(stats, pending, pendingCount);
   }

private:
   //+------------------------------------------------------------------+
   //| Basic trade statistics                                           |
   //+------------------------------------------------------------------+
   void CalculateTradeStats(SStats &stats, SOrder &orders[], int count, double initialBalance)
   {
      stats.totalTrades = count;
      stats.largestLoss = 0;

      double totalWinAmount = 0;
      double totalLossAmount = 0;

      for(int i = 0; i < count; i++)
      {
         double np = orders[i].netProfit;

         stats.totalCommission += orders[i].totalCommission;
         stats.totalSwap += orders[i].totalSwap;

         if(np >= 0)
         {
            stats.winningTrades++;
            stats.grossProfit += np;
            totalWinAmount += np;
            if(np > stats.largestWin)
               stats.largestWin = np;
         }
         else
         {
            stats.losingTrades++;
            stats.grossLoss += np; // negative value
            totalLossAmount += np;
            if(np < stats.largestLoss)
               stats.largestLoss = np;
         }
      }

      stats.netProfit = stats.grossProfit + stats.grossLoss;
      stats.netProfitPct = (initialBalance > 0) ? (stats.netProfit / initialBalance) * 100.0 : 0;

      stats.winRate = (stats.totalTrades > 0) ? (double)stats.winningTrades / (double)stats.totalTrades : 0;

      stats.profitFactor = (stats.grossLoss != 0) ? MathAbs(stats.grossProfit / stats.grossLoss) : 
                           (stats.grossProfit > 0 ? 999.99 : 0);

      stats.avgWin = (stats.winningTrades > 0) ? totalWinAmount / stats.winningTrades : 0;
      stats.avgLoss = (stats.losingTrades > 0) ? MathAbs(totalLossAmount / stats.losingTrades) : 0;

      stats.expectancy = (stats.winRate * stats.avgWin) - ((1.0 - stats.winRate) * stats.avgLoss);

      // If no losing trades, clean up largestLoss
      if(stats.losingTrades == 0)
         stats.largestLoss = 0;
   }

   //+------------------------------------------------------------------+
   //| Drawdown calculation from equity curve                           |
   //+------------------------------------------------------------------+
   void CalculateDrawdown(SStats &stats, SEquityPoint &equity[], int count)
   {
      if(count == 0)
         return;

      double peak = equity[0].equity;
      stats.maxDrawdown = 0;
      stats.maxDrawdownPct = 0;

      for(int i = 1; i < count; i++)
      {
         if(equity[i].equity > peak)
            peak = equity[i].equity;

         double dd = peak - equity[i].equity;
         double ddPct = (peak > 0) ? (dd / peak) * 100.0 : 0;

         if(dd > stats.maxDrawdown)
         {
            stats.maxDrawdown = dd;
            stats.maxDrawdownPct = ddPct;
            stats.maxDrawdownDate = equity[i].time;
         }
      }

      stats.recoveryFactor = (stats.maxDrawdown > 0) ? stats.netProfit / stats.maxDrawdown : 0;
   }

   //+------------------------------------------------------------------+
   //| Sharpe ratio (using per-trade returns)                           |
   //+------------------------------------------------------------------+
   void CalculateSharpe(SStats &stats, SOrder &orders[], int count)
   {
      if(count < 2)
      {
         stats.sharpeRatio = 0;
         return;
      }

      double returns[];
      ArrayResize(returns, count);

      double sum = 0;
      for(int i = 0; i < count; i++)
      {
         returns[i] = orders[i].netProfit;
         sum += returns[i];
      }

      double mean = sum / count;

      double sumSqDev = 0;
      for(int i = 0; i < count; i++)
      {
         double dev = returns[i] - mean;
         sumSqDev += dev * dev;
      }

      double stdDev = MathSqrt(sumSqDev / (count - 1));

      stats.sharpeRatio = (stdDev > 0) ? mean / stdDev : 0;
   }

   //+------------------------------------------------------------------+
   //| Consecutive wins/losses                                          |
   //+------------------------------------------------------------------+
   void CalculateConsecutive(SStats &stats, SOrder &orders[], int count)
   {
      int currentWins = 0;
      int currentLosses = 0;

      for(int i = 0; i < count; i++)
      {
         if(orders[i].netProfit >= 0)
         {
            currentWins++;
            currentLosses = 0;
            if(currentWins > stats.maxConsecutiveWins)
               stats.maxConsecutiveWins = currentWins;
         }
         else
         {
            currentLosses++;
            currentWins = 0;
            if(currentLosses > stats.maxConsecutiveLosses)
               stats.maxConsecutiveLosses = currentLosses;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Average trade duration in seconds                                |
   //+------------------------------------------------------------------+
   void CalculateDuration(SStats &stats, SOrder &orders[], int count)
   {
      if(count == 0)
         return;

      long totalDuration = 0;
      int validCount = 0;

      for(int i = 0; i < count; i++)
      {
         if(orders[i].closeTime > orders[i].openTime)
         {
            totalDuration += (long)(orders[i].closeTime - orders[i].openTime);
            validCount++;
         }
      }

      stats.avgTradeDuration = (validCount > 0) ? (int)(totalDuration / validCount) : 0;
   }

   //+------------------------------------------------------------------+
   //| Monthly performance breakdown                                    |
   //+------------------------------------------------------------------+
   void CalculateMonthly(SStats &stats, SOrder &orders[], int count, double initialBalance)
   {
      if(count == 0)
         return;

      // Find unique months from orders
      string months[];
      int monthIdx[];
      ArrayResize(months, 0, 24);
      ArrayResize(monthIdx, 0, 24);
      int monthCount = 0;

      for(int i = 0; i < count; i++)
      {
         MqlDateTime dt;
         TimeToStruct(orders[i].closeTime > 0 ? orders[i].closeTime : orders[i].openTime, dt);
         string monthStr = StringFormat("%04d-%02d", dt.year, dt.mon);

         // Find or add month
         bool found = false;
         for(int m = 0; m < monthCount; m++)
         {
            if(months[m] == monthStr)
            {
               found = true;
               break;
            }
         }
         if(!found)
         {
            monthCount++;
            ArrayResize(months, monthCount, 24);
            months[monthCount - 1] = monthStr;
         }
      }

      // Sort months
      for(int i = 0; i < monthCount - 1; i++)
         for(int j = i + 1; j < monthCount; j++)
            if(months[j] < months[i])
            {
               string tmp = months[i];
               months[i] = months[j];
               months[j] = tmp;
            }

      // Calculate stats per month
      ArrayResize(stats.monthly, monthCount);
      stats.monthlyCount = monthCount;

      double runningBalance = initialBalance;

      for(int m = 0; m < monthCount; m++)
      {
         stats.monthly[m].month = months[m];
         stats.monthly[m].profit = 0;
         stats.monthly[m].trades = 0;
         stats.monthly[m].winningTrades = 0;
         stats.monthly[m].losingTrades = 0;

         double startBalance = runningBalance;

         for(int i = 0; i < count; i++)
         {
            MqlDateTime dt;
            TimeToStruct(orders[i].closeTime > 0 ? orders[i].closeTime : orders[i].openTime, dt);
            string monthStr = StringFormat("%04d-%02d", dt.year, dt.mon);

            if(monthStr == months[m])
            {
               stats.monthly[m].profit += orders[i].netProfit;
               stats.monthly[m].trades++;
               if(orders[i].netProfit >= 0)
                  stats.monthly[m].winningTrades++;
               else
                  stats.monthly[m].losingTrades++;
            }
         }

         stats.monthly[m].profitPct = (startBalance > 0) ? (stats.monthly[m].profit / startBalance) * 100.0 : 0;
         stats.monthly[m].winRate = (stats.monthly[m].trades > 0) ?
                                    (double)stats.monthly[m].winningTrades / (double)stats.monthly[m].trades : 0;

         runningBalance += stats.monthly[m].profit;
      }
   }

   //+------------------------------------------------------------------+
   //| Pending order statistics                                         |
   //+------------------------------------------------------------------+
   void CalculatePendingStats(SStats &stats, SPendingOrder &pending[], int count)
   {
      for(int i = 0; i < count; i++)
      {
         switch(pending[i].status)
         {
            case PENDING_STATUS_FILLED:    stats.pendingOrdersFilled++; break;
            case PENDING_STATUS_CANCELLED: stats.pendingOrdersCancelled++; break;
            case PENDING_STATUS_EXPIRED:   stats.pendingOrdersExpired++; break;
            default: break;
         }
      }
   }
};

//+------------------------------------------------------------------+
