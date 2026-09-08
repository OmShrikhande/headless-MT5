//+------------------------------------------------------------------+
//|                                                 MyCustomEA.mq5   |
//|                                  Copyright 2026, Headless MT5    |
//|                                             https://mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Headless MT5"
#property link      "https://mql5.com"
#property version   "1.10"
#property description "Alternating 1-Minute Buy/Sell EA for XAUUSD"

#include <Trade\Trade.mqh>

// Inputs
input string TradeSymbol   = "XAUUSD";  // Symbol to trade
input double TargetLotSize = 0.01;      // Trade Lot Size
input ulong  MagicNumber   = 123456;    // EA Magic Number

// Global Objects & Variables
CTrade   trade;
bool     is_buy_next       = true;   // Alternates: true = BUY, false = SELL
datetime last_trade_minute = 0;      // Tracks last processed minute timestamp

//+------------------------------------------------------------------+
//| Close existing open positions for target symbol & magic number   |
//+------------------------------------------------------------------+
void CloseExistingPositions(string symbol, ulong magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == magic)
           {
            PrintFormat("[MyCustomEA] Closing position #%I64u on %s", ticket, symbol);
            if(!trade.PositionClose(ticket))
              {
               PrintFormat("[MyCustomEA] Failed to close position #%I64u. Error: %u", ticket, trade.ResultRetcode());
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Execute alternating 1-minute trade cycle                         |
//+------------------------------------------------------------------+
void ExecuteTradeCycle()
  {
   string symbol = (TradeSymbol != "" && TradeSymbol != "CURRENT") ? TradeSymbol : _Symbol;
   
   // Select target symbol in Market Watch if not already active
   SymbolSelect(symbol, true);
   
   // 1. Close any existing open positions opened by this EA
   CloseExistingPositions(symbol, MagicNumber);
   
   // 2. Open new position (BUY vs SELL alternating)
   if(is_buy_next)
     {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      PrintFormat("[MyCustomEA] Cycle: Placing BUY trade on %s at Ask: %.2f (Lot: %.2f)", symbol, ask, TargetLotSize);
      
      if(trade.Buy(TargetLotSize, symbol, ask, 0, 0, "Headless MT5 Buy Cycle"))
        {
         PrintFormat("[MyCustomEA] ✅ BUY order executed successfully. Ticket: %I64u", trade.ResultOrder());
        }
      else
        {
         PrintFormat("[MyCustomEA] ❌ BUY order failed. Retcode: %u", trade.ResultRetcode());
        }
      is_buy_next = false; // Next 1-min cycle will SELL
     }
   else
     {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      PrintFormat("[MyCustomEA] Cycle: Placing SELL trade on %s at Bid: %.2f (Lot: %.2f)", symbol, bid, TargetLotSize);
      
      if(trade.Sell(TargetLotSize, symbol, bid, 0, 0, "Headless MT5 Sell Cycle"))
        {
         PrintFormat("[MyCustomEA] ✅ SELL order executed successfully. Ticket: %I64u", trade.ResultOrder());
        }
      else
        {
         PrintFormat("[MyCustomEA] ❌ SELL order failed. Retcode: %u", trade.ResultRetcode());
        }
      is_buy_next = true; // Next 1-min cycle will BUY
     }
  }

//+------------------------------------------------------------------+
//| Helper to evaluate 1-minute cycle boundary                        |
//+------------------------------------------------------------------+
void CheckMinuteCycle()
  {
   datetime current_time = TimeCurrent();
   if(current_time <= 0) return;
   
   datetime current_minute = current_time / 60;
   
   if(last_trade_minute == 0)
     {
      // First run: mark current minute and execute initial trade
      last_trade_minute = current_minute;
      ExecuteTradeCycle();
     }
   else if(current_minute > last_trade_minute)
     {
      // New 1-minute interval reached
      last_trade_minute = current_minute;
      ExecuteTradeCycle();
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   string symbol = (TradeSymbol != "" && TradeSymbol != "CURRENT") ? TradeSymbol : _Symbol;
   SymbolSelect(symbol, true);
   
   trade.SetExpertMagicNumber(MagicNumber);
   
   PrintFormat("[MyCustomEA] Initializing Alternating 1-Min EA on %s...", symbol);
   PrintFormat("[MyCustomEA] Account #%d | Server: %s | Company: %s", 
               AccountInfoInteger(ACCOUNT_LOGIN), 
               AccountInfoString(ACCOUNT_SERVER), 
               AccountInfoString(ACCOUNT_COMPANY));

   // Set timer to check every second for minute boundary changes
   EventSetTimer(1);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   PrintFormat("[MyCustomEA] Deinitializing EA. Reason code: %d", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckMinuteCycle();
  }

//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
void OnTimer()
  {
   static datetime last_heartbeat = 0;
   datetime current_time = TimeCurrent();
   
   CheckMinuteCycle();

   // Periodic heartbeat every 30 seconds
   if(current_time - last_heartbeat >= 30)
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      PrintFormat("[MyCustomEA] [Heartbeat] Balance: %.2f | Equity: %.2f | Open Positions: %d | Next Action: %s", 
                  balance, equity, PositionsTotal(), is_buy_next ? "BUY" : "SELL");
      last_heartbeat = current_time;
     }
  }
//+------------------------------------------------------------------+

