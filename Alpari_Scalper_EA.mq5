//+------------------------------------------------------------------+
//|                                    Alpari_Gold_Scalper_EA.mq5    |
//|                                    Scalping Expert Advisor Gold   |
//+------------------------------------------------------------------+
#property copyright "Alpari Gold Scalper EA"
#property version   "1.08"
#property strict

#include <Trade\Trade.mqh>

input group "=== تنظیمات کلی ==="
input int      InpMaxTrades       = 3;
input double   InpRiskPercent     = 2.0;
input double   InpRiskReward      = 2.0;
input int      InpMagicNumber     = 123456;

input group "=== تنظیمات ترند ==="
input int      InpFastMA          = 8;
input int      InpSlowMA          = 21;
input int      InpATRPeriod       = 14;

input group "=== تنظیمات ورود ==="
input int      InpSlippage        = 30;
input int      InpTicksBetween    = 3;
input double   InpATRMultiplier   = 1.0;

input group "=== زمان معاملات ==="
input int      InpStartHour       = 0;
input int      InpEndHour         = 24;

//--- Global Variables
CTrade         trade;
int            handleFastMA;
int            handleSlowMA;
int            handleATR;
int            openTradeCount;
int            currentDirection;
int            tickCounter;
int            totalOrders;
int            totalErrors;
datetime       lastTradeTime;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   
   handleFastMA = iMA(_Symbol, PERIOD_M1, InpFastMA, 0, MODE_EMA, PRICE_CLOSE);
   handleSlowMA = iMA(_Symbol, PERIOD_M1, InpSlowMA, 0, MODE_EMA, PRICE_CLOSE);
   handleATR = iATR(_Symbol, PERIOD_M1, InpATRPeriod);
   
   if(handleFastMA == INVALID_HANDLE || handleSlowMA == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicators!");
      return INIT_FAILED;
   }
   
   openTradeCount = 0;
   currentDirection = 0;
   tickCounter = 0;
   totalOrders = 0;
   totalErrors = 0;
   lastTradeTime = 0;
   
   Print("=== Alpari Gold Scalper v1.08 ===");
   Print("Symbol: ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleFastMA != INVALID_HANDLE) IndicatorRelease(handleFastMA);
   if(handleSlowMA != INVALID_HANDLE) IndicatorRelease(handleSlowMA);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   Print("=== Orders: ", totalOrders, " | Errors: ", totalErrors, " ===");
}

//+------------------------------------------------------------------+
void OnTick()
{
   CountOpenTrades();
   
   if(openTradeCount >= InpMaxTrades)
      return;
   
   tickCounter++;
   
   if(tickCounter < InpTicksBetween)
      return;
   
   tickCounter = 0;
   AnalyzeMarket();
}

//+------------------------------------------------------------------+
void CountOpenTrades()
{
   openTradeCount = 0;
   currentDirection = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
               openTradeCount++;
               long posType = PositionGetInteger(POSITION_TYPE);
               if(posType == POSITION_TYPE_BUY)
                  currentDirection = 1;
               else if(posType == POSITION_TYPE_SELL)
                  currentDirection = -1;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
int GetMinSLDistance()
{
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   int minDistance = MathMax(stopsLevel, freezeLevel);
   if(minDistance < 10)
      minDistance = 10;
   return minDistance;
}

//+------------------------------------------------------------------+
void AnalyzeMarket()
{
   double fastMA[], slowMA[], atr[];
   
   if(CopyBuffer(handleFastMA, 0, 0, 3, fastMA) < 3) return;
   if(CopyBuffer(handleSlowMA, 0, 0, 3, slowMA) < 3) return;
   if(CopyBuffer(handleATR, 0, 0, 1, atr) < 1) return;
   
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(ask == 0 || bid == 0) return;
   if(atr[0] <= 0) return;
   
   double slDistance = atr[0] * InpATRMultiplier;
   double tpDistance = slDistance * InpRiskReward;
   
   int minSLPoints = GetMinSLDistance();
   double minSLPrice = minSLPoints * _Point;
   
   if(slDistance < minSLPrice)
   {
      slDistance = minSLPrice;
      tpDistance = slDistance * InpRiskReward;
   }
   
   bool fastAboveSlow = fastMA[0] > slowMA[0];
   bool fastBelowSlow = fastMA[0] < slowMA[0];
   
   bool allowTrade = (TimeCurrent() - lastTradeTime > 10);
   
   string dirStr = "NONE";
   if(currentDirection == 1) dirStr = "BUY";
   if(currentDirection == -1) dirStr = "SELL";
   
   Print("DEBUG: Dir=", dirStr,
         " Fast=", DoubleToString(fastMA[0], _Digits),
         " Slow=", DoubleToString(slowMA[0], _Digits),
         " Trades=", openTradeCount);
   
   if(fastAboveSlow && allowTrade)
   {
      if(currentDirection == 0 || currentDirection == 1)
      {
         Print("SIGNAL: BUY");
         ExecuteBuy(ask, slDistance, tpDistance);
      }
   }
   else if(fastBelowSlow && allowTrade)
   {
      if(currentDirection == 0 || currentDirection == -1)
      {
         Print("SIGNAL: SELL");
         ExecuteSell(bid, slDistance, tpDistance);
      }
   }
}

//+------------------------------------------------------------------+
void ExecuteBuy(double ask, double slDist, double tpDist)
{
   double sl = NormalizeDouble(ask - slDist, _Digits);
   double tp = NormalizeDouble(ask + tpDist, _Digits);
   
   double lots = CalculateLotSize(slDist);
   if(lots <= 0)
   {
      totalErrors++;
      return;
   }
   
   Print("BUY: Price=", DoubleToString(ask, _Digits),
         " SL=", DoubleToString(sl, _Digits),
         " TP=", DoubleToString(tp, _Digits),
         " Lots=", DoubleToString(lots, 2));
   
   if(trade.Buy(lots, _Symbol, 0, sl, tp, "Scalper Buy"))
   {
      lastTradeTime = TimeCurrent();
      currentDirection = 1;
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
   
   double lots = CalculateLotSize(slDist);
   if(lots <= 0)
   {
      totalErrors++;
      return;
   }
   
   Print("SELL: Price=", DoubleToString(bid, _Digits),
         " SL=", DoubleToString(sl, _Digits),
         " TP=", DoubleToString(tp, _Digits),
         " Lots=", DoubleToString(lots, 2));
   
   if(trade.Sell(lots, _Symbol, 0, sl, tp, "Scalper Sell"))
   {
      lastTradeTime = TimeCurrent();
      currentDirection = -1;
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
double CalculateLotSize(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue == 0 || tickSize == 0 || slDistance == 0)
      return 0;
   
   double lots = riskAmount / (slDistance / tickSize * tickValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lotStep > 0)
      lots = MathFloor(lots / lotStep) * lotStep;
   
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   
   return lots;
}
//+------------------------------------------------------------------+
