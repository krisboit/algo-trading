//+------------------------------------------------------------------+
//|                                              StrategyBase.mqh    |
//|  Shared framework: OnTester fitness, HasPosition, CloseAll       |
//|  Include this in every strategy EA                               |
//+------------------------------------------------------------------+
#ifndef FRAMEWORK_STRATEGYBASE_MQH
#define FRAMEWORK_STRATEGYBASE_MQH

//+------------------------------------------------------------------+
//| CalcFitness - Standard optimization fitness function              |
//| Returns: ProfitFactor * sqrt(Trades) * (1 - DD%/100)             |
//| Penalizes: < 10 trades=0, PF capped at 5, losing=0              |
//+------------------------------------------------------------------+
double CalcFitness()
{
   double profit      = TesterStatistics(STAT_PROFIT);
   double grossProfit = TesterStatistics(STAT_GROSS_PROFIT);
   double grossLoss   = TesterStatistics(STAT_GROSS_LOSS);
   double trades      = TesterStatistics(STAT_TRADES);
   double ddPercent   = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);

   // Minimum trades filter
   if(trades < 10) return 0.0;

   // Profit factor (capped at 5 to prevent overfitting)
   double pf = (grossLoss != 0) ? MathAbs(grossProfit / grossLoss) : 0.0;
   if(pf > 5.0) pf = 5.0;

   // Drawdown penalty: linear ramp 0-1 (0% DD = 1.0, 100% DD = 0.0)
   double ddFactor = MathMax(0.0, 1.0 - ddPercent / 100.0);

   // Trade count reward: sqrt scaling, bonus ramp for 10-30 trades
   double tradeFactor = MathSqrt(trades);
   if(trades < 30) tradeFactor *= (trades / 30.0); // penalize sparse trading

   // Losing strategies get 0
   if(profit <= 0 || pf < 1.0) return 0.0;

   return pf * tradeFactor * ddFactor;
}

//+------------------------------------------------------------------+
//| HasPosition - Check if we have an open position                  |
//| Parameters: symbol (default=current), magic number               |
//+------------------------------------------------------------------+
bool HasPosition(const string symbol, ulong magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| CloseAllPositions - Close all positions for symbol + magic       |
//+------------------------------------------------------------------+
void CloseAllPositions(const string symbol, ulong magic, CTrade &trade)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         trade.PositionClose(ticket);
      }
   }
}

#endif // FRAMEWORK_STRATEGYBASE_MQH
