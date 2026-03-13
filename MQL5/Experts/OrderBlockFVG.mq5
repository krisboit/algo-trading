//+------------------------------------------------------------------+
//|                                             OrderBlockFVG.mq5    |
//|  Strategy 5: Order Block + Fair Value Gap (Smart Money)          |
//|  Identifies institutional OBs and FVGs on HTF, enters on LTF    |
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
input group "=== Zone Detection (HTF) ==="
input ENUM_TIMEFRAMES InpHTF      = PERIOD_H1;  // Structure Timeframe
input double InpOB_ImpulseATR     = 1.5;   // Impulse Move: ATR Multiplier
input int    InpOB_MaxAge         = 50;    // Max HTF Bars Before OB Expires
input int    InpOB_MaxZones       = 5;     // Max Active Zones

input group "=== FVG Settings ==="
input bool   InpFVG_Enabled       = true;  // Enable Fair Value Gaps
input double InpFVG_MinGapATR     = 0.3;   // Min FVG Size (ATR fraction)

input group "=== Entry Confirmation ==="
input int    InpRSI_Period        = 14;    // RSI Period
input double InpRSI_OB_Level     = 30.0;  // RSI Oversold for Buy
input double InpRSI_OS_Level     = 70.0;  // RSI Overbought for Sell
input int    InpHTF_EMA           = 50;    // HTF EMA for Trend Direction

input group "=== Exit Settings ==="
input double InpRiskReward        = 2.0;   // Risk-to-Reward Ratio
input int    InpSL_Buffer         = 10;    // SL Buffer Beyond Zone (points)
input bool   InpUsePartialClose   = true;  // Partial Close 50% at 1:1

input group "=== Risk Management ==="
input double InpRiskPercent       = 1.0;   // Risk Per Trade (%)
input ulong  InpMagicNumber       = 100005; // Magic Number

//+------------------------------------------------------------------+
//| Zone structures                                                  |
//+------------------------------------------------------------------+
enum ZONE_TYPE { ZONE_BULL, ZONE_BEAR };
enum ZONE_SOURCE { SOURCE_OB, SOURCE_FVG };

struct SZone
{
   double    high;
   double    low;
   datetime  time;
   ZONE_TYPE type;
   ZONE_SOURCE source;
   bool      fresh;
   int       age;      // HTF bars since creation
};

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CStrategyExporter exporter;
CTrade            trade;

int hRSI, hHTF_EMA, hHTF_ATR;

SZone    g_zones[];
int      g_zoneCount;
datetime lastBarTime = 0;
datetime lastHTFBarTime = 0;
bool     g_partialDone = false;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetDeviationInPoints(30);

   hRSI     = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   hHTF_EMA = iMA(_Symbol, InpHTF, InpHTF_EMA, 0, MODE_EMA, PRICE_CLOSE);
   hHTF_ATR = iATR(_Symbol, InpHTF, 14);

   if(hRSI == INVALID_HANDLE || hHTF_EMA == INVALID_HANDLE || hHTF_ATR == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return INIT_FAILED;
   }

   g_zoneCount = 0;
   ArrayResize(g_zones, 0, 20);

   exporter.Init("OrderBlockFVG", InpMagicNumber);
   exporter.AddTimeframe(PERIOD_CURRENT);
   exporter.AddTimeframe(InpHTF);

   exporter.RegisterIndicator(hRSI, StringFormat("RSI_%d", InpRSI_Period), 1);
   exporter.RegisterIndicator(hHTF_EMA, StringFormat("EMA_%d_%s", InpHTF_EMA,
                              STimeframeData::TimeframeToString(InpHTF)), 1, InpHTF);
   exporter.RegisterIndicator(hHTF_ATR, StringFormat("ATR_14_%s",
                              STimeframeData::TimeframeToString(InpHTF)), 1, InpHTF);

   Print("OrderBlockFVG initialized on ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   exporter.Export();
   IndicatorRelease(hRSI);
   IndicatorRelease(hHTF_EMA);
   IndicatorRelease(hHTF_ATR);
}

//+------------------------------------------------------------------+
//| Optimization fitness function (Framework)                        |
//+------------------------------------------------------------------+
double OnTester()
{
   double fitness = CalcFitness();

   string names[]  = {"InpHTF", "InpOB_ImpulseATR", "InpOB_MaxAge", "InpOB_MaxZones",
                       "InpFVG_Enabled", "InpFVG_MinGapATR", "InpRSI_Period",
                       "InpRSI_OB_Level", "InpRSI_OS_Level", "InpHTF_EMA",
                       "InpRiskReward", "InpSL_Buffer", "InpUsePartialClose",
                       "InpRiskPercent"};
   double values[] = {InpHTF, InpOB_ImpulseATR, InpOB_MaxAge, InpOB_MaxZones,
                      InpFVG_Enabled, InpFVG_MinGapATR, InpRSI_Period,
                      InpRSI_OB_Level, InpRSI_OS_Level, InpHTF_EMA,
                      InpRiskReward, InpSL_Buffer, InpUsePartialClose,
                      InpRiskPercent};
   TesterExportPass(names, values, fitness);

   return fitness;
}

//+------------------------------------------------------------------+
void OnTick()
{
   exporter.OnTick();

   // HTF zone detection
   datetime htfBarTime = iTime(_Symbol, InpHTF, 0);
   if(htfBarTime != lastHTFBarTime && htfBarTime != 0)
   {
      lastHTFBarTime = htfBarTime;
      DetectZones();
      AgeZones();
   }

   // Primary TF entry logic
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   // Manage partial close
   if(HasPosition(_Symbol, InpMagicNumber) && InpUsePartialClose && !g_partialDone)
   {
      CheckPartialClose();
      return;
   }

   if(HasPosition(_Symbol, InpMagicNumber)) return;

   CheckEntry();
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   exporter.OnTradeTransaction(trans, request, result);
}

//+------------------------------------------------------------------+
//| Detect Order Blocks and FVGs on HTF                              |
//+------------------------------------------------------------------+
void DetectZones()
{
   double htfATR[];
   if(CopyBuffer(hHTF_ATR, 0, 1, 1, htfATR) != 1) return;

   // --- Order Block Detection ---
   // Look at bar 1 (just closed). Check if it's the start of an impulse.
   // Impulse = bar 1 body > ATR * multiplier
   double open1  = iOpen(_Symbol, InpHTF, 1);
   double close1 = iClose(_Symbol, InpHTF, 1);
   double high1  = iHigh(_Symbol, InpHTF, 1);
   double low1   = iLow(_Symbol, InpHTF, 1);
   double body1  = MathAbs(close1 - open1);

   if(body1 > htfATR[0] * InpOB_ImpulseATR)
   {
      // This is an impulse candle. The candle before it (bar 2) is the Order Block.
      double obHigh = iHigh(_Symbol, InpHTF, 2);
      double obLow  = iLow(_Symbol, InpHTF, 2);
      datetime obTime = iTime(_Symbol, InpHTF, 2);

      SZone zone;
      zone.high = obHigh;
      zone.low  = obLow;
      zone.time = obTime;
      zone.source = SOURCE_OB;
      zone.fresh = true;
      zone.age = 0;

      if(close1 > open1) // Bullish impulse -> Bullish OB (demand)
         zone.type = ZONE_BULL;
      else               // Bearish impulse -> Bearish OB (supply)
         zone.type = ZONE_BEAR;

      AddZone(zone);
   }

   // --- Fair Value Gap Detection ---
   if(InpFVG_Enabled)
   {
      // Three candles: bar 3, bar 2, bar 1
      double high3 = iHigh(_Symbol, InpHTF, 3);
      double low3  = iLow(_Symbol, InpHTF, 3);
      double high2 = iHigh(_Symbol, InpHTF, 2);
      double low2  = iLow(_Symbol, InpHTF, 2);

      // Bullish FVG: bar 3 high < bar 1 low (gap up)
      if(high3 < low1)
      {
         double gapSize = low1 - high3;
         if(gapSize >= htfATR[0] * InpFVG_MinGapATR)
         {
            SZone zone;
            zone.high = low1;     // top of gap
            zone.low  = high3;    // bottom of gap
            zone.time = iTime(_Symbol, InpHTF, 2); // middle candle time
            zone.type = ZONE_BULL; // bullish FVG = demand (price comes back down)
            zone.source = SOURCE_FVG;
            zone.fresh = true;
            zone.age = 0;
            AddZone(zone);
         }
      }

      // Bearish FVG: bar 3 low > bar 1 high (gap down)
      if(low3 > high1)
      {
         double gapSize = low3 - high1;
         if(gapSize >= htfATR[0] * InpFVG_MinGapATR)
         {
            SZone zone;
            zone.high = low3;     // top of gap
            zone.low  = high1;    // bottom of gap
            zone.time = iTime(_Symbol, InpHTF, 2);
            zone.type = ZONE_BEAR; // bearish FVG = supply (price comes back up)
            zone.source = SOURCE_FVG;
            zone.fresh = true;
            zone.age = 0;
            AddZone(zone);
         }
      }
   }
}

//+------------------------------------------------------------------+
void AddZone(SZone &zone)
{
   // Remove oldest if at max
   while(g_zoneCount >= InpOB_MaxZones)
   {
      // Remove first (oldest)
      for(int i = 0; i < g_zoneCount - 1; i++)
         g_zones[i] = g_zones[i + 1];
      g_zoneCount--;
   }

   g_zoneCount++;
   ArrayResize(g_zones, g_zoneCount, 20);
   g_zones[g_zoneCount - 1] = zone;
}

//+------------------------------------------------------------------+
void AgeZones()
{
   for(int i = g_zoneCount - 1; i >= 0; i--)
   {
      g_zones[i].age++;

      // Mark as stale
      if(g_zones[i].age > InpOB_MaxAge)
      {
         // Remove it
         for(int j = i; j < g_zoneCount - 1; j++)
            g_zones[j] = g_zones[j + 1];
         g_zoneCount--;
         ArrayResize(g_zones, g_zoneCount, 20);
      }
   }

   // Check if price has entered any zone (mark as tested/not fresh)
   double currentPrice = iClose(_Symbol, InpHTF, 1);
   for(int i = 0; i < g_zoneCount; i++)
   {
      if(g_zones[i].fresh && currentPrice >= g_zones[i].low && currentPrice <= g_zones[i].high)
         g_zones[i].fresh = false; // zone has been tested
   }
}

//+------------------------------------------------------------------+
void CheckEntry()
{
   if(g_zoneCount == 0) return;

   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // RSI confirmation
   double rsi[];
   if(CopyBuffer(hRSI, 0, 1, 1, rsi) != 1) return;

   // HTF trend
   double htfEMA[];
   if(CopyBuffer(hHTF_EMA, 0, 1, 1, htfEMA) != 1) return;

   for(int i = g_zoneCount - 1; i >= 0; i--)
   {
      if(!g_zones[i].fresh) continue;

      // Check if price is in this zone
      bool inZone = (close >= g_zones[i].low && close <= g_zones[i].high);
      if(!inZone) continue;

      double buffer = InpSL_Buffer * point;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Bullish zone (demand) -> BUY
      if(g_zones[i].type == ZONE_BULL && rsi[0] < InpRSI_OB_Level && close > htfEMA[0])
      {
         double sl = NormPrice(_Symbol, g_zones[i].low - buffer);
         double slDist = ask - sl;
         double tp = NormPrice(_Symbol, ask + slDist * InpRiskReward);
         double lots = CalcLotSize(_Symbol, InpRiskPercent, slDist / point);

         if(trade.Buy(lots, _Symbol, ask, sl, tp, "OB/FVG BUY"))
         {
            g_zones[i].fresh = false;
            g_partialDone = false;
            Print("BUY at ", (g_zones[i].source == SOURCE_OB ? "OB" : "FVG"),
                  " zone [", DoubleToString(g_zones[i].low, _Digits),
                  "-", DoubleToString(g_zones[i].high, _Digits), "]",
                  " RSI=", DoubleToString(rsi[0], 1));
         }
      }
      // Bearish zone (supply) -> SELL
      else if(g_zones[i].type == ZONE_BEAR && rsi[0] > InpRSI_OS_Level && close < htfEMA[0])
      {
         double sl = NormPrice(_Symbol, g_zones[i].high + buffer);
         double slDist = sl - bid;
         double tp = NormPrice(_Symbol, bid - slDist * InpRiskReward);
         double lots = CalcLotSize(_Symbol, InpRiskPercent, slDist / point);

         if(trade.Sell(lots, _Symbol, bid, sl, tp, "OB/FVG SELL"))
         {
            g_zones[i].fresh = false;
            g_partialDone = false;
            Print("SELL at ", (g_zones[i].source == SOURCE_OB ? "OB" : "FVG"),
                  " zone [", DoubleToString(g_zones[i].low, _Digits),
                  "-", DoubleToString(g_zones[i].high, _Digits), "]",
                  " RSI=", DoubleToString(rsi[0], 1));
         }
      }
   }
}

//+------------------------------------------------------------------+
void CheckPartialClose()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      double openPx = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double riskDist = MathAbs(openPx - sl);
      double currentPx = (posType == POSITION_TYPE_BUY) ?
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double profit = (posType == POSITION_TYPE_BUY) ? currentPx - openPx : openPx - currentPx;

      // Close 50% at 1:1 RR
      if(profit >= riskDist)
      {
         double halfLot = NormalizeDouble(volume * 0.5,
                          (int)MathLog10(1.0 / SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)));
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(halfLot >= minLot)
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            trade.PositionClosePartial(ticket, halfLot);
            g_partialDone = true;

            // Move SL to breakeven
            double beSL;
            if(posType == POSITION_TYPE_BUY)
               beSL = NormPrice(_Symbol, openPx + SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 5);
            else
               beSL = NormPrice(_Symbol, openPx - SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 5);

            trade.PositionModify(ticket, beSL, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
