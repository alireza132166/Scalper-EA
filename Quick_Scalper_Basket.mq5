//+------------------------------------------------------------------+
//|                                      Quick_Scalper_Basket.mq5    |
//|                                      Basket Scalping Strategy     |
//+------------------------------------------------------------------+
#property copyright "gg"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>

input group "=== تنظیمات کلی ==="
input double   LotSize          = 0.01;
input int      InpMagicNumber   = 77777;
input int      InpMaxTrades     = 5;
input int      InpSlippage      = 30;

input group "=== استراتژی ==="
input int      InpEMA_Fast      = 5;
input int      InpEMA_Slow      = 13;
input int      InpRSI_Period    = 7;
input int      InpRSI_BuyLevel  = 45;
input int      InpRSI_SellLevel = 55;

input group "=== سبد معاملات ==="
input double   InpBasketTP      = 5.0;       // حد سود سبد (دلار)
input double   InpBasketSL      = 20.0;      // حد ضرر سبد (دلار)
input int      InpMaxWaitSeconds = 60;        // حداکثر انتظار (ثانیه)

input group "=== فیلترها ==="
input int      InpMaxSpread     = 25;
input int      InpTicksBetween  = 1;

//--- Global Variables
CTrade         trade;
int            handleEMA_Fast;
int            handleEMA_Slow;
int            handleRSI;
int            tickCounter;
int            totalOrders;
int            totalClosed;
double         totalProfit;
datetime       basketStartTime;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   
   handleEMA_Fast = iMA(_Symbol, PERIOD_M1, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(_Symbol, PERIOD_M1, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, PERIOD_M1, InpRSI_Period, PRICE_CLOSE);
   
   if(handleEMA_Fast == INVALID_HANDLE || handleEMA_Slow == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
   {
      Print("ERROR: Indicators failed!");
      return INIT_FAILED;
   }
   
   tickCounter = 0;
   totalOrders = 0;
   totalClosed = 0;
   totalProfit = 0;
   basketStartTime = 0;
   
   Print("=== Quick Scalper Basket v3.0 ===");
   Print("MaxTrades: ", InpMaxTrades, " | BasketTP: $", InpBasketTP, " | BasketSL: $", InpBasketSL);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMA_Fast != INVALID_HANDLE) IndicatorRelease(handleEMA_Fast);
   if(handleEMA_Slow != INVALID_HANDLE) IndicatorRelease(handleEMA_Slow);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   Print("=== Orders: ", totalOrders, " | Closed: ", totalClosed, " | Profit: $", DoubleToString(totalProfit, 2), " ===");
}

//+------------------------------------------------------------------+
void OnTick()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
      return;
   
   double basketProfit = CalculateBasketProfit();
   
   if(CountPositions() > 0)
   {
      ManageBasket(basketProfit);
      return;
   }
   
   tickCounter++;
   if(tickCounter < InpTicksBetween)
      return;
   
   tickCounter = 0;
   OpenNewCycle();
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
double CalculateBasketProfit()
{
   double profit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         }
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
void ManageBasket(double basketProfit)
{
   int posCount = CountPositions();
   double elapsed = TimeCurrent() - basketStartTime;
   
   Print("BASKET: Profit=$", DoubleToString(basketProfit, 2),
         " | Positions=", posCount,
         " | Time=", (int)elapsed, "s");
   
   if(basketProfit >= InpBasketTP)
   {
      Print(">>> BASKET TP HIT! Closing all with profit: $", DoubleToString(basketProfit, 2));
      CloseAllPositions();
      totalProfit += basketProfit;
      totalClosed++;
      return;
   }
   
   if(basketProfit <= -InpBasketSL)
   {
      Print(">>> BASKET SL HIT! Closing all with loss: $", DoubleToString(basketProfit, 2));
      CloseAllPositions();
      totalProfit += basketProfit;
      totalClosed++;
      return;
   }
   
   if(elapsed >= InpMaxWaitSeconds && basketProfit > 0)
   {
      Print(">>> TIMEOUT with profit! Closing: $", DoubleToString(basketProfit, 2));
      CloseAllPositions();
      totalProfit += basketProfit;
      totalClosed++;
      return;
   }
   
   if(posCount < InpMaxTrades)
   {
      AddToBasket();
   }
}

//+------------------------------------------------------------------+
void OpenNewCycle()
{
   double emaFast[], emaSlow[], rsi[];
   
   if(CopyBuffer(handleEMA_Fast, 0, 0, 2, emaFast) < 2) return;
   if(CopyBuffer(handleEMA_Slow, 0, 0, 2, emaSlow) < 2) return;
   if(CopyBuffer(handleRSI, 0, 0, 2, rsi) < 2) return;
   
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);
   
   bool emaUp = emaFast[0] > emaSlow[0];
   bool emaDown = emaFast[0] < emaSlow[0];
   
   if(emaUp && rsi[0] < InpRSI_BuyLevel)
   {
      Print("NEW CYCLE: BUY");
      OpenBasketTrade(ORDER_TYPE_BUY);
   }
   else if(emaDown && rsi[0] > InpRSI_SellLevel)
   {
      Print("NEW CYCLE: SELL");
      OpenBasketTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
void AddToBasket()
{
   double emaFast[], emaSlow[], rsi[];
   
   if(CopyBuffer(handleEMA_Fast, 0, 0, 1, emaFast) < 1) return;
   if(CopyBuffer(handleEMA_Slow, 0, 0, 1, emaSlow) < 1) return;
   if(CopyBuffer(handleRSI, 0, 0, 1, rsi) < 1) return;
   
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);
   
   long lastDirection = GetLastTradeDirection();
   
   bool emaUp = emaFast[0] > emaSlow[0];
   bool emaDown = emaFast[0] < emaSlow[0];
   
   if(emaUp && rsi[0] < InpRSI_BuyLevel && lastDirection != POSITION_TYPE_BUY)
   {
      Print("ADD: BUY");
      OpenBasketTrade(ORDER_TYPE_BUY);
   }
   else if(emaDown && rsi[0] > InpRSI_SellLevel && lastDirection != POSITION_TYPE_SELL)
   {
      Print("ADD: SELL");
      OpenBasketTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
long GetLastTradeDirection()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            return PositionGetInteger(POSITION_TYPE);
         }
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
void OpenBasketTrade(ENUM_ORDER_TYPE orderType)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
   double sl = 0;
   double tp = 0;
   
   if(CountPositions() == 0)
      basketStartTime = TimeCurrent();
   
   string comment = "Basket " + EnumToString(orderType);
   
   bool result = false;
   if(orderType == ORDER_TYPE_BUY)
      result = trade.Buy(LotSize, _Symbol, 0, sl, tp, comment);
   else
      result = trade.Sell(LotSize, _Symbol, 0, sl, tp, comment);
   
   if(result)
   {
      totalOrders++;
      Print("SUCCESS: ", EnumToString(orderType), " Ticket=", trade.ResultOrder());
   }
   else
   {
      Print("ERROR: ", EnumToString(orderType), " ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            trade.PositionClose(ticket);
         }
      }
   }
}
//+------------------------------------------------------------------+
