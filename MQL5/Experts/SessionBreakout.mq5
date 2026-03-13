//+------------------------------------------------------------------+
//|                                             SessionBreakout.mq5  |
//|  Strategy 1: Asian Session Range Breakout                        |
//|  Trades breakout of Asian range during London/NY kill zones      |
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
input group "=== Session Settings (GMT Hours) ==="
input int    InpAsianStart      = 0;       // Asian Session Start Hour
input int    InpAsianEnd        = 8;       // Asian Session End Hour
input int    InpLondonStart     = 8;       // London Kill Zone Start
input int    InpLondonEnd       = 11;      // London Kill Zone End
input int    InpNYStart         = 13;      // NY Kill Zone Start
input int    InpNYEnd           = 16;      // NY Kill Zone End
input int    InpSessionClose    = 21;      // Force Close Hour

input group "=== Trade Settings ==="
input int    InpBreakoutBuffer  = 5;       // Breakout Buffer (points)
input double InpRiskReward      = 1.5;     // Risk-to-Reward Ratio
input int    InpMinRangePoints  = 50;      // Min Asian Range (points)
input int    InpMaxRangePoints  = 500;     // Max Asian Range (points)
input int    InpMaxTradesPerDay = 2;       // Max Trades Per Day

input group "=== Risk Management ==="
input double InpRiskPercent     = 1.0;     // Risk Per Trade (%)
input ulong  InpMagicNumber     = 100001;  // Magic Number

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CStrategyExporter exporter;
CTrade            trade;

// Session tracking
double   g_asianHigh;
double   g_asianLow;
bool     g_rangeReady;
datetime g_lastRangeDay;
int      g_tradesToday;
datetime g_lastTradeDay;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetDeviationInPoints(30);

   g_asianHigh = 0;
   g_asianLow  = 0;
   g_rangeReady = false;
   g_lastRangeDay = 0;
   g_tradesToday = 0;
   g_lastTradeDay = 0;

   // Initialize exporter
   exporter.Init("SessionBreakout", InpMagicNumber);
   exporter.AddTimeframe(PERIOD_CURRENT);

   Print("SessionBreakout initialized: ", _Symbol, " ", EnumToString((ENUM_TIMEFRAMES)_Period));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   exporter.Export();
}

//+------------------------------------------------------------------+
//| Optimization fitness function (Framework)                        |
//+------------------------------------------------------------------+
double OnTester()
{
   double fitness = CalcFitness();

   string names[]  = {"InpAsianStart", "InpAsianEnd", "InpLondonStart", "InpLondonEnd",
                       "InpNYStart", "InpNYEnd", "InpSessionClose", "InpBreakoutBuffer",
                       "InpRiskReward", "InpMinRangePoints", "InpMaxRangePoints",
                       "InpMaxTradesPerDay", "InpRiskPercent"};
   double values[] = {InpAsianStart, InpAsianEnd, InpLondonStart, InpLondonEnd,
                      InpNYStart, InpNYEnd, InpSessionClose, InpBreakoutBuffer,
                      InpRiskReward, InpMinRangePoints, InpMaxRangePoints,
                      InpMaxTradesPerDay, InpRiskPercent};
   TesterExportPass(names, values, fitness);

   return fitness;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   exporter.OnTick();

   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;

   // Reset daily counter
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today != g_lastTradeDay)
   {
      g_tradesToday = 0;
      g_lastTradeDay = today;
   }

   // Phase 1: Build Asian range
   if(hour >= InpAsianStart && hour < InpAsianEnd)
   {
      BuildAsianRange(today);
      return;
   }

   // Phase 2: Mark range as ready at Asian close
   if(!g_rangeReady && g_lastRangeDay == today && g_asianHigh > 0 && g_asianLow > 0)
   {
      g_rangeReady = true;
   }

   // Phase 3: Force close at session end
   if(hour >= InpSessionClose)
   {
      CloseAllPositions(_Symbol, InpMagicNumber, trade);
      return;
   }

   // Phase 4: Check for breakout during kill zones
   bool inKillZone = (hour >= InpLondonStart && hour < InpLondonEnd) ||
                     (hour >= InpNYStart && hour < InpNYEnd);

   if(inKillZone && g_rangeReady && g_lastRangeDay == today)
   {
      CheckBreakout();
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   exporter.OnTradeTransaction(trans, request, result);
}

//+------------------------------------------------------------------+
//| Build Asian session range                                        |
//+------------------------------------------------------------------+
void BuildAsianRange(datetime today)
{
   if(g_lastRangeDay != today)
   {
      // New day — reset range
      g_asianHigh = 0;
      g_asianLow  = DBL_MAX;
      g_lastRangeDay = today;
      g_rangeReady = false;
   }

   double high = iHigh(_Symbol, PERIOD_CURRENT, 0);
   double low  = iLow(_Symbol, PERIOD_CURRENT, 0);

   if(high > g_asianHigh) g_asianHigh = high;
   if(low  < g_asianLow)  g_asianLow  = low;
}

//+------------------------------------------------------------------+
//| Check for breakout                                               |
//+------------------------------------------------------------------+
void CheckBreakout()
{
   // Already at max trades
   if(g_tradesToday >= InpMaxTradesPerDay) return;

   // Already in a position
   if(HasPosition(_Symbol, InpMagicNumber)) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double rangePoints = (g_asianHigh - g_asianLow) / point;

   // Range filter
   if(rangePoints < InpMinRangePoints || rangePoints > InpMaxRangePoints) return;

   double buffer = InpBreakoutBuffer * point;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double breakoutHigh = g_asianHigh + buffer;
   double breakoutLow  = g_asianLow  - buffer;

   // Calculate SL distance (opposite side of range)
   double slDistanceBuy  = ask - (g_asianLow - buffer);
   double slDistanceSell = (g_asianHigh + buffer) - bid;

   // BUY: price breaks above Asian high
   if(ask > breakoutHigh)
   {
      double sl = NormPrice(_Symbol, g_asianLow - buffer);
      double tp = NormPrice(_Symbol, ask + slDistanceBuy * InpRiskReward);
      double lots = CalcLotSize(_Symbol, InpRiskPercent, slDistanceBuy / point);

      if(trade.Buy(lots, _Symbol, ask, sl, tp, "SB BUY"))
      {
         g_tradesToday++;
         Print("BUY Breakout: Asian H=", g_asianHigh, " L=", g_asianLow,
               " Range=", DoubleToString(rangePoints, 0), " pts");
      }
   }
   // SELL: price breaks below Asian low
   else if(bid < breakoutLow)
   {
      double sl = NormPrice(_Symbol, g_asianHigh + buffer);
      double tp = NormPrice(_Symbol, bid - slDistanceSell * InpRiskReward);
      double lots = CalcLotSize(_Symbol, InpRiskPercent, slDistanceSell / point);

      if(trade.Sell(lots, _Symbol, bid, sl, tp, "SB SELL"))
      {
         g_tradesToday++;
         Print("SELL Breakout: Asian H=", g_asianHigh, " L=", g_asianLow,
               " Range=", DoubleToString(rangePoints, 0), " pts");
      }
   }
}

//+------------------------------------------------------------------+
