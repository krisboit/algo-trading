//+------------------------------------------------------------------+
//|                                      KeltnerChannelBreakout.mq5  |
//|  Strategy 6: Keltner Channel Breakout (KC + ATR volatility)      |
//|                                                                  |
//|  BUY:  Candle opens below lower KC, closes above it, ATR5>5pip   |
//|  SELL: Candle opens above upper KC, closes below it, ATR5>5pip   |
//|  Entry: signal candle close +/- 3 pips                           |
//|  SL:   signal candle low (buy) / high (sell) +/- spread          |
//|  TP:   opposite KC band                                          |
//|  BE:   move SL to entry when 1RR profit reached                  |
//+------------------------------------------------------------------+
#property copyright "Strategy Exporter"
#property link      "https://github.com/algo-trading"
#property version   "1.00"

#include <StrategyExporter/RiskManager.mqh>
#include <Framework/StrategyBase.mqh>
#include <Framework/TradeManager.mqh>
#include <Framework/TesterExport.mqh>
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Keltner Channel ==="
input int    InpKC_EMA_Period   = 20;      // KC EMA Period
input int    InpKC_ATR_Period   = 10;      // KC ATR Period
input double InpKC_ATR_Mult     = 2.0;    // KC ATR Multiplier

input group "=== Volatility Filter ==="
input int    InpATR_Filter_Period = 5;     // ATR Filter Period
input double InpATR_Min_Pips     = 5.0;   // Min ATR (pips)

input group "=== Trade Settings ==="
input double InpEntryOffset     = 3.0;    // Entry Offset (pips from candle close)
input double InpRiskPercent     = 1.0;    // Risk Per Trade (%)
input ulong  InpMagicNumber     = 100006; // Magic Number

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;

int hKC_EMA;        // EMA handle for KC middle line
int hKC_ATR;        // ATR handle for KC band width
int hATR_Filter;    // ATR handle for volatility filter

datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetDeviationInPoints(30);

   // KC middle line = EMA
   hKC_EMA = iMA(_Symbol, PERIOD_CURRENT, InpKC_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   // KC band width = ATR
   hKC_ATR = iATR(_Symbol, PERIOD_CURRENT, InpKC_ATR_Period);
   // Volatility filter = ATR(5)
   hATR_Filter = iATR(_Symbol, PERIOD_CURRENT, InpATR_Filter_Period);

   if(hKC_EMA == INVALID_HANDLE || hKC_ATR == INVALID_HANDLE || hATR_Filter == INVALID_HANDLE)
   {
      Print("Error creating indicator handles! Error=", GetLastError());
      return INIT_FAILED;
   }

   Print("KeltnerChannelBreakout initialized on ", _Symbol,
         " | KC(", InpKC_EMA_Period, ",", InpKC_ATR_Period, ",", InpKC_ATR_Mult, ")",
         " | ATR Filter(", InpATR_Filter_Period, ") > ", InpATR_Min_Pips, " pips",
         " | Risk: ", InpRiskPercent, "%");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hKC_EMA);
   IndicatorRelease(hKC_ATR);
   IndicatorRelease(hATR_Filter);
}

//+------------------------------------------------------------------+
//| Optimization fitness function (Framework)                        |
//+------------------------------------------------------------------+
double OnTester()
{
   double fitness = CalcFitness();

   string names[]  = {"InpKC_EMA_Period", "InpKC_ATR_Period", "InpKC_ATR_Mult",
                       "InpATR_Filter_Period", "InpATR_Min_Pips", "InpEntryOffset",
                       "InpRiskPercent"};
   double values[] = {InpKC_EMA_Period, InpKC_ATR_Period, InpKC_ATR_Mult,
                      InpATR_Filter_Period, InpATR_Min_Pips, InpEntryOffset,
                      InpRiskPercent};
   TesterExportPass(names, values, fitness);

   return fitness;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- Breakeven management: check every tick ---
   if(HasPosition(_Symbol, InpMagicNumber))
      CheckBreakEven(_Symbol, InpMagicNumber, trade);

   // --- New bar detection: signals only on bar close ---
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   // Don't enter if already in a position
   if(HasPosition(_Symbol, InpMagicNumber)) return;

   CheckForSignal();
}

//+------------------------------------------------------------------+
//| Convert pips to price units based on symbol digits               |
//+------------------------------------------------------------------+
double PipsToPrice(double pips)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   // 5-digit (EURUSD etc.) or 3-digit (USDJPY etc.) brokers: 1 pip = 10 points
   // 4-digit or 2-digit brokers: 1 pip = 1 point
   if(digits == 5 || digits == 3)
      return pips * 10.0 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   else
      return pips * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| Check for entry signal on completed bar                          |
//+------------------------------------------------------------------+
void CheckForSignal()
{
   //--- Get indicator values for the completed bar (index 1) ---
   double ema[], kcATR[], filterATR[];

   if(CopyBuffer(hKC_EMA,    0, 1, 1, ema)       != 1) return;
   if(CopyBuffer(hKC_ATR,    0, 1, 1, kcATR)     != 1) return;
   if(CopyBuffer(hATR_Filter, 0, 1, 1, filterATR) != 1) return;

   //--- Calculate Keltner Channel bands ---
   double upperBand = ema[0] + kcATR[0] * InpKC_ATR_Mult;
   double lowerBand = ema[0] - kcATR[0] * InpKC_ATR_Mult;

   //--- Get signal candle OHLC (completed bar, index 1) ---
   double open1  = iOpen(_Symbol,  PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double high1  = iHigh(_Symbol,  PERIOD_CURRENT, 1);
   double low1   = iLow(_Symbol,   PERIOD_CURRENT, 1);

   //--- Volatility filter: ATR(5) must exceed minimum pips ---
   double minATRPrice = PipsToPrice(InpATR_Min_Pips);
   if(filterATR[0] < minATRPrice)
      return;

   //--- Price data ---
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   double entryOffsetPrice = PipsToPrice(InpEntryOffset);

   //=== BUY SIGNAL ===
   // Candle opens below lower KC band, closes above lower KC band
   if(open1 < lowerBand && close1 > lowerBand)
   {
      double entryPrice = close1 + entryOffsetPrice;
      double slPrice    = low1 - spread;
      double tpPrice    = upperBand;

      // Validate: entry must be below TP, SL must be below entry
      if(entryPrice >= tpPrice || slPrice >= entryPrice)
      {
         Print("BUY signal rejected: invalid levels. Entry=", entryPrice,
               " SL=", slPrice, " TP=", tpPrice);
         return;
      }

      double slDist = entryPrice - slPrice;
      double slPoints = slDist / point;

      // Check minimum stop distance
      int minStopPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      if(slPoints < minStopPoints || (tpPrice - entryPrice) / point < minStopPoints)
      {
         Print("BUY signal rejected: SL or TP below minimum stop level (",
               minStopPoints, " points)");
         return;
      }

      double lots = CalcLotSize(_Symbol, InpRiskPercent, slPoints);

      // Use current ask for market execution
      if(trade.Buy(lots, _Symbol, ask,
                   NormPrice(_Symbol, slPrice),
                   NormPrice(_Symbol, tpPrice),
                   "KC BUY"))
      {
         Print("KC BUY opened: Lots=", DoubleToString(lots, 2),
               " Entry=", DoubleToString(ask, _Digits),
               " SL=", DoubleToString(slPrice, _Digits),
               " TP=", DoubleToString(tpPrice, _Digits),
               " ATR5=", DoubleToString(filterATR[0] / PipsToPrice(1.0), 1), " pips",
               " | KC Upper=", DoubleToString(upperBand, _Digits),
               " Lower=", DoubleToString(lowerBand, _Digits));
      }
   }
   //=== SELL SIGNAL ===
   // Candle opens above upper KC band, closes below upper KC band
   else if(open1 > upperBand && close1 < upperBand)
   {
      double entryPrice = close1 - entryOffsetPrice;
      double slPrice    = high1 + spread;
      double tpPrice    = lowerBand;

      // Validate: entry must be above TP, SL must be above entry
      if(entryPrice <= tpPrice || slPrice <= entryPrice)
      {
         Print("SELL signal rejected: invalid levels. Entry=", entryPrice,
               " SL=", slPrice, " TP=", tpPrice);
         return;
      }

      double slDist = slPrice - entryPrice;
      double slPoints = slDist / point;

      // Check minimum stop distance
      int minStopPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      if(slPoints < minStopPoints || (entryPrice - tpPrice) / point < minStopPoints)
      {
         Print("SELL signal rejected: SL or TP below minimum stop level (",
               minStopPoints, " points)");
         return;
      }

      double lots = CalcLotSize(_Symbol, InpRiskPercent, slPoints);

      // Use current bid for market execution
      if(trade.Sell(lots, _Symbol, bid,
                    NormPrice(_Symbol, slPrice),
                    NormPrice(_Symbol, tpPrice),
                    "KC SELL"))
      {
         Print("KC SELL opened: Lots=", DoubleToString(lots, 2),
               " Entry=", DoubleToString(bid, _Digits),
               " SL=", DoubleToString(slPrice, _Digits),
               " TP=", DoubleToString(tpPrice, _Digits),
               " ATR5=", DoubleToString(filterATR[0] / PipsToPrice(1.0), 1), " pips",
               " | KC Upper=", DoubleToString(upperBand, _Digits),
               " Lower=", DoubleToString(lowerBand, _Digits));
      }
   }
}

//+------------------------------------------------------------------+
