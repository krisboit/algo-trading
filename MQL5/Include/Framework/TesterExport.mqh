//+------------------------------------------------------------------+
//|                                             TesterExport.mqh     |
//|  Optimization per-pass result export for worker collection       |
//|  Writes profitable + low-DD passes to CSV in agent sandbox       |
//+------------------------------------------------------------------+
#ifndef FRAMEWORK_TESTEREXPORT_MQH
#define FRAMEWORK_TESTEREXPORT_MQH

//+------------------------------------------------------------------+
//| TesterExportPass - Write one optimization pass result to file    |
//|                                                                  |
//| Called from each EA's OnTester() with its input param names/vals. |
//| Only writes if: profit > 0 AND drawdown < 30%.                   |
//|                                                                  |
//| Output format (one line per pass, CSV):                          |
//| profit,profitFactor,expectedPayoff,recoveryFactor,sharpeRatio,   |
//| drawdownPercent,trades,customCriterion,param1=val1,param2=val2   |
//|                                                                  |
//| File lands in: Tester/Agent-X/MQL5/Files/opt_results.csv         |
//| Worker collects all agent files after MT5 exits.                 |
//+------------------------------------------------------------------+
void TesterExportPass(const string &paramNames[], const double &paramValues[], double fitness)
{
   // Get tester statistics
   double profit         = TesterStatistics(STAT_PROFIT);
   double profitFactor   = TesterStatistics(STAT_PROFIT_FACTOR);
   double expectedPayoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
   double recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);
   double sharpeRatio    = TesterStatistics(STAT_SHARPE_RATIO);
   double ddPercent      = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades         = TesterStatistics(STAT_TRADES);

   // Filter: only write profitable passes with acceptable drawdown
   if(profit <= 0) return;
   if(ddPercent > 30.0) return;
   if(trades < 10) return;

   // Build CSV line
   string line = StringFormat("%.2f,%.4f,%.4f,%.4f,%.4f,%.2f,%.0f,%.4f",
                              profit, profitFactor, expectedPayoff,
                              recoveryFactor, sharpeRatio, ddPercent,
                              trades, fitness);

   // Append input parameters
   int count = ArraySize(paramNames);
   for(int i = 0; i < count; i++)
   {
      line += StringFormat(",%s=%.8g", paramNames[i], paramValues[i]);
   }

   // Write to file (append mode)
   int handle = FileOpen("opt_results.csv", FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);
      FileWriteString(handle, line + "\n");
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| Overload for string parameters (enum values, etc.)               |
//+------------------------------------------------------------------+
void TesterExportPass(const string &paramNames[], const string &paramValues[], double fitness)
{
   double profit         = TesterStatistics(STAT_PROFIT);
   double profitFactor   = TesterStatistics(STAT_PROFIT_FACTOR);
   double expectedPayoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
   double recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);
   double sharpeRatio    = TesterStatistics(STAT_SHARPE_RATIO);
   double ddPercent      = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades         = TesterStatistics(STAT_TRADES);

   if(profit <= 0) return;
   if(ddPercent > 30.0) return;
   if(trades < 10) return;

   string line = StringFormat("%.2f,%.4f,%.4f,%.4f,%.4f,%.2f,%.0f,%.4f",
                              profit, profitFactor, expectedPayoff,
                              recoveryFactor, sharpeRatio, ddPercent,
                              trades, fitness);

   int count = ArraySize(paramNames);
   for(int i = 0; i < count; i++)
   {
      line += StringFormat(",%s=%s", paramNames[i], paramValues[i]);
   }

   int handle = FileOpen("opt_results.csv", FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);
      FileWriteString(handle, line + "\n");
      FileClose(handle);
   }
}

#endif // FRAMEWORK_TESTEREXPORT_MQH
