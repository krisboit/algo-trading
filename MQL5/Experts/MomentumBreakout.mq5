//+------------------------------------------------------------------+
//|                                          MomentumBreakout.mq5    |
//|  Strategy 4: Donchian Breakout + MACD Momentum + ATR Trail       |
//+------------------------------------------------------------------+
#property copyright "Strategy Exporter"
#property link      "https://github.com/algo-trading"
#property version   "1.00"

#include <StrategyExporter/StrategyExporter.mqh>
#include <StrategyExporter/RiskManager.mqh>
#include <Framework/StrategyBase.mqh>
#include <Framework/TesterExport.mqh>
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Donchian Channel ==="
input int    InpDonchian_Period  = 20;     // Donchian Period (breakout lookback)

input group "=== MACD ==="
input int    InpMACD_Fast        = 12;     // MACD Fast
input int    InpMACD_Slow        = 26;     // MACD Slow
input int    InpMACD_Signal      = 9;      // MACD Signal

input group "=== ATR / Exits ==="
input int    InpATR_Period       = 14;     // ATR Period
input double InpATR_SL_Mult      = 2.0;   // ATR SL Multiplier
input double InpATR_TP_Mult      = 0.0;   // ATR TP Multiplier (0=trail only)
input double InpATR_Trail_Mult   = 1.5;   // ATR Trailing Distance
input double InpATR_Activation   = 1.0;   // ATR Distance to Activate Trail
input double InpBreakevenATR     = 1.0;   // ATR Profit to Move to BE (0=off)
input int    InpMomentumFadeBars = 3;      // Bars of Fading Momentum to Exit

input group "=== Risk Management ==="
input double InpRiskPercent      = 1.0;    // Risk Per Trade (%)
input ulong  InpMagicNumber      = 100004; // Magic Number

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CStrategyExporter exporter;
CTrade            trade;

int hMACD, hATR;
datetime lastBarTime = 0;
bool     g_breakEvenDone = false;
int      g_fadingBars = 0;     // consecutive bars of fading MACD histogram

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetDeviationInPoints(30);

   hMACD = iMACD(_Symbol, PERIOD_CURRENT, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);
   hATR  = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);

   if(hMACD == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return INIT_FAILED;
   }

   exporter.Init("MomentumBreakout", InpMagicNumber);
   exporter.AddTimeframe(PERIOD_CURRENT);

   exporter.RegisterIndicator(hMACD, StringFormat("MACD_%d_%d_%d", InpMACD_Fast, InpMACD_Slow, InpMACD_Signal), 3);
   exporter.RegisterIndicator(hATR, StringFormat("ATR_%d", InpATR_Period), 1);

   Print("MomentumBreakout initialized on ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   exporter.Export();
   IndicatorRelease(hMACD);
   IndicatorRelease(hATR);
}

//+------------------------------------------------------------------+
//| Optimization fitness function (Framework)                        |
//+------------------------------------------------------------------+
double OnTester()
{
   double fitness = CalcFitness();

   string names[]  = {"InpDonchian_Period", "InpMACD_Fast", "InpMACD_Slow", "InpMACD_Signal",
                       "InpATR_Period", "InpATR_SL_Mult", "InpATR_TP_Mult",
                       "InpATR_Trail_Mult", "InpATR_Activation", "InpBreakevenATR",
                       "InpMomentumFadeBars", "InpRiskPercent"};
   double values[] = {InpDonchian_Period, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal,
                      InpATR_Period, InpATR_SL_Mult, InpATR_TP_Mult,
                      InpATR_Trail_Mult, InpATR_Activation, InpBreakevenATR,
                      InpMomentumFadeBars, InpRiskPercent};
   TesterExportPass(names, values, fitness);

   return fitness;
}

//+------------------------------------------------------------------+
void OnTick()
{
   exporter.OnTick();

   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   if(HasPosition(_Symbol, InpMagicNumber))
   {
      ManagePosition();
      return;
   }

   CheckForBreakout();
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   exporter.OnTradeTransaction(trans, request, result);
}

//+------------------------------------------------------------------+
//| Calculate Donchian Channel (no built-in indicator)               |
//+------------------------------------------------------------------+
void GetDonchianChannel(double &upper, double &lower)
{
   int highestBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpDonchian_Period, 2); // skip bar 0,1
   int lowestBar  = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpDonchian_Period, 2);

   upper = iHigh(_Symbol, PERIOD_CURRENT, highestBar);
   lower = iLow(_Symbol, PERIOD_CURRENT, lowestBar);
}

//+------------------------------------------------------------------+
void CheckForBreakout()
{
   double donchianUpper, donchianLower;
   GetDonchianChannel(donchianUpper, donchianLower);

   double close = iClose(_Symbol, PERIOD_CURRENT, 1);

   // MACD histogram
   double macdMain[], macdSignal[];
   if(CopyBuffer(hMACD, 0, 1, 2, macdMain) != 2) return;
   if(CopyBuffer(hMACD, 1, 1, 2, macdSignal) != 2) return;

   double hist1 = macdMain[1] - macdSignal[1]; // bar 1 (most recent)
   double hist0 = macdMain[0] - macdSignal[0]; // bar 2 (older)

   // ATR
   double atr[];
   if(CopyBuffer(hATR, 0, 1, 1, atr) != 1) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // BUY: Close above Donchian upper + MACD histogram positive & increasing
   if(close > donchianUpper && hist1 > 0 && hist1 > hist0)
   {
      double sl = NormPrice(_Symbol, ask - atr[0] * InpATR_SL_Mult);
      double tp = InpATR_TP_Mult > 0 ? NormPrice(_Symbol, ask + atr[0] * InpATR_TP_Mult) : 0;
      double slDist = atr[0] * InpATR_SL_Mult;
      double lots = CalcLotSize(_Symbol, InpRiskPercent, slDist / point);

      if(trade.Buy(lots, _Symbol, ask, sl, tp, "MB BUY"))
      {
         g_breakEvenDone = false;
         g_fadingBars = 0;
         Print("BUY Breakout: Donchian=", DoubleToString(donchianUpper, _Digits),
               " MACD=", DoubleToString(hist1, 6));
      }
   }
   // SELL: Close below Donchian lower + MACD histogram negative & decreasing
   else if(close < donchianLower && hist1 < 0 && hist1 < hist0)
   {
      double sl = NormPrice(_Symbol, bid + atr[0] * InpATR_SL_Mult);
      double tp = InpATR_TP_Mult > 0 ? NormPrice(_Symbol, bid - atr[0] * InpATR_TP_Mult) : 0;
      double slDist = atr[0] * InpATR_SL_Mult;
      double lots = CalcLotSize(_Symbol, InpRiskPercent, slDist / point);

      if(trade.Sell(lots, _Symbol, bid, sl, tp, "MB SELL"))
      {
         g_breakEvenDone = false;
         g_fadingBars = 0;
         Print("SELL Breakout: Donchian=", DoubleToString(donchianLower, _Digits),
               " MACD=", DoubleToString(hist1, 6));
      }
   }
}

//+------------------------------------------------------------------+
void ManagePosition()
{
   double atr[];
   if(CopyBuffer(hATR, 0, 1, 1, atr) != 1) return;

   // MACD momentum fade check
   double macdMain[], macdSignal[];
   if(CopyBuffer(hMACD, 0, 1, 2, macdMain) != 2) return;
   if(CopyBuffer(hMACD, 1, 1, 2, macdSignal) != 2) return;
   double hist1 = macdMain[1] - macdSignal[1];
   double hist0 = macdMain[0] - macdSignal[0];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ulong  ticket  = PositionGetInteger(POSITION_TICKET);
      double openPx  = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double tp      = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double currentPx = (posType == POSITION_TYPE_BUY) ?
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double profit = (posType == POSITION_TYPE_BUY) ? currentPx - openPx : openPx - currentPx;

      // Breakeven move
      if(!g_breakEvenDone && InpBreakevenATR > 0 && profit >= atr[0] * InpBreakevenATR)
      {
         double beSL;
         if(posType == POSITION_TYPE_BUY)
            beSL = NormPrice(_Symbol, openPx + SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 5);
         else
            beSL = NormPrice(_Symbol, openPx - SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 5);

         trade.PositionModify(ticket, beSL, tp);
         g_breakEvenDone = true;
         currentSL = beSL;
      }

      // Trailing stop (activate after ATR_Activation profit)
      if(profit >= atr[0] * InpATR_Activation)
      {
         double trailDist = atr[0] * InpATR_Trail_Mult;
         if(posType == POSITION_TYPE_BUY)
         {
            double newSL = NormPrice(_Symbol, currentPx - trailDist);
            if(newSL > currentSL)
               trade.PositionModify(ticket, newSL, tp);
         }
         else
         {
            double newSL = NormPrice(_Symbol, currentPx + trailDist);
            if(newSL < currentSL)
               trade.PositionModify(ticket, newSL, tp);
         }
      }

      // Momentum fade exit
      bool fading = false;
      if(posType == POSITION_TYPE_BUY)
         fading = (hist1 < hist0); // histogram decreasing = momentum fading for longs
      else
         fading = (hist1 > hist0); // histogram increasing = momentum fading for shorts

      if(fading)
         g_fadingBars++;
      else
         g_fadingBars = 0;

      if(g_fadingBars >= InpMomentumFadeBars)
      {
         trade.PositionClose(ticket);
         g_fadingBars = 0;
      }
   }
}

//+------------------------------------------------------------------+
