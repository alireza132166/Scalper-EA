//+------------------------------------------------------------------+
//|                                        Quick_Scalper_10.mq5      |
//|                                        10 Trade Basket Scalper    |
//+------------------------------------------------------------------+
#property copyright "gg"
#property version   "7.00"
#property strict

#include <Trade\Trade.mqh>

input group "=== تنظیمات کلی ==="
input double   LotSize          = 0.01;
input int      InpMagicNumber   = 99999;
input int      InpMaxTrades     = 10;
input int      InpSlippage      = 30;

input group "=== حد ضرر و سود ==="
input int      InpSL_Pips       = 10;
input double   InpTradeTP_Pips  = 3.0;
input double   InpBasketTP      = 25.0;
input double   InpBasketSL      = 50.0;

input group "=== فیلترها ==="
input int      InpMaxSpread     = 30;

//--- Global Variables
CTrade         trade;
int            totalOrders;
int            totalCycles;
double         totalProfit;
datetime       cycleStart;
int            tradesOpened;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   
   totalOrders = 0;
   totalCycles = 0;
   totalProfit = 0;
   cycleStart = 0;
   tradesOpened = 0;
   
   Print("=== Quick Scalper 10 v7.0 ===");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== Cycles: ", totalCycles, " | Orders: ", totalOrders, " | Profit: $", DoubleToString(totalProfit, 2), " ===");
}

//+------------------------------------------------------------------+
void OnTick()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
      return;
   
   int posCount = CountPositions();
   double basketProfit = CalculateBasketProfit();
   
   if(posCount > 0)
   {
      ManageBasket(basketProfit, posCount);
      return;
   }
   
   TryOpenCycle();
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
int GetCandleDirection()
{
   double close1 = iClose(_Symbol, PERIOD_M1, 1);
   double close2 = iClose(_Symbol, PERIOD_M1, 2);
   
   if(close1 > close2) return 1;
   if(close1 < close2) return -1;
   return 0;
}

//+------------------------------------------------------------------+
void ManageBasket(double basketProfit, int posCount)
{
   int candleDir = GetCandleDirection();
   int basketDir = GetBasketDirection();
   
   Print("BASKET: $", DoubleToString(basketProfit, 2),
         " | Pos: ", posCount,
         " | Candle: ", (candleDir == 1 ? "UP" : "DOWN"),
         " | Basket: ", (basketDir == 1 ? "BUY" : "SELL"));
   
   if(basketProfit >= InpBasketTP)
   {
      Print("=== BASKET TP! Profit: $", DoubleToString(basketProfit, 2), " ===");
      CloseAll();
      totalProfit += basketProfit;
      return;
   }
   
   if(basketProfit <= -InpBasketSL)
   {
      Print("=== BASKET SL! Loss: $", DoubleToString(basketProfit, 2), " ===");
      CloseAll();
      totalProfit += basketProfit;
      return;
   }
   
   if(posCount >= InpMaxTrades)
      return;
   
   if(candleDir != 0 && candleDir != basketDir)
   {
      Print("=== REVERSAL! Closing all ===");
      CloseAll();
      return;
   }
   
   if(candleDir == basketDir)
   {
      if(candleDir == 1)
      {
         Print("ADD: BUY (candle UP)");
         OpenSingle(ORDER_TYPE_BUY);
      }
      else
      {
         Print("ADD: SELL (candle DOWN)");
         OpenSingle(ORDER_TYPE_SELL);
      }
   }
}

//+------------------------------------------------------------------+
int GetBasketDirection()
{
   double buyLots = 0, sellLots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            double vol = PositionGetDouble(POSITION_VOLUME);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               buyLots += vol;
            else
               sellLots += vol;
         }
      }
   }
   
   if(buyLots > sellLots) return 1;
   if(sellLots > buyLots) return -1;
   return 0;
}

//+------------------------------------------------------------------+
void TryOpenCycle()
{
   int candleDir = GetCandleDirection();
   
   Print("DEBUG: Close[1]=", DoubleToString(iClose(_Symbol, PERIOD_M1, 1), _Digits),
         " Close[2]=", DoubleToString(iClose(_Symbol, PERIOD_M1, 2), _Digits),
         " Dir=", (candleDir == 1 ? "UP" : "DOWN"));
   
   if(candleDir == 0)
      return;
   
   double slPips = InpSL_Pips;
   
   tradesOpened = 0;
   
   string dirStr = (candleDir == 1) ? "BUY" : "SELL";
   Print("=== NEW ", dirStr, " CYCLE ===");
   
   for(int i = 0; i < InpMaxTrades; i++)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      double sl = 0;
      double tp = 0;
      
      if(candleDir == 1)
      {
         sl = NormalizeDouble(ask - slPips * _Point * 10, _Digits);
         tp = NormalizeDouble(ask + InpTradeTP_Pips * _Point * 10, _Digits);
         
         if(!trade.Buy(LotSize, _Symbol, 0, sl, tp, "Basket Buy"))
         {
            Print("ERROR: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
         }
      }
      else
      {
         sl = NormalizeDouble(bid + slPips * _Point * 10, _Digits);
         tp = NormalizeDouble(bid - InpTradeTP_Pips * _Point * 10, _Digits);
         
         if(!trade.Sell(LotSize, _Symbol, 0, sl, tp, "Basket Sell"))
         {
            Print("ERROR: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
         }
      }
      
      tradesOpened++;
      totalOrders++;
   }
   
   cycleStart = TimeCurrent();
   totalCycles++;
}

//+------------------------------------------------------------------+
void OpenSingle(ENUM_ORDER_TYPE orderType)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double sl = 0;
   double tp = 0;
   
   if(orderType == ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(ask - InpSL_Pips * _Point * 10, _Digits);
      tp = NormalizeDouble(ask + InpTradeTP_Pips * _Point * 10, _Digits);
   }
   else
   {
      sl = NormalizeDouble(bid + InpSL_Pips * _Point * 10, _Digits);
      tp = NormalizeDouble(bid - InpTradeTP_Pips * _Point * 10, _Digits);
   }
   
   bool result = false;
   if(orderType == ORDER_TYPE_BUY)
      result = trade.Buy(LotSize, _Symbol, 0, sl, tp, "Basket Add");
   else
      result = trade.Sell(LotSize, _Symbol, 0, sl, tp, "Basket Add");
   
   if(result)
   {
      tradesOpened++;
      totalOrders++;
      Print("Add #", tradesOpened, ": ", EnumToString(orderType));
   }
}

//+------------------------------------------------------------------+
void CloseAll()
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
