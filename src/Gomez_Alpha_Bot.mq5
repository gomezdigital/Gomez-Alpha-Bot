//+------------------------------------------------------------------+
//|                                                   Gomez_Alpha_Bot.mq5
//|                         GOMEZ ALPHA BOT - MT5 Expert Advisor
//| Purpose: EURUSD market analysis and signal reporting only
//| Strategy: M15 setup + H1 trend confirmation
//| Safety: NO order placement, modification, or closing
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"
#property description "Gomez Alpha Bot: analysis-only M15/H1 signal assistant."

enum SIGNAL_DIRECTION
  {
   SIGNAL_SELL = -1,
   SIGNAL_WAIT =  0,
   SIGNAL_BUY  =  1
  };

//--- Market and timeframe settings
input group "01. Market"
input string          InpSymbol               = "EURUSD";
input ENUM_TIMEFRAMES InpSignalTimeframe      = PERIOD_M15;
input ENUM_TIMEFRAMES InpTrendTimeframe       = PERIOD_H1;

//--- Indicator settings
input group "02. Indicators"
input int             InpFastEMA              = 50;
input int             InpSlowEMA              = 200;
input int             InpRSIPeriod            = 14;
input double          InpRSIBuyThreshold       = 52.0;
input double          InpRSISellThreshold      = 48.0;
input int             InpMACDFast              = 12;
input int             InpMACDSlow              = 26;
input int             InpMACDSignal            = 9;
input int             InpATRPeriod             = 14;

//--- Structure and illustrative risk reference settings
input group "03. Structure and Risk References"
input int             InpStructureLookback     = 80;
input int             InpSwingStrength         = 2;
input double          InpStopATRMultiplier      = 1.5;
input double          InpTargetATRMultiplier    = 2.0;

//--- Output settings
input group "04. Output"
input bool            InpShowChartComment      = true;
input bool            InpLogWaitSignals        = true;

int hM15FastEMA = INVALID_HANDLE;
int hM15SlowEMA = INVALID_HANDLE;
int hH1FastEMA  = INVALID_HANDLE;
int hH1SlowEMA  = INVALID_HANDLE;
int hRSI        = INVALID_HANDLE;
int hMACD       = INVALID_HANDLE;
int hATR        = INVALID_HANDLE;
datetime g_lastSignalBarTime = 0;

//+------------------------------------------------------------------+
//| Read one indicator value safely from a specified buffer and bar. |
//+------------------------------------------------------------------+
bool ReadBufferValue(const int handle,const int buffer,const int shift,double &value)
  {
   value=EMPTY_VALUE;
   if(handle==INVALID_HANDLE)
      return false;

   double data[];
   ArraySetAsSeries(data,true);
   ResetLastError();
   if(CopyBuffer(handle,buffer,shift,1,data)!=1)
      return false;

   value=data[0];
   return (value!=EMPTY_VALUE && MathIsValidNumber(value));
  }

//+------------------------------------------------------------------+
//| Check whether all indicator handles have enough calculated data. |
//+------------------------------------------------------------------+
bool IndicatorsReady()
  {
   return (BarsCalculated(hM15FastEMA)>InpSlowEMA &&
           BarsCalculated(hM15SlowEMA)>InpSlowEMA &&
           BarsCalculated(hH1FastEMA)>InpSlowEMA &&
           BarsCalculated(hH1SlowEMA)>InpSlowEMA &&
           BarsCalculated(hRSI)>InpRSIPeriod &&
           BarsCalculated(hMACD)>InpMACDSlow+InpMACDSignal &&
           BarsCalculated(hATR)>InpATRPeriod);
  }

//+------------------------------------------------------------------+
//| Return true once for each newly opened signal-timeframe candle.  |
//+------------------------------------------------------------------+
bool IsNewSignalBar()
  {
   datetime barTime=iTime(InpSymbol,InpSignalTimeframe,0);
   if(barTime<=0 || barTime==g_lastSignalBarTime)
      return false;

   g_lastSignalBarTime=barTime;
   return true;
  }

//+------------------------------------------------------------------+
//| Confirmed swing high/low detection using closed bars only.        |
//| Support/resistance are the nearest confirmed pivots around price. |
//+------------------------------------------------------------------+
bool FindStructure(const double currentPrice,double &support,double &resistance)
  {
   support=0.0;
   resistance=0.0;

   int totalBars=Bars(InpSymbol,InpSignalTimeframe);
   int strength=InpSwingStrength;
   int lastCandidate=MathMin(InpStructureLookback,totalBars-strength-1);
   if(lastCandidate<=strength+1)
      return false;

   double nearestSupport=-DBL_MAX;
   double nearestResistance=DBL_MAX;

   for(int shift=strength+1;shift<=lastCandidate;shift++)
     {
      double candidateHigh=iHigh(InpSymbol,InpSignalTimeframe,shift);
      double candidateLow=iLow(InpSymbol,InpSignalTimeframe,shift);
      if(candidateHigh<=0.0 || candidateLow<=0.0)
         continue;

      bool isSwingHigh=true;
      bool isSwingLow=true;

      for(int offset=1;offset<=strength;offset++)
        {
         // More recent closed bars and older bars must not exceed the pivot.
         if(candidateHigh<=iHigh(InpSymbol,InpSignalTimeframe,shift-offset) ||
            candidateHigh<=iHigh(InpSymbol,InpSignalTimeframe,shift+offset))
            isSwingHigh=false;

         if(candidateLow>=iLow(InpSymbol,InpSignalTimeframe,shift-offset) ||
            candidateLow>=iLow(InpSymbol,InpSignalTimeframe,shift+offset))
            isSwingLow=false;

         if(!isSwingHigh && !isSwingLow)
            break;
        }

      if(isSwingLow && candidateLow<currentPrice &&
         candidateLow>nearestSupport)
         nearestSupport=candidateLow;

      if(isSwingHigh && candidateHigh>currentPrice &&
         candidateHigh<nearestResistance)
         nearestResistance=candidateHigh;
     }

   if(nearestSupport>-DBL_MAX)
      support=nearestSupport;
   if(nearestResistance<DBL_MAX)
      resistance=nearestResistance;

   // If a confirmed pivot is missing on one side, use the recent extreme
   // on that side as a conservative context reference, not as a swing pivot.
   if(support<=0.0 || resistance<=0.0)
     {
      int count=MathMin(InpStructureLookback,totalBars-1);
      if(count<2)
         return false;

      double recentLow=DBL_MAX;
      double recentHigh=-DBL_MAX;
      for(int shift=1;shift<=count;shift++)
        {
         double low=iLow(InpSymbol,InpSignalTimeframe,shift);
         double high=iHigh(InpSymbol,InpSignalTimeframe,shift);
         if(low>0.0 && low<recentLow) recentLow=low;
         if(high>0.0 && high>recentHigh) recentHigh=high;
        }

      if(support<=0.0 && recentLow<currentPrice)
         support=recentLow;
      if(resistance<=0.0 && recentHigh>currentPrice)
         resistance=recentHigh;
     }

   return (support>0.0 && resistance>0.0 && support<resistance);
  }

//+------------------------------------------------------------------+
//| Human-readable signal label.                                     |
//+------------------------------------------------------------------+
string SignalName(const SIGNAL_DIRECTION signal)
  {
   if(signal==SIGNAL_BUY)  return "BUY";
   if(signal==SIGNAL_SELL) return "SELL";
   return "WAIT";
  }

//+------------------------------------------------------------------+
//| Evaluate the previous fully closed signal candle.                |
//+------------------------------------------------------------------+
void AnalyzeClosedCandle()
  {
   if(!IndicatorsReady())
     {
      Print("GOMEZ ALPHA BOT | WAIT | Indicator history is still loading.");
      return;
     }

   // WAIT is intentional: all required checks must pass before a direction
   // can be reported. No order-related functions are called anywhere.
   SIGNAL_DIRECTION signal=SIGNAL_WAIT;
   string reason="Conditions not fully aligned";

   double closeM15=iClose(InpSymbol,InpSignalTimeframe,1);
   double closeH1=iClose(InpSymbol,InpTrendTimeframe,1);
   double m15Fast,m15Slow,h1Fast,h1Slow,rsi,macdMain,macdSignal,atr;

   if(closeM15<=0.0 || closeH1<=0.0 ||
      !ReadBufferValue(hM15FastEMA,0,1,m15Fast) ||
      !ReadBufferValue(hM15SlowEMA,0,1,m15Slow) ||
      !ReadBufferValue(hH1FastEMA,0,1,h1Fast) ||
      !ReadBufferValue(hH1SlowEMA,0,1,h1Slow) ||
      !ReadBufferValue(hRSI,0,1,rsi) ||
      !ReadBufferValue(hMACD,0,1,macdMain) ||
      !ReadBufferValue(hMACD,1,1,macdSignal) ||
      !ReadBufferValue(hATR,0,1,atr) || atr<=0.0)
     {
      Print("GOMEZ ALPHA BOT | WAIT | Price or indicator data unavailable.");
      return;
     }

   double support,resistance;
   if(!FindStructure(closeM15,support,resistance))
     {
      Print("GOMEZ ALPHA BOT | WAIT | Reliable structure levels unavailable.");
      return;
     }

   // H1 trend: EMA alignment plus closed H1 price relative to EMA 200.
   bool h1Bullish=(h1Fast>h1Slow && closeH1>h1Slow);
   bool h1Bearish=(h1Fast<h1Slow && closeH1<h1Slow);

   // M15 setup: EMA alignment plus closed M15 price relative to EMA 50.
   bool m15Bullish=(m15Fast>m15Slow && closeM15>m15Fast);
   bool m15Bearish=(m15Fast<m15Slow && closeM15<m15Fast);

   bool momentumBullish=(rsi>=InpRSIBuyThreshold && macdMain>macdSignal);
   bool momentumBearish=(rsi<=InpRSISellThreshold && macdMain<macdSignal);

   double roomToResistance=resistance-closeM15;
   double roomToSupport=closeM15-support;
   bool roomForBuy=(roomToResistance>atr);
   bool roomForSell=(roomToSupport>atr);

   if(h1Bullish && m15Bullish && momentumBullish && roomForBuy)
     {
      signal=SIGNAL_BUY;
      reason="H1 trend, M15 setup and momentum aligned";
     }
   else if(h1Bearish && m15Bearish && momentumBearish && roomForSell)
     {
      signal=SIGNAL_SELL;
      reason="H1 trend, M15 setup and momentum aligned";
     }
   else if((h1Bullish && !roomForBuy) || (h1Bearish && !roomForSell))
      reason="Insufficient room before opposing structure";

   int digits=(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS);
   double stopReference=0.0;
   double targetReference=0.0;
   if(signal==SIGNAL_BUY)
     {
      stopReference=closeM15-(atr*InpStopATRMultiplier);
      targetReference=closeM15+(atr*InpTargetATRMultiplier);
     }
   else if(signal==SIGNAL_SELL)
     {
      stopReference=closeM15+(atr*InpStopATRMultiplier);
      targetReference=closeM15-(atr*InpTargetATRMultiplier);
     }

   string report="GOMEZ ALPHA BOT v1.10\n";
   report+="MODE: ANALYSIS ONLY - NO ORDERS\n";
   report+="Signal: "+SignalName(signal)+" | "+InpSymbol+"\n";
   report+="Signal timeframe: "+EnumToString(InpSignalTimeframe)+
            " | Trend timeframe: "+EnumToString(InpTrendTimeframe)+"\n";
   report+="Closed candle: "+TimeToString(iTime(InpSymbol,InpSignalTimeframe,1),TIME_DATE|TIME_MINUTES)+"\n";
   report+="Close: "+DoubleToString(closeM15,digits)+
            " | RSI: "+DoubleToString(rsi,2)+
            " | MACD: "+DoubleToString(macdMain,digits)+
            " / "+DoubleToString(macdSignal,digits)+"\n";
   report+="H1 EMA50/200: "+DoubleToString(h1Fast,digits)+
            " / "+DoubleToString(h1Slow,digits)+
            " | H1 close: "+DoubleToString(closeH1,digits)+"\n";
   report+="Support: "+DoubleToString(support,digits)+
            " | Resistance: "+DoubleToString(resistance,digits)+
            " | ATR: "+DoubleToString(atr,digits)+"\n";
   report+="Assessment: "+reason;

   if(signal!=SIGNAL_WAIT)
      report+="\nIllustrative SL: "+DoubleToString(stopReference,digits)+
              " | Illustrative TP: "+DoubleToString(targetReference,digits);

   if(signal!=SIGNAL_WAIT || InpLogWaitSignals)
      Print(report);
   if(InpShowChartComment)
      Comment(report);
  }

//+------------------------------------------------------------------+
//| Expert initialization.                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(StringLen(InpSymbol)<1 ||
      InpFastEMA<1 || InpSlowEMA<=InpFastEMA ||
      InpRSIPeriod<2 || InpMACDFast<1 ||
      InpMACDSlow<=InpMACDFast || InpMACDSignal<1 ||
      InpATRPeriod<1 || InpStructureLookback<10 ||
      InpSwingStrength<1 || InpSwingStrength>10 ||
      InpRSISellThreshold<0.0 || InpRSIBuyThreshold>100.0 ||
      InpRSISellThreshold>=InpRSIBuyThreshold ||
      InpStopATRMultiplier<=0.0 || InpTargetATRMultiplier<=0.0)
     {
      Print("GOMEZ ALPHA BOT: Invalid input settings. Check the EA inputs.");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(!SymbolSelect(InpSymbol,true))
     {
      Print("GOMEZ ALPHA BOT: Could not select symbol ",InpSymbol,
            ". Check the broker's symbol name (some use suffixes).");
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
      Print("GOMEZ ALPHA BOT: Failed to initialize indicator handles. Error ",
            GetLastError());
      return INIT_FAILED;
     }

   Print("GOMEZ ALPHA BOT v1.10 initialized for ",InpSymbol,
         ". Analysis-only mode is enforced; no order execution is implemented.");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Release resources on unload.                                     |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Tick handler: analyze only once when a new signal bar begins.    |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(IsNewSignalBar())
      AnalyzeClosedCandle();
  }
//+------------------------------------------------------------------+
