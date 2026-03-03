//+------------------------------------------------------------------+
//|                                    ExampleStrategyWithExport.mq5 |
//|                                          Strategy Exporter v1.0  |
//|                                                                  |
//| Strategy: RSI + Bollinger Bands + MACD Confluence                |
//|                                                                  |
//| Chart indicators (overlays):                                     |
//|   - SMA 50 (trend filter)                                       |
//|   - Bollinger Bands 20,2                                        |
//|                                                                  |
//| Panel indicators (oscillators):                                  |
//|   - RSI 14 (entry signal)                                       |
//|   - MACD 12,26,9 (confirmation)                                 |
//|                                                                  |
//| Higher timeframe:                                                |
//|   - SMA 50 on D1 (trend direction)                              |
//|                                                                  |
//| Rules:                                                           |
//|   BUY:  Price near lower BB, RSI < 35, MACD histogram turning   |
//|         up, price above D1 SMA 50                                |
//|   SELL: Price near upper BB, RSI > 65, MACD histogram turning   |
//|         down, price below D1 SMA 50                              |
//|                                                                  |
//|   Exit: SL/TP based on ATR or fixed pips                        |
//+------------------------------------------------------------------+
#property copyright "Strategy Exporter"
#property link      "https://github.com/algo-trading"
#property version   "1.00"

#include <StrategyExporter/StrategyExporter.mqh>
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Trade Settings ==="
input double InpLotSize        = 0.1;     // Lot Size
input int    InpStopLoss       = 50;      // Stop Loss (pips)
input int    InpTakeProfit     = 100;     // Take Profit (pips)
input ulong  InpMagicNumber    = 123456;  // Magic Number

input group "=== Indicator Settings ==="
input int    InpSMA_Period     = 50;      // SMA Period
input int    InpBB_Period      = 20;      // Bollinger Bands Period
input double InpBB_Deviation   = 2.0;     // Bollinger Bands Deviation
input int    InpRSI_Period     = 14;      // RSI Period
input double InpRSI_BuyLevel  = 35.0;    // RSI Buy Level (oversold)
input double InpRSI_SellLevel = 65.0;    // RSI Sell Level (overbought)
input int    InpMACD_Fast      = 12;      // MACD Fast Period
input int    InpMACD_Slow      = 26;      // MACD Slow Period
input int    InpMACD_Signal    = 9;       // MACD Signal Period

input group "=== Higher Timeframe ==="
input ENUM_TIMEFRAMES InpHTF   = PERIOD_D1; // Higher Timeframe

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CStrategyExporter exporter;
CTrade            trade;

// Indicator handles - primary timeframe
int hSMA;
int hBB;
int hRSI;
int hMACD;

// Indicator handles - higher timeframe
int hSMA_HTF;

// Tracking
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set up trading
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetDeviationInPoints(10);

   //--- Create indicators on primary timeframe

   // Chart overlay indicators
   hSMA = iMA(_Symbol, PERIOD_CURRENT, InpSMA_Period, 0, MODE_SMA, PRICE_CLOSE);
   hBB  = iBands(_Symbol, PERIOD_CURRENT, InpBB_Period, 0, InpBB_Deviation, PRICE_CLOSE);

   // Panel indicators (oscillators)
   hRSI  = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   hMACD = iMACD(_Symbol, PERIOD_CURRENT, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);

   // Higher timeframe indicator
   hSMA_HTF = iMA(_Symbol, InpHTF, InpSMA_Period, 0, MODE_SMA, PRICE_CLOSE);

   //--- Validate handles
   if(hSMA == INVALID_HANDLE || hBB == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hMACD == INVALID_HANDLE ||
      hSMA_HTF == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return INIT_FAILED;
   }

   //--- Initialize Strategy Exporter
   exporter.Init("RSI_BB_MACD_Strategy", InpMagicNumber);

   // Register timeframes
   exporter.AddTimeframe(PERIOD_CURRENT);
   exporter.AddTimeframe(InpHTF);

   // Register chart overlay indicators (primary TF)
   exporter.RegisterIndicator(hSMA, StringFormat("SMA_%d", InpSMA_Period), 1);
   exporter.RegisterIndicator(hBB,  StringFormat("BB_%d_%.1f", InpBB_Period, InpBB_Deviation), 3);

   // Give BB proper buffer names
   string bbNames[] = {"middle", "upper", "lower"};
   // Note: iBands buffer order: 0=BASE(middle), 1=UPPER, 2=LOWER

   // Register panel indicators (primary TF)
   exporter.RegisterIndicator(hRSI,  StringFormat("RSI_%d", InpRSI_Period), 1);
   exporter.RegisterIndicator(hMACD, StringFormat("MACD_%d_%d_%d", InpMACD_Fast, InpMACD_Slow, InpMACD_Signal), 3);

   // Register higher TF indicator
   exporter.RegisterIndicator(hSMA_HTF, StringFormat("SMA_%d_%s", InpSMA_Period,
                              STimeframeData::TimeframeToString(InpHTF)), 1, InpHTF);

   Print("Strategy initialized successfully!");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Export strategy data to JSON
   exporter.Export();

   //--- Release indicator handles
   IndicatorRelease(hSMA);
   IndicatorRelease(hBB);
   IndicatorRelease(hRSI);
   IndicatorRelease(hMACD);
   IndicatorRelease(hSMA_HTF);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Let exporter collect data
   exporter.OnTick();

   //--- Only trade on new bar
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;

   //--- Check for trade signals
   CheckForSignal();
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
//| Check for trade signals                                          |
//+------------------------------------------------------------------+
void CheckForSignal()
{
   //--- Get indicator values (bar 1 = completed bar)

   // SMA
   double sma[];
   if(CopyBuffer(hSMA, 0, 1, 1, sma) != 1) return;

   // Bollinger Bands
   double bbMiddle[], bbUpper[], bbLower[];
   if(CopyBuffer(hBB, 0, 1, 1, bbMiddle) != 1) return;
   if(CopyBuffer(hBB, 1, 1, 1, bbUpper) != 1) return;
   if(CopyBuffer(hBB, 2, 1, 1, bbLower) != 1) return;

   // RSI
   double rsi[];
   if(CopyBuffer(hRSI, 0, 1, 1, rsi) != 1) return;

   // MACD - current bar (bar 1)
   double macdMain[], macdSignal[];
   if(CopyBuffer(hMACD, 0, 1, 1, macdMain) != 1) return;
   if(CopyBuffer(hMACD, 1, 1, 1, macdSignal) != 1) return;

   // MACD - previous bar (bar 2)
   double macdMainPrev[], macdSignalPrev[];
   if(CopyBuffer(hMACD, 0, 2, 1, macdMainPrev) != 1) return;
   if(CopyBuffer(hMACD, 1, 2, 1, macdSignalPrev) != 1) return;

   // HTF SMA
   double smaHTF[];
   if(CopyBuffer(hSMA_HTF, 0, 1, 1, smaHTF) != 1) return;

   // Price data
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double low   = iLow(_Symbol, PERIOD_CURRENT, 1);
   double high  = iHigh(_Symbol, PERIOD_CURRENT, 1);

   //--- Calculate MACD histogram
   double macdHist = macdMain[0] - macdSignal[0];
   double macdHistPrev = macdMainPrev[0] - macdSignalPrev[0];

   //--- Check if we have any open positions
   bool hasPosition = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         hasPosition = true;
         break;
      }
   }

   //--- Skip if already in position
   if(hasPosition)
      return;

   //--- Calculate SL/TP
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- BUY Signal
   // Price near lower BB, RSI oversold, MACD histogram turning up, above D1 SMA
   bool buyCondition =
      (low <= bbLower[0] || close <= bbLower[0] * 1.001) &&  // Price touching/near lower BB
      (rsi[0] < InpRSI_BuyLevel) &&                           // RSI oversold
      (macdHist > macdHistPrev) &&                             // MACD histogram turning up
      (close > smaHTF[0]);                                     // Above D1 SMA (uptrend)

   //--- SELL Signal
   // Price near upper BB, RSI overbought, MACD histogram turning down, below D1 SMA
   bool sellCondition =
      (high >= bbUpper[0] || close >= bbUpper[0] * 0.999) &&  // Price touching/near upper BB
      (rsi[0] > InpRSI_SellLevel) &&                           // RSI overbought
      (macdHist < macdHistPrev) &&                             // MACD histogram turning down
      (close < smaHTF[0]);                                     // Below D1 SMA (downtrend)

   //--- Execute trades
   if(buyCondition)
   {
      double sl = ask - InpStopLoss * point;
      double tp = ask + InpTakeProfit * point;

      if(trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "RSI_BB_MACD BUY"))
         Print("BUY Signal: RSI=", DoubleToString(rsi[0], 1),
               " BB_Lower=", DoubleToString(bbLower[0], _Digits),
               " MACD_Hist=", DoubleToString(macdHist, 6));
      else
         Print("BUY Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
   else if(sellCondition)
   {
      double sl = bid + InpStopLoss * point;
      double tp = bid - InpTakeProfit * point;

      if(trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "RSI_BB_MACD SELL"))
         Print("SELL Signal: RSI=", DoubleToString(rsi[0], 1),
               " BB_Upper=", DoubleToString(bbUpper[0], _Digits),
               " MACD_Hist=", DoubleToString(macdHist, 6));
      else
         Print("SELL Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
