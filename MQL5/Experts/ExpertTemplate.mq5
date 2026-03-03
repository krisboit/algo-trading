//+------------------------------------------------------------------+
//|                                               ExpertTemplate.mq5 |
//|                                                      Your Name   |
//|                                             https://www.site.com |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "https://www.site.com"
#property version   "1.00"

//--- input parameters
input double LotSize = 0.01;
input int    StopLoss = 50;
input int    TakeProfit = 100;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- initialization code
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- cleanup code
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- main trading logic
}

//+------------------------------------------------------------------+
