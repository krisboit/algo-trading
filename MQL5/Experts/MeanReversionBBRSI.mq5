//+------------------------------------------------------------------+
//|                                         MeanReversionBBRSI.mq5   |
//|  Strategy 2: Mean Reversion (BB + RSI + ADX trend filter)        |
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
input group "=== Bollinger Bands ==="
input int    InpBB_Period       = 20;      // BB Period
input double InpBB_Deviation    = 2.0;     // BB Deviation

input group "=== RSI ==="
input int    InpRSI_Period      = 14;      // RSI Period
input double InpRSI_BuyLevel   = 30.0;    // RSI Buy Level (oversold)
input double InpRSI_SellLevel  = 70.0;    // RSI Sell Level (overbought)

input group "=== ADX Trend Filter ==="
input int    InpADX_Period      = 14;      // ADX Period
input double InpADX_Threshold   = 25.0;   // Max ADX (range filter)

input group "=== Exit Settings ==="
input int    InpExitMode        = 2;       // Exit Mode (1=Fixed, 2=BB Middle, 3=ATR)
input int    InpFixedSL         = 50;      // Fixed SL (points, mode 1)
input int    InpFixedTP         = 50;      // Fixed TP (points, mode 1)
input int    InpATR_Period      = 14;      // ATR Period (mode 3)
input double InpATR_SL_Mult     = 1.5;    // ATR SL Multiplier (mode 3)
input double InpATR_TP_Mult     = 1.0;    // ATR TP Multiplier (mode 3)
input int    InpMaxBarsHold     = 20;      // Max Bars to Hold

input group "=== Risk Management ==="
input double InpRiskPercent     = 1.0;     // Risk Per Trade (%)
input ulong  InpMagicNumber     = 100002;  // Magic Number

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CStrategyExporter exporter;
CTrade            trade;

int hBB, hRSI, hADX, hATR;
datetime lastBarTime = 0;
int      barsInTrade = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetDeviationInPoints(30);

   hBB  = iBands(_Symbol, PERIOD_CURRENT, InpBB_Period, 0, InpBB_Deviation, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   hADX = iADX(_Symbol, PERIOD_CURRENT, InpADX_Period);
   hATR = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);

   if(hBB == INVALID_HANDLE || hRSI == INVALID_HANDLE ||
      hADX == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return INIT_FAILED;
   }

   exporter.Init("MeanReversionBBRSI", InpMagicNumber);
   exporter.AddTimeframe(PERIOD_CURRENT);

   exporter.RegisterIndicator(hBB,  StringFormat("BB_%d_%.1f", InpBB_Period, InpBB_Deviation), 3);
   exporter.RegisterIndicator(hRSI, StringFormat("RSI_%d", InpRSI_Period), 1);
   exporter.RegisterIndicator(hADX, StringFormat("ADX_%d", InpADX_Period), 3);
   exporter.RegisterIndicator(hATR, StringFormat("ATR_%d", InpATR_Period), 1);

   Print("MeanReversionBBRSI initialized on ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   exporter.Export();
   IndicatorRelease(hBB);
   IndicatorRelease(hRSI);
   IndicatorRelease(hADX);
   IndicatorRelease(hATR);
}

//+------------------------------------------------------------------+
//| Optimization fitness function (Framework)                        |
//+------------------------------------------------------------------+
double OnTester()
{
   double fitness = CalcFitness();

   string names[]  = {"InpBB_Period", "InpBB_Deviation", "InpRSI_Period",
                       "InpRSI_BuyLevel", "InpRSI_SellLevel", "InpADX_Period",
                       "InpADX_Threshold", "InpExitMode", "InpFixedSL", "InpFixedTP",
                       "InpATR_Period", "InpATR_SL_Mult", "InpATR_TP_Mult",
                       "InpMaxBarsHold", "InpRiskPercent"};
   double values[] = {InpBB_Period, InpBB_Deviation, InpRSI_Period,
                      InpRSI_BuyLevel, InpRSI_SellLevel, InpADX_Period,
                      InpADX_Threshold, InpExitMode, InpFixedSL, InpFixedTP,
                      InpATR_Period, InpATR_SL_Mult, InpATR_TP_Mult,
                      InpMaxBarsHold, InpRiskPercent};
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

   // Track bars in trade for max hold exit
   if(HasPosition(_Symbol, InpMagicNumber)) barsInTrade++;
   else barsInTrade = 0;

   // Max hold time exit
   if(HasPosition(_Symbol, InpMagicNumber) && barsInTrade >= InpMaxBarsHold)
   {
      CloseAllPositions(_Symbol, InpMagicNumber, trade);
      return;
   }

   // BB middle exit (mode 2)
   if(HasPosition(_Symbol, InpMagicNumber) && InpExitMode == 2)
   {
      CheckBBMiddleExit();
   }

   // Don't enter if already in position
   if(HasPosition(_Symbol, InpMagicNumber)) return;

   CheckForSignal();
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   exporter.OnTradeTransaction(trans, request, result);
}

//+------------------------------------------------------------------+
void CheckForSignal()
{
   // Get indicator values (bar 1 = completed bar)
   double bbMiddle[], bbUpper[], bbLower[], rsi[], adx[], atr[];
   if(CopyBuffer(hBB,  0, 1, 1, bbMiddle) != 1) return;
   if(CopyBuffer(hBB,  1, 1, 1, bbUpper)  != 1) return;
   if(CopyBuffer(hBB,  2, 1, 1, bbLower)  != 1) return;
   if(CopyBuffer(hRSI, 0, 1, 1, rsi)      != 1) return;
   if(CopyBuffer(hADX, 0, 1, 1, adx)      != 1) return;
   if(CopyBuffer(hATR, 0, 1, 1, atr)      != 1) return;

   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ADX filter — only trade in range
   if(adx[0] > InpADX_Threshold) return;

   double sl = 0, tp = 0, slDist = 0;

   // BUY: Price at/below lower BB + RSI oversold
   if(close <= bbLower[0] && rsi[0] < InpRSI_BuyLevel)
   {
      CalculateExitLevels(true, ask, bbMiddle[0], atr[0], point, sl, tp, slDist);
      double lots = CalcLotSize(_Symbol, InpRiskPercent, slDist / point);

      if(trade.Buy(lots, _Symbol, ask, NormPrice(_Symbol, sl), NormPrice(_Symbol, tp), "MR BUY"))
      {
         barsInTrade = 0;
         Print("BUY: RSI=", DoubleToString(rsi[0],1), " ADX=", DoubleToString(adx[0],1),
               " Close=", DoubleToString(close, _Digits));
      }
   }
   // SELL: Price at/above upper BB + RSI overbought
   else if(close >= bbUpper[0] && rsi[0] > InpRSI_SellLevel)
   {
      CalculateExitLevels(false, bid, bbMiddle[0], atr[0], point, sl, tp, slDist);
      double lots = CalcLotSize(_Symbol, InpRiskPercent, slDist / point);

      if(trade.Sell(lots, _Symbol, bid, NormPrice(_Symbol, sl), NormPrice(_Symbol, tp), "MR SELL"))
      {
         barsInTrade = 0;
         Print("SELL: RSI=", DoubleToString(rsi[0],1), " ADX=", DoubleToString(adx[0],1),
               " Close=", DoubleToString(close, _Digits));
      }
   }
}

//+------------------------------------------------------------------+
void CalculateExitLevels(bool isBuy, double entry, double bbMid, double atrVal,
                         double point, double &sl, double &tp, double &slDist)
{
   switch(InpExitMode)
   {
      case 1: // Fixed
         if(isBuy)
         {
            sl = entry - InpFixedSL * point;
            tp = entry + InpFixedTP * point;
         }
         else
         {
            sl = entry + InpFixedSL * point;
            tp = entry - InpFixedTP * point;
         }
         slDist = InpFixedSL * point;
         break;

      case 2: // BB Middle
         if(isBuy)
         {
            sl = entry - atrVal * InpATR_SL_Mult;
            tp = bbMid;
            if(tp <= entry) tp = entry + atrVal; // fallback
         }
         else
         {
            sl = entry + atrVal * InpATR_SL_Mult;
            tp = bbMid;
            if(tp >= entry) tp = entry - atrVal; // fallback
         }
         slDist = MathAbs(entry - sl);
         break;

      case 3: // ATR
         if(isBuy)
         {
            sl = entry - atrVal * InpATR_SL_Mult;
            tp = entry + atrVal * InpATR_TP_Mult;
         }
         else
         {
            sl = entry + atrVal * InpATR_SL_Mult;
            tp = entry - atrVal * InpATR_TP_Mult;
         }
         slDist = atrVal * InpATR_SL_Mult;
         break;

      default:
         sl = isBuy ? entry - atrVal * 1.5 : entry + atrVal * 1.5;
         tp = isBuy ? entry + atrVal       : entry - atrVal;
         slDist = atrVal * 1.5;
         break;
   }
}

//+------------------------------------------------------------------+
void CheckBBMiddleExit()
{
   double bbMiddle[];
   if(CopyBuffer(hBB, 0, 1, 1, bbMiddle) != 1) return;

   double close = iClose(_Symbol, PERIOD_CURRENT, 1);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Close if price has crossed BB middle
      if(posType == POSITION_TYPE_BUY && close >= bbMiddle[0])
      {
         trade.PositionClose(PositionGetInteger(POSITION_TICKET));
      }
      else if(posType == POSITION_TYPE_SELL && close <= bbMiddle[0])
      {
         trade.PositionClose(PositionGetInteger(POSITION_TICKET));
      }
   }
}

//+------------------------------------------------------------------+
