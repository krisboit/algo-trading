//+------------------------------------------------------------------+
//|                                           IndicatorTemplate.mq5  |
//|                                                      Your Name   |
//|                                             https://www.site.com |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "https://www.site.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

//--- plot settings
#property indicator_label1  "Buffer1"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- input parameters
input int InpPeriod = 14;

//--- indicator buffers
double Buffer1[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- indicator buffers mapping
   SetIndexBuffer(0, Buffer1, INDICATOR_DATA);
   
   //--- set indicator name
   IndicatorSetString(INDICATOR_SHORTNAME, "IndicatorTemplate(" + IntegerToString(InpPeriod) + ")");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- calculation loop
   for(int i = prev_calculated; i < rates_total; i++)
   {
      Buffer1[i] = close[i];
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
