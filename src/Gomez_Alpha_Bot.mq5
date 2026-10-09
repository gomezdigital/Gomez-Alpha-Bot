//+------------------------------------------------------------------+
//|                                                   Gomez_Alpha_Bot.mq5
//|                         GOMEZ ALPHA BOT - MT5 Expert Advisor
//| Purpose: Multi-method EURUSD market analysis and trade-plan report
//| Framework: M15 setup + H1 trend confirmation
//| Safety: ANALYSIS ONLY - NO ORDER EXECUTION
//+------------------------------------------------------------------+
#property strict
#property version   "1.30"
#property description "Gomez Alpha Bot: multi-method analysis-only M15/H1 assistant."

enum SIGNAL_DIRECTION
  {
   SIGNAL_SELL = -1,
   SIGNAL_WAIT =  0,
   SIGNAL_BUY  =  1
  };

//--- 01. Market
input group "01. Market"
input string          InpSymbol                = "EURUSD";
input ENUM_TIMEFRAMES InpSignalTimeframe       = PERIOD_M15;
input ENUM_TIMEFRAMES InpTrendTimeframe        = PERIOD_H1;

//--- 02. Trend and momentum
input group "02. Trend and Momentum"
input int             InpFastEMA               = 50;
input int             InpSlowEMA               = 200;
input int             InpRSIPeriod             = 14;
input double          InpRSIBuyThreshold        = 52.0;
input double          InpRSISellThreshold       = 48.0;
input int             InpMACDFast               = 12;
input int             InpMACDSlow               = 26;
input int             InpMACDSignal             = 9;
input int             InpADXPeriod              = 14;
input double          InpADXTrendThreshold      = 20.0;
input int             InpATRPeriod              = 14;

//--- 03. Volatility and structure
input group "03. Volatility and Structure"
input int             InpBandsPeriod            = 20;
input double          InpBandsDeviation         = 2.0;
input int             InpStructureLookback      = 80;
input int             InpSwingStrength          = 2;
input double          InpMinimumRoomATR         = 1.0;

//--- 04. Trade-plan references (not sent to broker)
input group "04. Illustrative Trade Plan"
input double          InpStopATRMultiplier      = 1.5;
input double          InpTargetATRMultiplier    = 2.0;
input double          InpMinimumRewardRisk      = 1.2;
input int             InpMaximumSpreadPoints    = 30;

//--- 05. Output
input group "05. Reporting"
input int             InpMinimumScore           = 6;
input bool            InpShowChartComment       = true;
input bool            InpLogWaitSignals         = true;

int hM15FastEMA=INVALID_HANDLE;
int hM15SlowEMA=INVALID_HANDLE;
int hH1FastEMA=INVALID_HANDLE;
int hH1SlowEMA=INVALID_HANDLE;
int hRSI=INVALID_HANDLE;
int hMACD=INVALID_HANDLE;
int hATR=INVALID_HANDLE;
int hADX=INVALID_HANDLE;
int hBands=INVALID_HANDLE;
datetime g_lastSignalBarTime=0;
datetime g_lastReadinessNoticeBarTime=0;

//+------------------------------------------------------------------+
//| Read one indicator value safely.                                  |
//+------------------------------------------------------------------+
bool ReadBufferValue(const int handle,const int buffer,const int shift,double &value)
  {
   value=EMPTY_VALUE;
   if(handle==INVALID_HANDLE)
      return false;
   double data[];
   ArraySetAsSeries(data,true);
   if(CopyBuffer(handle,buffer,shift,1,data)!=1)
      return false;
   value=data[0];
   return (value!=EMPTY_VALUE && MathIsValidNumber(value));
  }

//+------------------------------------------------------------------+
//| Confirm all indicator histories are calculated.                  |
//+------------------------------------------------------------------+
bool IndicatorsReady()
  {
   return (BarsCalculated(hM15FastEMA)>InpSlowEMA &&
           BarsCalculated(hM15SlowEMA)>InpSlowEMA &&
           BarsCalculated(hH1FastEMA)>InpSlowEMA &&
           BarsCalculated(hH1SlowEMA)>InpSlowEMA &&
           BarsCalculated(hRSI)>InpRSIPeriod &&
           BarsCalculated(hMACD)>InpMACDSlow+InpMACDSignal &&
           BarsCalculated(hATR)>InpATRPeriod &&
           BarsCalculated(hADX)>InpADXPeriod &&
           BarsCalculated(hBands)>InpBandsPeriod);
  }

//+------------------------------------------------------------------+
//| New signal candle detector.                                      |
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
//| Find confirmed swing pivots and nearest support/resistance.       |
//+------------------------------------------------------------------+
bool FindStructure(const double price,double &support,double &resistance)
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
      double high=iHigh(InpSymbol,InpSignalTimeframe,shift);
      double low=iLow(InpSymbol,InpSignalTimeframe,shift);
      if(high<=0.0 || low<=0.0)
         continue;

      bool swingHigh=true;
      bool swingLow=true;
      for(int offset=1;offset<=strength;offset++)
        {
         if(high<=iHigh(InpSymbol,InpSignalTimeframe,shift-offset) ||
            high<=iHigh(InpSymbol,InpSignalTimeframe,shift+offset))
            swingHigh=false;
         if(low>=iLow(InpSymbol,InpSignalTimeframe,shift-offset) ||
            low>=iLow(InpSymbol,InpSignalTimeframe,shift+offset))
            swingLow=false;
         if(!swingHigh && !swingLow)
            break;
        }

      if(swingLow && low<price && low>nearestSupport)
         nearestSupport=low;
      if(swingHigh && high>price && high<nearestResistance)
         nearestResistance=high;
     }

   if(nearestSupport>-DBL_MAX)
      support=nearestSupport;
   if(nearestResistance<DBL_MAX)
      resistance=nearestResistance;

   // Context fallback if a confirmed pivot is unavailable on one side.
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
      if(support<=0.0 && recentLow<price) support=recentLow;
      if(resistance<=0.0 && recentHigh>price) resistance=recentHigh;
     }

   return (support>0.0 && resistance>0.0 && support<resistance);
  }

//+------------------------------------------------------------------+
//| Simple closed-candle pattern checks; not standalone entry rules.  |
//+------------------------------------------------------------------+
bool BullishEngulfing()
  {
   double o1=iOpen(InpSymbol,InpSignalTimeframe,1);
   double c1=iClose(InpSymbol,InpSignalTimeframe,1);
   double o2=iOpen(InpSymbol,InpSignalTimeframe,2);
   double c2=iClose(InpSymbol,InpSignalTimeframe,2);
   return (c2<o2 && c1>o1 && o1<=c2 && c1>=o2);
  }

bool BearishEngulfing()
  {
   double o1=iOpen(InpSymbol,InpSignalTimeframe,1);
   double c1=iClose(InpSymbol,InpSignalTimeframe,1);
   double o2=iOpen(InpSymbol,InpSignalTimeframe,2);
   double c2=iClose(InpSymbol,InpSignalTimeframe,2);
   return (c2>o2 && c1<o1 && o1>=c2 && c1<=o2);
  }

bool BullishPinBar()
  {
   double o=iOpen(InpSymbol,InpSignalTimeframe,1);
   double c=iClose(InpSymbol,InpSignalTimeframe,1);
   double h=iHigh(InpSymbol,InpSignalTimeframe,1);
   double l=iLow(InpSymbol,InpSignalTimeframe,1);
   double body=MathAbs(c-o);
   double range=h-l;
   if(range<=0.0) return false;
   double lowerWick=MathMin(o,c)-l;
   double upperWick=h-MathMax(o,c);
   return (lowerWick>=body*2.0 && lowerWick>upperWick && c>l+range*0.55);
  }

bool BearishPinBar()
  {
   double o=iOpen(InpSymbol,InpSignalTimeframe,1);
   double c=iClose(InpSymbol,InpSignalTimeframe,1);
   double h=iHigh(InpSymbol,InpSignalTimeframe,1);
   double l=iLow(InpSymbol,InpSignalTimeframe,1);
   double body=MathAbs(c-o);
   double range=h-l;
   if(range<=0.0) return false;
   double upperWick=h-MathMax(o,c);
   double lowerWick=MathMin(o,c)-l;
   return (upperWick>=body*2.0 && upperWick>lowerWick && c<l+range*0.45);
  }

//+------------------------------------------------------------------+
//| Score confluence across independent technical-analysis categories.|
//+------------------------------------------------------------------+
void AnalyzeClosedCandle()
  {
   if(!IndicatorsReady())
     {
      Print("GOMEZ ALPHA BOT | WAIT | Indicator history is still loading.");
      return;
     }

   SIGNAL_DIRECTION signal=SIGNAL_WAIT;
   string reason="Evidence is mixed or below the required score";
   double closeM15=iClose(InpSymbol,InpSignalTimeframe,1);
   double closeH1=iClose(InpSymbol,InpTrendTimeframe,1);
   double m15Fast,m15Slow,h1Fast,h1Slow,rsi,macdMain,macdSignal,atr;
   double adx,plusDI,minusDI,basis,upperBand,lowerBand;

   if(closeM15<=0.0 || closeH1<=0.0 ||
      !ReadBufferValue(hM15FastEMA,0,1,m15Fast) ||
      !ReadBufferValue(hM15SlowEMA,0,1,m15Slow) ||
      !ReadBufferValue(hH1FastEMA,0,1,h1Fast) ||
      !ReadBufferValue(hH1SlowEMA,0,1,h1Slow) ||
      !ReadBufferValue(hRSI,0,1,rsi) ||
      !ReadBufferValue(hMACD,0,1,macdMain) ||
      !ReadBufferValue(hMACD,1,1,macdSignal) ||
      !ReadBufferValue(hATR,0,1,atr) ||
      !ReadBufferValue(hADX,0,1,adx) ||
      !ReadBufferValue(hADX,1,1,plusDI) ||
      !ReadBufferValue(hADX,2,1,minusDI) ||
      !ReadBufferValue(hBands,0,1,basis) ||
      !ReadBufferValue(hBands,1,1,upperBand) ||
      !ReadBufferValue(hBands,2,1,lowerBand) || atr<=0.0)
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

   bool h1Bullish=(h1Fast>h1Slow && closeH1>h1Slow);
   bool h1Bearish=(h1Fast<h1Slow && closeH1<h1Slow);
   bool m15Bullish=(m15Fast>m15Slow && closeM15>m15Fast);
   bool m15Bearish=(m15Fast<m15Slow && closeM15<m15Fast);
   bool momentumBullish=(rsi>=InpRSIBuyThreshold && macdMain>macdSignal);
   bool momentumBearish=(rsi<=InpRSISellThreshold && macdMain<macdSignal);
   bool adxBullish=(adx>=InpADXTrendThreshold && plusDI>minusDI);
   bool adxBearish=(adx>=InpADXTrendThreshold && minusDI>plusDI);
   bool candleBullish=(BullishEngulfing() || BullishPinBar());
   bool candleBearish=(BearishEngulfing() || BearishPinBar());
   bool bandBullish=(closeM15>basis && closeM15<upperBand);
   bool bandBearish=(closeM15<basis && closeM15>lowerBand);

   double roomToResistance=resistance-closeM15;
   double roomToSupport=closeM15-support;
   bool roomForBuy=(roomToResistance>atr*InpMinimumRoomATR);
   bool roomForSell=(roomToSupport>atr*InpMinimumRoomATR);

   int buyScore=0;
   int sellScore=0;
   if(h1Bullish) buyScore+=2;
   if(h1Bearish) sellScore+=2;
   if(m15Bullish) buyScore+=2;
   if(m15Bearish) sellScore+=2;
   if(momentumBullish) buyScore+=2;
   if(momentumBearish) sellScore+=2;
   if(adxBullish) buyScore++;
   if(adxBearish) sellScore++;
   if(candleBullish) buyScore++;
   if(candleBearish) sellScore++;
   if(bandBullish) buyScore++;
   if(bandBearish) sellScore++;
   if(roomForBuy) buyScore++;
   if(roomForSell) sellScore++;

   int maxScore=10;
   double buyConfidence=MathMin(100.0,100.0*buyScore/maxScore);
   double sellConfidence=MathMin(100.0,100.0*sellScore/maxScore);

   if(h1Bullish && m15Bullish && momentumBullish && roomForBuy &&
      buyScore>=InpMinimumScore && buyScore>sellScore)
     {
      signal=SIGNAL_BUY;
      reason="Bullish trend, momentum and structure confluence";
     }
   else if(h1Bearish && m15Bearish && momentumBearish && roomForSell &&
           sellScore>=InpMinimumScore && sellScore>buyScore)
     {
      signal=SIGNAL_SELL;
      reason="Bearish trend, momentum and structure confluence";
     }
   else if((h1Bullish && !roomForBuy) || (h1Bearish && !roomForSell))
      reason="Insufficient room before opposing support/resistance";
   else if(buyScore==sellScore)
      reason="Conflicting directional evidence; no clear advantage";

   MqlTick tick;
   double spreadPoints=-1.0;
   double symbolPoint=SymbolInfoDouble(InpSymbol,SYMBOL_POINT);
   bool tickAvailable=(SymbolInfoTick(InpSymbol,tick) &&
                       tick.ask>0.0 && tick.bid>0.0 &&
                       tick.ask>=tick.bid && symbolPoint>0.0);

   if(tickAvailable)
      spreadPoints=(tick.ask-tick.bid)/symbolPoint;
   else
     {
      signal=SIGNAL_WAIT;
      reason="Current bid/ask or symbol point unavailable";
     }

   if(tickAvailable && spreadPoints>InpMaximumSpreadPoints)
     {
      signal=SIGNAL_WAIT;
      reason="Spread exceeds configured analysis threshold";
     }

   int digits=(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS);
   double entryReference=closeM15;
   double stopReference=0.0;
   double targetReference=0.0;
   double rewardRisk=0.0;
   if(signal==SIGNAL_BUY)
     {
      stopReference=entryReference-(atr*InpStopATRMultiplier);
      targetReference=entryReference+(atr*InpTargetATRMultiplier);
      rewardRisk=(entryReference-stopReference>0.0 ?
                  (targetReference-entryReference)/(entryReference-stopReference):0.0);
     }
   else if(signal==SIGNAL_SELL)
     {
      stopReference=entryReference+(atr*InpStopATRMultiplier);
      targetReference=entryReference-(atr*InpTargetATRMultiplier);
      rewardRisk=(stopReference-entryReference>0.0 ?
                  (entryReference-targetReference)/(stopReference-entryReference):0.0);
     }

   if(signal!=SIGNAL_WAIT && rewardRisk<InpMinimumRewardRisk)
     {
      signal=SIGNAL_WAIT;
      reason="Illustrative reward/risk is below the configured minimum";
      stopReference=0.0;
      targetReference=0.0;
     }

   string report="GOMEZ ALPHA BOT v1.20\n";
   report+="MODE: ANALYSIS ONLY - NO ORDERS\n";
   report+="Signal: "+(signal==SIGNAL_BUY ? "BUY" : signal==SIGNAL_SELL ? "SELL" : "WAIT")+
           " | "+InpSymbol+"\n";
   report+="Closed candle: "+TimeToString(iTime(InpSymbol,InpSignalTimeframe,1),TIME_DATE|TIME_MINUTES)+"\n";
   report+="Timeframes: "+EnumToString(InpSignalTimeframe)+" setup / "+
           EnumToString(InpTrendTimeframe)+" trend\n";
   report+="Confluence score: BUY "+IntegerToString(buyScore)+"/"+IntegerToString(maxScore)+
           " ("+DoubleToString(buyConfidence,0)+"%) | SELL "+
           IntegerToString(sellScore)+"/"+IntegerToString(maxScore)+
           " ("+DoubleToString(sellConfidence,0)+"%)\n";
   report+="RSI: "+DoubleToString(rsi,2)+" | MACD: "+
           DoubleToString(macdMain,digits)+" / "+DoubleToString(macdSignal,digits)+
           " | ADX: "+DoubleToString(adx,2)+"\n";
   report+="H1 EMA50/200: "+DoubleToString(h1Fast,digits)+" / "+
           DoubleToString(h1Slow,digits)+" | M15 EMA50/200: "+
           DoubleToString(m15Fast,digits)+" / "+DoubleToString(m15Slow,digits)+"\n";
   report+="Bands upper/mid/lower: "+DoubleToString(upperBand,digits)+" / "+
           DoubleToString(basis,digits)+" / "+DoubleToString(lowerBand,digits)+"\n";
   report+="Support: "+DoubleToString(support,digits)+" | Resistance: "+
           DoubleToString(resistance,digits)+" | ATR: "+DoubleToString(atr,digits)+"\n";
   report+="Spread: "+DoubleToString(spreadPoints,1)+" points | Assessment: "+reason;

   if(signal!=SIGNAL_WAIT)
     {
      report+="\nEntry reference (closed-candle price): "+DoubleToString(entryReference,digits);
      report+="\nIllustrative SL: "+DoubleToString(stopReference,digits)+
              " | Illustrative TP: "+DoubleToString(targetReference,digits);
      report+=" | Reward/risk: 1:"+DoubleToString(rewardRisk,2);
      report+="\nPlan basis: trend + momentum + volatility + structure; confirm price live.";
     }
   else
      report+="\nNo trade plan issued: wait for clearer conditions.";

   report+="\nCandle pattern: "+string(candleBullish ? "Bullish" : candleBearish ? "Bearish" : "No defined pattern");
   report+="\nRisk notice: levels are analysis references, not broker orders or guarantees.";

   if(signal!=SIGNAL_WAIT || InpLogWaitSignals)
      Print(report);
   if(InpShowChartComment)
      Comment(report);
  }

//+------------------------------------------------------------------+
//| Initialize indicator handles and validate configuration.         |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(StringLen(InpSymbol)<1 || InpFastEMA<1 || InpSlowEMA<=InpFastEMA ||
      InpRSIPeriod<2 || InpMACDFast<1 || InpMACDSlow<=InpMACDFast ||
      InpMACDSignal<1 || InpATRPeriod<1 || InpADXPeriod<2 ||
      InpBandsPeriod<2 || InpBandsDeviation<=0.0 ||
      InpStructureLookback<10 || InpSwingStrength<1 || InpSwingStrength>10 ||
      InpRSISellThreshold<0.0 || InpRSIBuyThreshold>100.0 ||
      InpRSISellThreshold>=InpRSIBuyThreshold || InpADXTrendThreshold<0.0 ||
      InpStopATRMultiplier<=0.0 || InpTargetATRMultiplier<=0.0 ||
      InpMinimumRewardRisk<=0.0 || InpMinimumRoomATR<0.0 ||
      InpMaximumSpreadPoints<0 || InpMinimumScore<1 || InpMinimumScore>10)
     {
      Print("GOMEZ ALPHA BOT: Invalid input settings. Check the EA inputs.");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(!SymbolSelect(InpSymbol,true))
     {
      Print("GOMEZ ALPHA BOT: Could not select symbol ",InpSymbol,
            ". Check the broker's exact symbol name.");
      return INIT_FAILED;
     }

   hM15FastEMA=iMA(InpSymbol,InpSignalTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   hM15SlowEMA=iMA(InpSymbol,InpSignalTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hH1FastEMA=iMA(InpSymbol,InpTrendTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   hH1SlowEMA=iMA(InpSymbol,InpTrendTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hRSI=iRSI(InpSymbol,InpSignalTimeframe,InpRSIPeriod,PRICE_CLOSE);
   hMACD=iMACD(InpSymbol,InpSignalTimeframe,InpMACDFast,InpMACDSlow,InpMACDSignal,PRICE_CLOSE);
   hATR=iATR(InpSymbol,InpSignalTimeframe,InpATRPeriod);
   hADX=iADX(InpSymbol,InpSignalTimeframe,InpADXPeriod);
   hBands=iBands(InpSymbol,InpSignalTimeframe,InpBandsPeriod,0,InpBandsDeviation,PRICE_CLOSE);

   if(hM15FastEMA==INVALID_HANDLE || hM15SlowEMA==INVALID_HANDLE ||
      hH1FastEMA==INVALID_HANDLE || hH1SlowEMA==INVALID_HANDLE ||
      hRSI==INVALID_HANDLE || hMACD==INVALID_HANDLE || hATR==INVALID_HANDLE ||
      hADX==INVALID_HANDLE || hBands==INVALID_HANDLE)
     {
      Print("GOMEZ ALPHA BOT: Failed to initialize indicator handles. Error ",GetLastError());
      return INIT_FAILED;
     }

   Print("GOMEZ ALPHA BOT v1.20 initialized for ",InpSymbol,
         ". Multi-method analysis is active. Order execution is not implemented.");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Release indicator resources.                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hM15FastEMA!=INVALID_HANDLE) IndicatorRelease(hM15FastEMA);
   if(hM15SlowEMA!=INVALID_HANDLE) IndicatorRelease(hM15SlowEMA);
   if(hH1FastEMA!=INVALID_HANDLE) IndicatorRelease(hH1FastEMA);
   if(hH1SlowEMA!=INVALID_HANDLE) IndicatorRelease(hH1SlowEMA);
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hMACD!=INVALID_HANDLE) IndicatorRelease(hMACD);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
   if(hBands!=INVALID_HANDLE) IndicatorRelease(hBands);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Analyze a newly opened signal-timeframe candle after indicators are ready.       |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime currentBarTime=iTime(InpSymbol,InpSignalTimeframe,0);
   if(currentBarTime<=0 || currentBarTime==g_lastSignalBarTime)
      return;

   // Do not mark the candle as processed until indicator history is ready.
   // This allows a retry on later ticks instead of silently skipping the cycle.
   if(!IndicatorsReady())
     {
      if(g_lastReadinessNoticeBarTime!=currentBarTime)
        {
         Print("GOMEZ ALPHA BOT | WAIT | Indicator history is loading; will retry on later ticks.");
         g_lastReadinessNoticeBarTime=currentBarTime;
        }
      return;
     }

   g_lastSignalBarTime=currentBarTime;
   AnalyzeClosedCandle();
  }
//+------------------------------------------------------------------+
