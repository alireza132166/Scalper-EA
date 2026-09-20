//+------------------------------------------------------------------+
//|                                      Simple_Scalper_Optimized.mq5|
//+------------------------------------------------------------------+
#property copyright "Alire"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

input group "=== تنظیمات کلی ==="
input double   LotSize         = 0.01;
input int      InpMagicNumber  = 88888;
input int      InpMaxTrades    = 1;
input int      InpSlippage     = 30;

input group "=== استراتژی ==="
input int      InpEMA_Fast     = 5;
input int      InpEMA_Slow     = 13;
input int      InpRSI_Period   = 7;
input int      InpRSI_BuyLevel = 50;
input int      InpRSI_SellLevel= 50;

input group "=== حد ضرر و سود ==="
input int      InpATR_Period   = 14;
input double   InpATR_SL_Mult  = 1.5;
input double   InpRR_Ratio     = 1.5;

input group "=== فیلترها ==="
input int      InpMaxSpread    = 30;
input int      InpTicksBetween = 3;

//--- Global Variables
CTrade         trade;
int            handleEMA_Fast;
int            handleEMA_Slow;
int            handleRSI;
int            handleATR;
int            tickCounter;
int            totalOrders;
int            totalErrors;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   
   handleEMA_Fast = iMA(_Symbol, PERIOD_M1, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(_Symbol, PERIOD_M1, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, PERIOD_M1, InpRSI_Period, PRICE_CLOSE);
   handleATR = iATR(_Symbol, PERIOD_M1, InpATR_Period);
   
   if(handleEMA_Fast == INVALID_HANDLE || handleEMA_Slow == INVALID_HANDLE || 
      handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("ERROR: Indicator creation failed!");
      return INIT_FAILED;
   }
   
   tickCounter = 0;
   totalOrders = 0;
   totalErrors = 0;
   
   Print("=== Simple Scalper v2.0 ===");
   Print("EMA: ", InpEMA_Fast, "/", InpEMA_Slow, " | RSI: ", InpRSI_Period);
   Print("SL: ATR*", DoubleToString(InpATR_SL_Mult, 1), " | RR: 1:", DoubleToString(InpRR_Ratio, 1));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMA_Fast != INVALID_HANDLE) IndicatorRelease(handleEMA_Fast);
   if(handleEMA_Slow != INVALID_HANDLE) IndicatorRelease(handleEMA_Slow);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   Print("=== Orders: ", totalOrders, " | Errors: ", totalErrors, " ===");
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(CountPositions() >= InpMaxTrades)
      return;
   
   tickCounter++;
   if(tickCounter < InpTicksBetween)
      return;
   
   tickCounter = 0;
   
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
      return;
   
   AnalyzeMarket();
}

//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
bool CheckFreeMargin(double lots)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double reqMargin = 0;
   
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, SymbolInfoDouble(_Symbol, SYMBOL_ASK), reqMargin))
      return true;
   
   if(reqMargin == 0)
      return true;
   
   if(freeMargin < reqMargin * 1.5)
   {
      Print("ERROR: Low margin. Free=", DoubleToString(freeMargin, 2));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
int GetMinSLDistance()
{
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   int minDist = MathMax(stopsLevel, freezeLevel);
   if(minDist < 10) minDist = 10;
   return minDist;
}

//+------------------------------------------------------------------+
void AnalyzeMarket()
{
   double emaFast[], emaSlow[], rsi[], atr[];
   
   if(CopyBuffer(handleEMA_Fast, 0, 0, 3, emaFast) < 3) return;
   if(CopyBuffer(handleEMA_Slow, 0, 0, 3, emaSlow) < 3) return;
   if(CopyBuffer(handleRSI, 0, 0, 3, rsi) < 3) return;
   if(CopyBuffer(handleATR, 0, 0, 1, atr) < 1) return;
   
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double close1 = iClose(_Symbol, PERIOD_M1, 1);
   
   if(ask == 0 || bid == 0 || atr[0] <= 0) return;
   
   double slDist = atr[0] * InpATR_SL_Mult;
   double tpDist = slDist * InpRR_Ratio;
   
   int minSL = GetMinSLDistance() * _Point;
   if(slDist < minSL)
   {
      slDist = minSL;
      tpDist = slDist * InpRR_Ratio;
   }
   
   bool emaFastUp = emaFast[0] > emaSlow[0];
   bool emaFastDown = emaFast[0] < emaSlow[0];
   bool priceAboveFast = close1 > emaFast[0];
   bool priceBelowFast = close1 < emaFast[0];
   bool rsiBuy = rsi[0] > InpRSI_BuyLevel;
   bool rsiSell = rsi[0] < InpRSI_SellLevel;
   
   Print("DEBUG: EMA=", (emaFastUp ? "UP" : "DOWN"),
         " RSI=", DoubleToString(rsi[0], 1),
         " ATR=", DoubleToString(atr[0], _Digits));
   
   if(emaFastUp && priceAboveFast && rsiBuy)
   {
      Print("SIGNAL: BUY");
      ExecuteBuy(ask, slDist, tpDist);
   }
   else if(emaFastDown && priceBelowFast && rsiSell)
   {
      Print("SIGNAL: SELL");
      ExecuteSell(bid, slDist, tpDist);
   }
}

//+------------------------------------------------------------------+
void ExecuteBuy(double ask, double slDist, double tpDist)
{
   double sl = NormalizeDouble(ask - slDist, _Digits);
   double tp = NormalizeDouble(ask + tpDist, _Digits);
   
   if(!CheckFreeMargin(LotSize))
   {
      totalErrors++;
      return;
   }
   
   Print("BUY: Ask=", DoubleToString(ask, _Digits),
         " SL=", DoubleToString(sl, _Digits),
         " TP=", DoubleToString(tp, _Digits));
   
   if(trade.Buy(LotSize, _Symbol, 0, sl, tp, "Scalper Buy"))
   {
      totalOrders++;
      Print("SUCCESS Buy: Ticket=", trade.ResultOrder());
   }
   else
   {
      totalErrors++;
      Print("ERROR Buy: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
void ExecuteSell(double bid, double slDist, double tpDist)
{
   double sl = NormalizeDouble(bid + slDist, _Digits);
   double tp = NormalizeDouble(bid - tpDist, _Digits);
   
   if(!CheckFreeMargin(LotSize))
   {
      totalErrors++;
      return;
   }
   
   Print("SELL: Bid=", DoubleToString(bid, _Digits),
         " SL=", DoubleToString(sl, _Digits),
         " TP=", DoubleToString(tp, _Digits));
   
   if(trade.Sell(LotSize, _Symbol, 0, sl, tp, "Scalper Sell"))
   {
      totalOrders++;
      Print("SUCCESS Sell: Ticket=", trade.ResultOrder());
   }
   else
   {
      totalErrors++;
      Print("ERROR Sell: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}
//+------------------------------------------------------------------+
