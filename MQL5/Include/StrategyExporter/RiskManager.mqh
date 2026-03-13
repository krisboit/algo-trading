//+------------------------------------------------------------------+
//|                                               RiskManager.mqh    |
//|                        Position sizing based on % account risk   |
//+------------------------------------------------------------------+
#property copyright "Strategy Exporter"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Calculate lot size based on % risk and SL distance               |
//+------------------------------------------------------------------+
double CalcLotSize(string symbol, double riskPercent, double slPoints)
{
   if(slPoints <= 0) return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * riskPercent / 100.0;

   // Get tick value for 1 lot
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(tickSize == 0 || tickValue == 0 || point == 0)
      return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   // Value per point per lot
   double pointValue = tickValue * (point / tickSize);

   // Lot size = risk money / (SL in points * value per point)
   double lots = riskMoney / (slPoints * pointValue);

   // Clamp to symbol limits
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(lotStep > 0)
      lots = MathFloor(lots / lotStep) * lotStep;

   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);

   return NormalizeDouble(lots, 8);
}

//+------------------------------------------------------------------+
//| Normalize price to symbol digits                                 |
//+------------------------------------------------------------------+
double NormPrice(string symbol, double price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}
//+------------------------------------------------------------------+
