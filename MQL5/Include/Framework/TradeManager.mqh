//+------------------------------------------------------------------+
//|                                             TradeManager.mqh     |
//|  Shared framework: ATR trailing stop, breakeven, partial close   |
//+------------------------------------------------------------------+
#ifndef FRAMEWORK_TRADEMANAGER_MQH
#define FRAMEWORK_TRADEMANAGER_MQH

#include <StrategyExporter/RiskManager.mqh>

//+------------------------------------------------------------------+
//| ManageTrailingStopATR - ATR-based trailing stop for all positions |
//| Call once per bar. Moves SL if new SL is better than current.    |
//| Only activates after position is in profit > entry price.        |
//+------------------------------------------------------------------+
void ManageTrailingStopATR(const string symbol, ulong magic, CTrade &trade,
                           int atrHandle, double multiplier)
{
   double atr[];
   if(CopyBuffer(atrHandle, 0, 1, 1, atr) != 1) return;

   double trailDist = atr[0] * multiplier;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;

      ulong  ticket    = PositionGetInteger(POSITION_TICKET);
      double openPx    = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(posType == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         double newSL = NormPrice(symbol, bid - trailDist);
         if(newSL > currentSL && newSL > openPx)
            trade.PositionModify(ticket, newSL, tp);
      }
      else
      {
         double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         double newSL = NormPrice(symbol, ask + trailDist);
         if(newSL < currentSL && newSL < openPx)
            trade.PositionModify(ticket, newSL, tp);
      }
   }
}

//+------------------------------------------------------------------+
//| CheckBreakEven - Move SL to breakeven at 1R profit               |
//| Call every tick for responsive breakeven. Returns true if         |
//| breakeven was applied on any position.                           |
//+------------------------------------------------------------------+
bool CheckBreakEven(const string symbol, ulong magic, CTrade &trade)
{
   bool applied = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;

      ulong  ticket     = PositionGetInteger(POSITION_TICKET);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL  = PositionGetDouble(POSITION_SL);
      double currentTP  = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // 1R = distance from entry to initial SL
      double oneR = MathAbs(entryPrice - currentSL);
      if(oneR <= 0) continue;

      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

      if(posType == POSITION_TYPE_BUY)
      {
         if(currentSL >= entryPrice) continue; // already at BE or better
         if(bid >= entryPrice + oneR)
         {
            double newSL = NormPrice(symbol, entryPrice);
            if(trade.PositionModify(ticket, newSL, currentTP))
               applied = true;
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         if(currentSL <= entryPrice && currentSL > 0) continue; // already at BE
         if(ask <= entryPrice - oneR)
         {
            double newSL = NormPrice(symbol, entryPrice);
            if(trade.PositionModify(ticket, newSL, currentTP))
               applied = true;
         }
      }
   }

   return applied;
}

//+------------------------------------------------------------------+
//| ApplyPartialClose - Close a percentage of position at a profit   |
//| level. Call once per bar. percentClose=0.5 means 50%.            |
//| atRR = risk/reward level (e.g., 1.0 = 1:1)                      |
//| Returns true if a partial close was executed.                    |
//+------------------------------------------------------------------+
bool ApplyPartialClose(const string symbol, ulong magic, CTrade &trade,
                       double percentClose, double atRR)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;

      double openPx  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl      = PositionGetDouble(POSITION_SL);
      double volume  = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double riskDist = MathAbs(openPx - sl);
      if(riskDist <= 0) continue;

      double currentPx = (posType == POSITION_TYPE_BUY) ?
                          SymbolInfoDouble(symbol, SYMBOL_BID) :
                          SymbolInfoDouble(symbol, SYMBOL_ASK);

      double profit = (posType == POSITION_TYPE_BUY) ? currentPx - openPx : openPx - currentPx;

      // Check if profit has reached the target RR level
      if(profit >= riskDist * atRR)
      {
         double closeLot = NormalizeDouble(volume * percentClose,
                           (int)MathLog10(1.0 / SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP)));
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

         if(closeLot >= minLot)
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            if(trade.PositionClosePartial(ticket, closeLot))
            {
               // Move SL to breakeven after partial close
               double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
               double beSL;
               if(posType == POSITION_TYPE_BUY)
                  beSL = NormPrice(symbol, openPx + point * 5);
               else
                  beSL = NormPrice(symbol, openPx - point * 5);

               trade.PositionModify(ticket, beSL, PositionGetDouble(POSITION_TP));
               return true;
            }
         }
      }
   }

   return false;
}

#endif // FRAMEWORK_TRADEMANAGER_MQH
