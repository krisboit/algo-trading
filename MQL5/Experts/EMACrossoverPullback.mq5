//+------------------------------------------------------------------+
//|                                       EMACrossoverPullback.mq5   |
//|  Strategy 3: EMA Crossover with Pullback Entry + ATR Trail       |
//+------------------------------------------------------------------+
#property copyright "Strategy Exporter"
#property link      "https://github.com/algo-trading"
#property version   "1.00"

#include <StrategyExporter/StrategyExporter.mqh>
#include <StrategyExporter/RiskManager.mqh>
#include <Framework/StrategyBase.mqh>
#include <Framework/TradeManager.mqh>
#include <Framework/TesterExport.mqh>
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "=== EMA Settings ==="
input int    InpFastEMA         = 8;       // Fast EMA Period
input int    InpSlowEMA         = 21;      // Slow EMA Period

input group "=== Higher Timeframe Filter ==="
input ENUM_TIMEFRAMES InpHTF    = PERIOD_H1; // Higher Timeframe
input int    InpHTF_EMA         = 50;      // HTF Trend EMA Period

input group "=== ATR / Exit Settings ==="
input int    InpATR_Period      = 14;      // ATR Period
input double InpATR_SL_Mult     = 1.5;    // ATR SL Multiplier
input double InpATR_TP_Mult     = 3.0;    // ATR TP Multiplier (0=disabled)
input double InpTrailATR_Mult   = 1.0;    // ATR Trailing Stop Multiplier

input group "=== Pullback Settings ==="
input int    InpPullbackMode    = 1;       // Pullback Mode (1=Touch, 2=Cross EMA zone)

input group "=== Risk Management ==="
input double InpRiskPercent     = 1.0;     // Risk Per Trade (%)
input ulong  InpMagicNumber     = 100003;  // Magic Number

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CStrategyExporter exporter;
CTrade            trade;

int hFastEMA, hSlowEMA, hHTF_EMA, hATR;

// State tracking
int      g_trendDir;        // 1=bullish, -1=bearish, 0=none
bool     g_pullbackStarted; // price entered EMA zone
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetDeviationInPoints(30);

   hFastEMA = iMA(_Symbol, PERIOD_CURRENT, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA = iMA(_Symbol, PERIOD_CURRENT, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hHTF_EMA = iMA(_Symbol, InpHTF, InpHTF_EMA, 0, MODE_EMA, PRICE_CLOSE);
   hATR     = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);

   if(hFastEMA == INVALID_HANDLE || hSlowEMA == INVALID_HANDLE ||
      hHTF_EMA == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return INIT_FAILED;
   }

   g_trendDir = 0;
   g_pullbackStarted = false;

   exporter.Init("EMACrossoverPullback", InpMagicNumber);
   exporter.AddTimeframe(PERIOD_CURRENT);
   exporter.AddTimeframe(InpHTF);

   exporter.RegisterIndicator(hFastEMA, StringFormat("EMA_%d", InpFastEMA), 1);
   exporter.RegisterIndicator(hSlowEMA, StringFormat("EMA_%d", InpSlowEMA), 1);
   exporter.RegisterIndicator(hHTF_EMA, StringFormat("EMA_%d_%s", InpHTF_EMA,
                              STimeframeData::TimeframeToString(InpHTF)), 1, InpHTF);
   exporter.RegisterIndicator(hATR, StringFormat("ATR_%d", InpATR_Period), 1);

   Print("EMACrossoverPullback initialized on ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   exporter.Export();
   IndicatorRelease(hFastEMA);
   IndicatorRelease(hSlowEMA);
   IndicatorRelease(hHTF_EMA);
   IndicatorRelease(hATR);
}

//+------------------------------------------------------------------+
//| Optimization fitness function (Framework)                        |
//+------------------------------------------------------------------+
double OnTester()
{
   double fitness = CalcFitness();

   string names[]  = {"InpFastEMA", "InpSlowEMA", "InpHTF", "InpHTF_EMA",
                       "InpATR_Period", "InpATR_SL_Mult", "InpATR_TP_Mult",
                       "InpTrailATR_Mult", "InpPullbackMode", "InpRiskPercent"};
   double values[] = {InpFastEMA, InpSlowEMA, InpHTF, InpHTF_EMA,
                      InpATR_Period, InpATR_SL_Mult, InpATR_TP_Mult,
                      InpTrailATR_Mult, InpPullbackMode, InpRiskPercent};
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

   // Manage trailing stop
   if(HasPosition(_Symbol, InpMagicNumber)) ManageTrailingStopATR(_Symbol, InpMagicNumber, trade, hATR, InpTrailATR_Mult);

   // Get EMA values
   double fastEMA[], slowEMA[];
   if(CopyBuffer(hFastEMA, 0, 1, 2, fastEMA) != 2) return;
   if(CopyBuffer(hSlowEMA, 0, 1, 2, slowEMA) != 2) return;

   // Detect crossover (trend change)
   // fastEMA[0] = bar 2 (older), fastEMA[1] = bar 1 (newer) — CopyBuffer returns chronological
   if(fastEMA[0] <= slowEMA[0] && fastEMA[1] > slowEMA[1])
   {
      g_trendDir = 1; // Bullish crossover
      g_pullbackStarted = false;
   }
   else if(fastEMA[0] >= slowEMA[0] && fastEMA[1] < slowEMA[1])
   {
      g_trendDir = -1; // Bearish crossover
      g_pullbackStarted = false;
   }

   // Already in position — check for opposite crossover exit
   if(HasPosition(_Symbol, InpMagicNumber))
   {
      CheckCrossoverExit();
      return;
   }

   // Check pullback entry
   if(g_trendDir != 0) CheckPullbackEntry(fastEMA[1], slowEMA[1]);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   exporter.OnTradeTransaction(trans, request, result);
}

//+------------------------------------------------------------------+
void CheckPullbackEntry(double fastEma, double slowEma)
{
   double close  = iClose(_Symbol, PERIOD_CURRENT, 1);
   double low    = iLow(_Symbol, PERIOD_CURRENT, 1);
   double high   = iHigh(_Symbol, PERIOD_CURRENT, 1);

   double htfEMA[];
   if(CopyBuffer(hHTF_EMA, 0, 1, 1, htfEMA) != 1) return;

   double atr[];
   if(CopyBuffer(hATR, 0, 1, 1, atr) != 1) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // BULLISH: Trend is up, look for pullback to fast EMA
   if(g_trendDir == 1)
   {
      // HTF filter: price must be above HTF EMA
      if(close < htfEMA[0]) return;

      // Check pullback
      bool touchedEMA = false;
      if(InpPullbackMode == 1)
         touchedEMA = (low <= fastEma); // Price touched fast EMA
      else
         touchedEMA = (close < fastEma && close > slowEma); // Price in EMA zone

      if(touchedEMA) g_pullbackStarted = true;

      // Entry: Pullback happened and price closed back above fast EMA
      if(g_pullbackStarted && close > fastEma)
      {
         g_pullbackStarted = false;

         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl  = NormPrice(_Symbol, ask - atr[0] * InpATR_SL_Mult);
         double tp  = InpATR_TP_Mult > 0 ? NormPrice(_Symbol, ask + atr[0] * InpATR_TP_Mult) : 0;
         double slDist = atr[0] * InpATR_SL_Mult;
         double lots = CalcLotSize(_Symbol, InpRiskPercent, slDist / point);

         if(trade.Buy(lots, _Symbol, ask, sl, tp, "EMA PB BUY"))
            Print("BUY Pullback: Fast=", DoubleToString(fastEma, _Digits),
                  " Slow=", DoubleToString(slowEma, _Digits));
      }
   }
   // BEARISH: Trend is down, look for pullback to fast EMA
   else if(g_trendDir == -1)
   {
      if(close > htfEMA[0]) return;

      bool touchedEMA = false;
      if(InpPullbackMode == 1)
         touchedEMA = (high >= fastEma);
      else
         touchedEMA = (close > fastEma && close < slowEma);

      if(touchedEMA) g_pullbackStarted = true;

      if(g_pullbackStarted && close < fastEma)
      {
         g_pullbackStarted = false;

         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl  = NormPrice(_Symbol, bid + atr[0] * InpATR_SL_Mult);
         double tp  = InpATR_TP_Mult > 0 ? NormPrice(_Symbol, bid - atr[0] * InpATR_TP_Mult) : 0;
         double slDist = atr[0] * InpATR_SL_Mult;
         double lots = CalcLotSize(_Symbol, InpRiskPercent, slDist / point);

         if(trade.Sell(lots, _Symbol, bid, sl, tp, "EMA PB SELL"))
            Print("SELL Pullback: Fast=", DoubleToString(fastEma, _Digits),
                  " Slow=", DoubleToString(slowEma, _Digits));
      }
   }
}

//+------------------------------------------------------------------+
void CheckCrossoverExit()
{
   // Exit on opposite crossover
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(posType == POSITION_TYPE_BUY && g_trendDir == -1)
         trade.PositionClose(PositionGetInteger(POSITION_TICKET));
      else if(posType == POSITION_TYPE_SELL && g_trendDir == 1)
         trade.PositionClose(PositionGetInteger(POSITION_TICKET));
   }
}

//+------------------------------------------------------------------+
