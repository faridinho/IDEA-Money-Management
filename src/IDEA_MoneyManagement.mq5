//+------------------------------------------------------------------+
//|                                       IDEA_MoneyManagement.mq5   |
//|                                Copyright 2024, Omran IDEA         |
//|                                         https://omranidea.com     |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2024, Omran IDEA"
#property link        "https://omranidea.com"
#property version     "1.00"
#property description "Professional money management EA with line-based entry,"
#property description "risk-based lot sizing, risk-free/break-even automation,"
#property description "partial close, and on-chart control panel."
#property strict

//--- Standard library includes
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+

enum ENUM_LOT_MODE
{
   LOT_FIXED         = 0,   // Fixed Lot
   LOT_RISK_PERCENT  = 1,   // Risk % of Balance
   LOT_BALANCE_PCT   = 2,   // % of Balance as Lot
};

enum ENUM_SLTP_MODE
{
   SLTP_LINE_BASED   = 0,   // Line-Based (drag lines on chart)
   SLTP_FIXED_PIPS   = 1,   // Fixed Pips
};

enum ENUM_RISKFREE_MODE
{
   RF_DISABLED       = 0,   // Disabled
   RF_BREAK_EVEN     = 1,   // Break-Even (move SL to entry)
   RF_RISK_FREE      = 2,   // Risk-Free (move SL to entry + offset)
};

enum ENUM_TRADE_DIRECTION
{
   DIR_BUY           = 0,   // Buy
   DIR_SELL          = 1,   // Sell
};

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

//--- Risk & Lot Sizing
input group "=== Risk & Lot Sizing ==="
input ENUM_LOT_MODE  InpLotMode            = LOT_RISK_PERCENT; // Lot Size Mode
input double         InpRiskPercent        = 1.0;              // Risk % per Trade
input double         InpFixedLot           = 0.01;             // Fixed Lot (if LOT_FIXED)
input double         InpBalanceLotPct      = 1.0;              // Balance % as Lot (if LOT_BALANCE_PCT)

//--- Stop Loss & Take Profit
input group "=== Stop Loss & Take Profit ==="
input ENUM_SLTP_MODE InpSLTPMode           = SLTP_LINE_BASED;  // SL/TP Mode
input int            InpFixedSLPips        = 50;               // Fixed SL (pips, if SLTP_FIXED_PIPS)
input int            InpFixedTPPips        = 100;              // Fixed TP (pips, if SLTP_FIXED_PIPS)

//--- Risk-Free & Break-Even
input group "=== Risk-Free / Break-Even ==="
input ENUM_RISKFREE_MODE InpRiskFreeMode   = RF_DISABLED;      // Risk-Free Mode
input double         InpBETriggerPct       = 50.0;             // Break-Even Trigger (% of TP reached)
input int            InpBEOffsetPips       = 1;                // Break-Even Offset (pips above entry)
input double         InpRFTriggerPct       = 60.0;             // Risk-Free Trigger (% of TP reached)
input int            InpRFOffsetPips       = 5;                // Risk-Free Offset (pips above entry)

//--- Partial Close
input group "=== Partial Close ==="
input bool           InpEnablePartialClose = false;            // Enable Partial Close
input double         InpPartialTriggerPct  = 50.0;             // Partial Close Trigger (% of TP)
input double         InpPartialClosePct    = 50.0;             // Volume to Close (%)

//--- Max Daily Loss Protection
input group "=== Daily Loss Protection ==="
input bool           InpEnableDailyLimit   = false;            // Enable Max Daily Loss
input double         InpMaxDailyLossPct    = 3.0;              // Max Daily Loss (% of Balance)
input double         InpMaxDailyLossUSD    = 0.0;              // Max Daily Loss (USD, 0 = ignore)

//--- Trade Settings
input group "=== Trade Settings ==="
input int            InpMagicNumber        = 202400;           // Magic Number
input int            InpSlippage           = 10;               // Slippage (points)
input string         InpTradeComment       = "IDEA-MM";        // Trade Comment

//--- Visual / Panel
input group "=== Visual Settings ==="
input bool           InpShowPanel          = true;             // Show Control Panel
input color          InpEntryLineColor     = clrDodgerBlue;    // Entry Line Color
input color          InpSLLineColor        = clrRed;           // Stop Loss Line Color
input color          InpTPLineColor        = clrLime;          // Take Profit Line Color
input int            InpLineWidth          = 2;                // Line Width

//+------------------------------------------------------------------+
//| Global Objects & Handles                                         |
//+------------------------------------------------------------------+

CTrade          g_trade;
CPositionInfo   g_position;
COrderInfo      g_order;
CAccountInfo    g_account;
CSymbolInfo     g_symbol;

//--- Line object names
const string LINE_ENTRY  = "IDEA_Entry";
const string LINE_SL     = "IDEA_SL";
const string LINE_TP     = "IDEA_TP";

//--- Panel object name prefix
const string PANEL_PREFIX = "IDEA_Panel_";

//--- State flags
bool     g_linesExist         = false;
bool     g_beDone             = false;    // break-even already moved
bool     g_rfDone             = false;    // risk-free already moved
bool     g_partialDone        = false;    // partial close already executed
bool     g_dailyLimitHit      = false;    // daily loss limit reached

//--- Daily tracking
double   g_dayStartBalance    = 0.0;
datetime g_lastDayChecked     = 0;
datetime g_currentDay         = 0;      // midnight of current trading day
double   g_dailyLoss          = 0.0;    // accumulated realized + floating loss today
bool     g_tradingAllowed     = true;   // set false when daily limit hit

//--- Lot size calculated at last trade
double   g_lastLotSize        = 0.0;

//--- Panel button state
bool     g_panelBuyArmed      = false;
bool     g_panelSellArmed     = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate inputs
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 100.0)
   {
      PrintFormat("OnInit: InpRiskPercent=%.2f out of range (0,100]", InpRiskPercent);
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- Configure trade object
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);

   //--- Set filling mode: prefer FOK, fall back to IOC
   long fillMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillMode & SYMBOL_FILLING_FOK) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillMode & SYMBOL_FILLING_IOC) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   //--- Initialise day tracking
   g_dayStartBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
   g_currentDay       = TimeCurrent();
   g_dailyLoss        = 0.0;
   g_tradingAllowed   = true;

   PrintFormat("OnInit: magic=%d slippage=%d fillMode=%d dayBalance=%.2f",
               InpMagicNumber, InpSlippage, (int)fillMode, g_dayStartBalance);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
}

//+------------------------------------------------------------------+
//| Chart event handler                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
}

//+------------------------------------------------------------------+
//| Lot size calculation                                              |
//+------------------------------------------------------------------+
//| Formula (RISK_PERCENT mode):                                      |
//|   risk_amount  = balance * RiskPercent / 100                     |
//|   sl_points    = |entry - sl| / SYMBOL_POINT                     |
//|   tick_value   = monetary value of one tick per 1.0 lot          |
//|   tick_size    = smallest price movement (== SYMBOL_POINT usually)|
//|   lot = risk_amount / (sl_points * tick_value / tick_size)       |
//|                                                                   |
//| tick_value / tick_size converts tick value to a per-point basis  |
//| so the denominator is "account currency loss per lot per point". |
//|                                                                   |
//| FIXED mode:     returns InpFixedLot (clamped & stepped).         |
//| BALANCE_PCT mode: treats InpBalanceLotPct % of balance as lots.  |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double slPrice)
{
   double lot = 0.0;

   if(InpLotMode == LOT_FIXED)
   {
      lot = InpFixedLot;
   }
   else if(InpLotMode == LOT_BALANCE_PCT)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      lot = balance * InpBalanceLotPct / 100.0;
   }
   else // LOT_RISK_PERCENT
   {
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmt   = balance * InpRiskPercent / 100.0;

      double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double tickVal   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(point <= 0.0 || tickVal <= 0.0 || tickSize <= 0.0)
      {
         Print("CalculateLotSize: invalid symbol tick data");
         return 0.0;
      }

      double slPoints = MathAbs(entryPrice - slPrice) / point;
      if(slPoints <= 0.0)
      {
         Print("CalculateLotSize: entry == SL, cannot calculate lot");
         return 0.0;
      }

      double lossPerLotPerPoint = tickVal / tickSize;
      lot = riskAmt / (slPoints * lossPerLotPerPoint);

      PrintFormat("CalculateLotSize | balance=%.2f risk=%.2f%% riskAmt=%.2f slPoints=%.1f lossPerPt=%.5f rawLot=%.4f",
                  balance, InpRiskPercent, riskAmt, slPoints, lossPerLotPerPoint, lot);
   }

   double normalized = NormalizeLot(lot);
   PrintFormat("CalculateLotSize | normalizedLot=%.2f (mode=%d)", normalized, InpLotMode);
   return normalized;
}

//+------------------------------------------------------------------+
//| Open a buy position                                               |
//+------------------------------------------------------------------+
//| entryPrice used only for lot calculation (SL distance).          |
//| Actual order fires at market Ask (price=0 in CTrade::Buy).       |
//| Resets all per-trade state flags on success.                     |
//+------------------------------------------------------------------+
bool OpenBuy(double entryPrice, double slPrice, double tpPrice)
{
   if(slPrice >= entryPrice)
   {
      PrintFormat("OpenBuy: invalid SL %.5f >= entry %.5f", slPrice, entryPrice);
      return false;
   }

   double lot = CalculateLotSize(entryPrice, slPrice);
   if(lot <= 0.0)
   {
      Print("OpenBuy: lot calculation returned 0, order aborted");
      return false;
   }

   PrintFormat("OpenBuy | entry=%.5f SL=%.5f TP=%.5f lot=%.2f", entryPrice, slPrice, tpPrice, lot);

   bool sent = g_trade.Buy(lot, _Symbol, 0, slPrice, tpPrice, InpTradeComment);

   if(sent && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      g_lastLotSize  = lot;
      g_beDone       = false;
      g_rfDone       = false;
      g_partialDone  = false;
      PrintFormat("OpenBuy: order placed | ticket=%d retcode=%d", g_trade.ResultOrder(), g_trade.ResultRetcode());
      return true;
   }

   PrintFormat("OpenBuy: order FAILED | retcode=%d comment=%s", g_trade.ResultRetcode(), g_trade.ResultComment());
   return false;
}

//+------------------------------------------------------------------+
//| Open a sell position                                              |
//+------------------------------------------------------------------+
//| slPrice must be above entryPrice for a valid sell setup.         |
//+------------------------------------------------------------------+
bool OpenSell(double entryPrice, double slPrice, double tpPrice)
{
   if(slPrice <= entryPrice)
   {
      PrintFormat("OpenSell: invalid SL %.5f <= entry %.5f", slPrice, entryPrice);
      return false;
   }

   double lot = CalculateLotSize(entryPrice, slPrice);
   if(lot <= 0.0)
   {
      Print("OpenSell: lot calculation returned 0, order aborted");
      return false;
   }

   PrintFormat("OpenSell | entry=%.5f SL=%.5f TP=%.5f lot=%.2f", entryPrice, slPrice, tpPrice, lot);

   bool sent = g_trade.Sell(lot, _Symbol, 0, slPrice, tpPrice, InpTradeComment);

   if(sent && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      g_lastLotSize  = lot;
      g_beDone       = false;
      g_rfDone       = false;
      g_partialDone  = false;
      PrintFormat("OpenSell: order placed | ticket=%d retcode=%d", g_trade.ResultOrder(), g_trade.ResultRetcode());
      return true;
   }

   PrintFormat("OpenSell: order FAILED | retcode=%d comment=%s", g_trade.ResultRetcode(), g_trade.ResultComment());
   return false;
}

//+------------------------------------------------------------------+
//| Close or partially close a position by ticket                     |
//+------------------------------------------------------------------+
//| volumePct: 100.0 = full close, 50.0 = half close, etc.           |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket, double volumePct = 100.0)
{
   if(!PositionSelectByTicket(ticket))
   {
      PrintFormat("ClosePosition: ticket %d not found", ticket);
      return false;
   }

   bool result = false;

   if(volumePct >= 100.0)
   {
      result = g_trade.PositionClose(ticket);
   }
   else
   {
      double currentVol  = PositionGetDouble(POSITION_VOLUME);
      double closeVol    = NormalizeLot(currentVol * volumePct / 100.0);

      if(closeVol <= 0.0)
      {
         PrintFormat("ClosePosition: closeVol=0 after normalize (currentVol=%.2f pct=%.1f%%)", currentVol, volumePct);
         return false;
      }

      PrintFormat("ClosePosition | ticket=%d pct=%.1f%% currentVol=%.2f closeVol=%.2f",
                  ticket, volumePct, currentVol, closeVol);

      result = g_trade.PositionClosePartial(ticket, closeVol);
   }

   if(result && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      PrintFormat("ClosePosition: OK | ticket=%d pct=%.1f%% retcode=%d",
                  ticket, volumePct, g_trade.ResultRetcode());
      return true;
   }

   PrintFormat("ClosePosition: FAILED | ticket=%d retcode=%d comment=%s",
               ticket, g_trade.ResultRetcode(), g_trade.ResultComment());
   return false;
}

//+------------------------------------------------------------------+
//| Draw / refresh Entry, SL, TP lines on chart                      |
//+------------------------------------------------------------------+
//| Called on init and when user clicks "Draw Lines" in panel.        |
//+------------------------------------------------------------------+
void DrawLines(ENUM_TRADE_DIRECTION direction)
{
}

//+------------------------------------------------------------------+
//| Remove all IDEA chart lines                                       |
//+------------------------------------------------------------------+
void DeleteLines()
{
}

//+------------------------------------------------------------------+
//| Manage open position: check BE, RF, partial close triggers        |
//+------------------------------------------------------------------+
void ManagePosition()
{
}

//+------------------------------------------------------------------+
//| Move stop loss of open position to new price                      |
//+------------------------------------------------------------------+
bool MoveSL(ulong ticket, double newSL)
{
   return false;
}

//+------------------------------------------------------------------+
//| Check and enforce daily loss limit                                |
//+------------------------------------------------------------------+
//| Returns true if trading is blocked (limit hit).                  |
//| Call on every tick before placing orders.                        |
//+------------------------------------------------------------------+
bool CheckDailyLimit()
{
   if(!InpEnableDailyLimit)
   {
      g_tradingAllowed = true;
      return false;
   }

   //--- Detect new trading day and reset
   MqlDateTime now, last;
   TimeToStruct(TimeCurrent(),   now);
   TimeToStruct(g_currentDay,    last);

   if(now.day != last.day || now.mon != last.mon || now.year != last.year)
   {
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyLoss       = 0.0;
      g_currentDay      = TimeCurrent();
      g_tradingAllowed  = true;
      PrintFormat("CheckDailyLimit: new day — balance reset to %.2f", g_dayStartBalance);
   }

   //--- Equity drawdown from day start (captures both floating and closed P&L)
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyLoss      = g_dayStartBalance - equity;

   //--- Check % threshold
   double limitAmt  = g_dayStartBalance * InpMaxDailyLossPct / 100.0;

   //--- Also check fixed USD limit if set
   if(InpMaxDailyLossUSD > 0.0)
      limitAmt = MathMin(limitAmt, InpMaxDailyLossUSD);

   if(g_dailyLoss >= limitAmt)
   {
      if(g_tradingAllowed)   // print only on state change
         PrintFormat("CheckDailyLimit: LIMIT HIT | loss=%.2f limit=%.2f (%.1f%% of %.2f)",
                     g_dailyLoss, limitAmt, InpMaxDailyLossPct, g_dayStartBalance);
      g_tradingAllowed = false;
      return true;
   }

   g_tradingAllowed = true;
   return false;
}

//+------------------------------------------------------------------+
//| Build / refresh on-chart control panel                            |
//+------------------------------------------------------------------+
void UpdatePanel()
{
}

//+------------------------------------------------------------------+
//| Remove all panel objects from chart                               |
//+------------------------------------------------------------------+
void DeletePanel()
{
}

//+------------------------------------------------------------------+
//| Retrieve line price by object name; returns 0.0 if missing        |
//+------------------------------------------------------------------+
double GetLinePrice(const string lineName)
{
   return 0.0;
}

//+------------------------------------------------------------------+
//| Normalize lot to broker step & min/max constraints               |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0) step = 0.01;

   lot = MathRound(lot / step) * step;
   lot = MathMax(lot, minV);
   lot = MathMin(lot, maxV);

   return lot;
}
//+------------------------------------------------------------------+
