//+------------------------------------------------------------------+
//|                                      Gomez_Alpha_Bot.mq5         |
//| GOMEZ ALPHA BOT - analysis-only MT5 Expert Advisor                |
//| Strategy: EURUSD, M15 signals with H1 trend confirmation          |
//| IMPORTANT: This EA does not place, modify, or close any orders.   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Analysis-only EURUSD M15/H1 signal assistant."

enum SIGNAL_DIRECTION
  {
   SIGNAL_WAIT = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

input string          InpSymbol              = "EURUSD";
input ENUM_TIMEFRAMES InpSignalTimeframe     = PERIOD_M15;
input ENUM_TIMEFRAMES InpTrendTimeframe      = PERIOD_H1;
input int             InpFastEMA             = 50;
input int             InpSlowEMA             = 200;
input int             InpRSIPeriod           = 14;
input int             InpMACDFast             = 12;
input int             InpMACDSlow             = 26;
input int             InpMACDSignal           = 9;
input int             InpATRPeriod            = 14;
input int             InpStructureLookback    = 50;
input int             InpSwingStrength        = 2;
input double          InpStopATRMultiplier    = 1.5;
input double          InpTargetATRMultiplier  = 2.0;
input bool            InpShowChartComment     = true;

int hM15FastEMA = INVALID_HANDLE;
int hM15SlowEMA = INVALID_HANDLE;
int hH1FastEMA  = INVALID_HANDLE;
int hH1SlowEMA  = INVALID_HANDLE;
int hRSI        = INVALID_HANDLE;
int hMACD       = INVALID_HANDLE;
int hATR        = INVALID_HANDLE;
datetime lastM15BarTime = 0;

double BufferValue(const int handle,const int buffer,const int shift)
  {
   double values[];
   ArraySetAsSeries(values,true);
   if(handle==INVALID_HANDLE || CopyBuffer(handle,buffer,shift,1,values)!=1)
      return EMPTY_VALUE;
   return values[0];
  }

bool IsNewSignalBar()
  {
   datetime barTime=iTime(InpSymbol,InpSignalTimeframe,0);
   if(barTime<=0 || barTime==lastM15BarTime)
      return false;
   lastM15BarTime=barTime;
   return true;
  }

// Finds recent swing-based support/resistance using closed candles only.
bool FindStructure(double &support,double &resistance)
  {
   support=DBL_MAX;
   resistance=-DBL_MAX;
   int bars=Bars(InpSymbol,InpSignalTimeframe);
   int limit=MathMin(InpStructureLookback,bars-InpSwingStrength-2);
   if(limit<=InpSwingStrength+1)
      return false;

   for(int i=InpSwingStrength+1;i<=limit;i++)
     {
      double high=iHigh(InpSymbol,InpSignalTimeframe,i);
      double low=iLow(InpSymbol,InpSignalTimeframe,i);
      if(high>0 && high>resistance)
         resistance=high;
      if(low>0 && low<support)
         support=low;
     }
   return (support<DBL_MAX && resistance>-DBL_MAX);
  }

string SignalName(const SIGNAL_DIRECTION signal)
  {
   if(signal==SIGNAL_BUY)  return "BUY";
   if(signal==SIGNAL_SELL) return "SELL";
   return "WAIT";
  }

void AnalyzeClosedCandle()
  {
   // WAIT is the safe default. A signal is emitted only when all checks agree.
   SIGNAL_DIRECTION signal=SIGNAL_WAIT;

   double close1=iClose(InpSymbol,InpSignalTimeframe,1);
   double m15Fast=BufferValue(hM15FastEMA,0,1);
   double m15Slow=BufferValue(hM15SlowEMA,0,1);
   double h1Fast=BufferValue(hH1FastEMA,0,1);
   double h1Slow=BufferValue(hH1SlowEMA,0,1);
   double rsi=BufferValue(hRSI,0,1);
   double macdMain=BufferValue(hMACD,0,1);
   double macdSignal=BufferValue(hMACD,1,1);
   double atr=BufferValue(hATR,0,1);

   if(close1<=0 || m15Fast==EMPTY_VALUE || m15Slow==EMPTY_VALUE ||
      h1Fast==EMPTY_VALUE || h1Slow==EMPTY_VALUE || rsi==EMPTY_VALUE ||
      macdMain==EMPTY_VALUE || macdSignal==EMPTY_VALUE ||
      atr==EMPTY_VALUE || atr<=0)
     {
      Print("GOMEZ ALPHA BOT | WAIT | Indicator data not ready.");
      return;
     }

   double support,resistance;
   if(!FindStructure(support,resistance))
     {
      Print("GOMEZ ALPHA BOT | WAIT | Not enough structure data.");
      return;
     }

   bool h1Bullish=(h1Fast>h1Slow);
   bool h1Bearish=(h1Fast<h1Slow);
   bool m15Bullish=(m15Fast>m15Slow && close1>m15Fast);
   bool m15Bearish=(m15Fast<m15Slow && close1<m15Fast);
   bool momentumBullish=(rsi>=52.0 && macdMain>macdSignal);
   bool momentumBearish=(rsi<=48.0 && macdMain<macdSignal);

   // Avoid entries directly into nearby opposing structure.
   double roomToResistance=resistance-close1;
   double roomToSupport=close1-support;
   bool roomForBuy=(roomToResistance>atr);
   bool roomForSell=(roomToSupport>atr);

   if(h1Bullish && m15Bullish && momentumBullish && roomForBuy)
      signal=SIGNAL_BUY;
   else if(h1Bearish && m15Bearish && momentumBearish && roomForSell)
      signal=SIGNAL_SELL;

   double entry=close1;
   double stopLoss=0.0;
   double takeProfit=0.0;
   if(signal==SIGNAL_BUY)
     {
      stopLoss=entry-(atr*InpStopATRMultiplier);
      takeProfit=entry+(atr*InpTargetATRMultiplier);
     }
   else if(signal==SIGNAL_SELL)
     {
      stopLoss=entry+(atr*InpStopATRMultiplier);
      takeProfit=entry-(atr*InpTargetATRMultiplier);
     }

   int digits=(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS);
   string report="GOMEZ ALPHA BOT | "+SignalName(signal)+
      " | Symbol: "+InpSymbol+
      " | Signal TF: M15 | Trend TF: H1"+
      " | Close: "+DoubleToString(entry,digits)+
      " | RSI: "+DoubleToString(rsi,2)+
      " | MACD: "+DoubleToString(macdMain,digits)+
      " | ATR: "+DoubleToString(atr,digits)+
      " | Support: "+DoubleToString(support,digits)+
      " | Resistance: "+DoubleToString(resistance,digits);

   if(signal!=SIGNAL_WAIT)
      report+=" | Illustrative SL: "+DoubleToString(stopLoss,digits)+
              " | Illustrative TP: "+DoubleToString(takeProfit,digits);
   report+=" | ANALYSIS ONLY - NO ORDERS";

   Print(report);
   if(InpShowChartComment)
      Comment(report);
  }

int OnInit()
  {
   if(!SymbolSelect(InpSymbol,true))
     {
      Print("GOMEZ ALPHA BOT: Could not select symbol ",InpSymbol);
      return INIT_FAILED;
     }

   hM15FastEMA=iMA(InpSymbol,InpSignalTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   hM15SlowEMA=iMA(InpSymbol,InpSignalTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hH1FastEMA=iMA(InpSymbol,InpTrendTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   hH1SlowEMA=iMA(InpSymbol,InpTrendTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hRSI=iRSI(InpSymbol,InpSignalTimeframe,InpRSIPeriod,PRICE_CLOSE);
   hMACD=iMACD(InpSymbol,InpSignalTimeframe,InpMACDFast,InpMACDSlow,InpMACDSignal,PRICE_CLOSE);
   hATR=iATR(InpSymbol,InpSignalTimeframe,InpATRPeriod);

   if(hM15FastEMA==INVALID_HANDLE || hM15SlowEMA==INVALID_HANDLE ||
      hH1FastEMA==INVALID_HANDLE || hH1SlowEMA==INVALID_HANDLE ||
      hRSI==INVALID_HANDLE || hMACD==INVALID_HANDLE || hATR==INVALID_HANDLE)
     {
      Print("GOMEZ ALPHA BOT: Failed to initialize one or more indicator handles.");
      return INIT_FAILED;
     }

   Print("GOMEZ ALPHA BOT v1.00 initialized. Analysis-only mode; no trading functions are used.");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(hM15FastEMA!=INVALID_HANDLE) IndicatorRelease(hM15FastEMA);
   if(hM15SlowEMA!=INVALID_HANDLE) IndicatorRelease(hM15SlowEMA);
   if(hH1FastEMA!=INVALID_HANDLE)  IndicatorRelease(hH1FastEMA);
   if(hH1SlowEMA!=INVALID_HANDLE)  IndicatorRelease(hH1SlowEMA);
   if(hRSI!=INVALID_HANDLE)        IndicatorRelease(hRSI);
   if(hMACD!=INVALID_HANDLE)       IndicatorRelease(hMACD);
   if(hATR!=INVALID_HANDLE)        IndicatorRelease(hATR);
   Comment("");
  }

void OnTick()
  {
   if(!IsNewSignalBar())
      return;
   AnalyzeClosedCandle();
  }
//+------------------------------------------------------------------+
