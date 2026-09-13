//+------------------------------------------------------------------+
//|                                                       OttoEA.mq5 |
//|                    OTTO â€” Pine Script v4.70 Master Build Port    |
//|              (prop_guard_tester.pine â†’ MetaTrader 5)             |
//|                                    Institutional / Real-Money    |
//+------------------------------------------------------------------+
#property copyright "OTTO EA"
#property version   "4.83"
#property description "OTTO EA â€” Exact port of Pine v4.70 (Wick1+Wick2)"
#property description "Separation | Sizing | Front-Run | Near-Miss | Stale vetoes"
#property description "Modules: News Shield | Risk | Block Manager | Order Mgmt | Trail"
#property link      "https://github.com/otto"

//+------------------------------------------------------------------+
//| Includes                                                          |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include "../Include/Otto/OttoDefines.mqh"
#include "../Include/Otto/COttoNewsFilter.mqh"
#include "../Include/Otto/COttoRiskManager.mqh"
#include "../Include/Otto/COttoMarketStructure.mqh"
#include "../Include/Otto/COttoBlockManager.mqh"
#include "../Include/Otto/COttoOrderManager.mqh"
#include "../Include/Otto/COttoCorrelationFilter.mqh"
#include "../Include/Otto/COttoTradeManager.mqh"
#include "../Include/Otto/COttoJournal.mqh"

//+------------------------------------------------------------------+
//| Global Module Instances                                           |
//+------------------------------------------------------------------+
COttoNewsFilter        g_newsFilter;
COttoRiskManager       g_riskManager;
COttoMarketStructure   g_marketStructure;
COttoBlockManager      g_blockManager;
COttoOrderManager      g_orderManager;
COttoCorrelationFilter g_correlationFilter;
COttoTradeManager      g_tradeManager;
COttoJournal           g_journal;

//+------------------------------------------------------------------+
//| Global State                                                      |
//+------------------------------------------------------------------+
string   g_symbol;
bool     g_isHedging        = false;
bool     g_initialized      = false;
int      g_tickCount        = 0;
datetime g_lastStatusLog    = 0;
int      g_fileHandle       = INVALID_HANDLE;
string   g_logFileName      = "";

// --- Human-readable trade journal ---
int      g_journalHandle    = INVALID_HANDLE;
string   g_journalFileName  = "";
long     g_lastPlacedCount  = 0;   // last-seen OrderManager GetOrdersPlaced()
long     g_lastFilledCount  = 0;   // last-seen GetOrdersFilled()
long     g_lastRejectedCount= 0;   // last-seen GetOrdersRejected()
long     g_lastHalfRisk     = 0;   // last-seen GetHalfRiskTriggers()
long     g_lastBE           = 0;   // last-seen GetBreakevenTriggers()
long     g_lastTrail        = 0;   // last-seen GetTrailActivations()
bool     g_lastHadTrade     = false;

// --- Market-day counter (Pine ta.change(time("D")) mirror) ---
int      g_marketDay        = 0;
datetime g_lastDailyBarTime = 0;
datetime g_lastBarTime      = 0;

// --- Prop Firm Safety State ---
double   g_initialBalance      = 0;
double   g_midnightBalance     = 0;
datetime g_lastMidnightCheck   = 0;
bool     g_dailyDD_Paused      = false;
bool     g_totalDD_Halted      = false;
datetime g_dailyDD_ResumeTime  = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   g_symbol = _Symbol;

   Print("==============================================================");
   Print("  OTTO EA v4.83 â€” Pine v4.70 Master Build â€” INITIALIZING");
   Print("  Symbol: ", g_symbol, " | Magic: ", MagicNumber);
   Print("==============================================================");

   // --- Validate Hedging Account ---
   ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("FATAL: OTTO requires HEDGING account mode!");
      Print("Current mode: ", EnumToString(marginMode));
      return INIT_FAILED;
     }
   g_isHedging = true;
   Print("[INIT] Account type: HEDGING");

   Print("[INIT] Balance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
         " | Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
         " | Free: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));

   // --- News Filter ---
   if(!g_newsFilter.Initialize(g_symbol))
      Print("[INIT] WARNING: News Filter init failed â€” continuing");
   else
      Print("[INIT] News Filter OK");

   // --- Risk Manager ---
   if(!g_riskManager.Initialize(g_symbol))
     {
      Print("[INIT] FATAL: Risk Manager init failed");
      return INIT_FAILED;
     }
   Print("[INIT] Risk Manager OK");

   // --- Market Structure (pivots) ---
   if(!g_marketStructure.Initialize(g_symbol))
     {
      Print("[INIT] FATAL: Market Structure init failed");
      return INIT_FAILED;
     }
   Print("[INIT] Market Structure OK");

   // --- Block Manager ---
   if(!g_blockManager.Initialize(g_symbol, &g_marketStructure))
     {
      Print("[INIT] FATAL: Block Manager init failed");
      return INIT_FAILED;
     }
   Print("[INIT] Block Manager OK");

   // --- Startup historical warm-up: populate blocks from past pivots ---
   g_blockManager.WarmUpHistory();
   Print("[INIT] Warm-up complete — blocks now on chart: ",
         g_blockManager.GetBlockCount());


   // --- Correlation Filter ---
   if(!g_correlationFilter.Initialize(g_symbol))
      Print("[INIT] WARNING: Correlation Filter init failed â€” continuing");
   else
      Print("[INIT] Correlation Filter OK");

   // --- Order Manager ---
   if(!g_orderManager.Initialize(g_symbol, &g_riskManager, &g_blockManager, &g_correlationFilter))
     {
      Print("[INIT] FATAL: Order Manager init failed");
      return INIT_FAILED;
     }
   Print("[INIT] Order Manager OK");

// --- Trade Journal (human-readable .txt lifecycle log) ---
   g_journal.Initialize(g_symbol);
   g_orderManager.SetJournal(&g_journal);


   // --- Trade Manager ---
   if(!g_tradeManager.Initialize(g_symbol, &g_riskManager, &g_orderManager, &g_blockManager))
     {
      Print("[INIT] FATAL: Trade Manager init failed");
      return INIT_FAILED;
     }
   Print("[INIT] Trade Manager OK");

   // --- Prop firm safety state ---
   g_initialBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
   g_midnightBalance  = g_initialBalance;
   g_dailyEquityHigh  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyDD_Paused   = false;
   g_totalDD_Halted   = false;
   MqlDateTime dt;
   TimeCurrent(dt);
   g_lastMidnightCheck = StructToTime(dt);
   Print("[Safety] Init Balance: ", DoubleToString(g_initialBalance, 2),
         " | DailyDD: ", SafetyDailyDDLimit, "% | TotalDD: ", SafetyTotalDDLimit, "%");

   // --- Market-day counter init (mirrors ta.change(time("D"))) ---
   g_lastDailyBarTime = iTime(_Symbol, PERIOD_D1, 0);
   g_marketDay        = 0;
   g_lastBarTime      = iTime(_Symbol, PERIOD_CURRENT, 0);

   // --- Sync existing trade state ---
   g_tradeManager.SyncTradeState();

   // --- Setup log file ---
   if(EnableLogging)
     {
      g_logFileName = "Otto_" + g_symbol + "_" +
                      IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
      g_fileHandle  = FileOpen(g_logFileName, FILE_CSV | FILE_WRITE | FILE_SHARE_READ, ',');
      if(g_fileHandle != INVALID_HANDLE)
        {
         FileWrite(g_fileHandle, "Time", "Symbol", "Event", "Details");
         Print("[INIT] Log file: ", g_logFileName);
        }
      else
         Print("[INIT] WARNING: Could not create log file");
     }

// --- Setup human-readable trade journal ---
   if(EnableJournal)
     {
      g_journalFileName = "Otto_Journal_" + g_symbol + "_" +
                          IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".txt";
      g_journalHandle   = FileOpen(g_journalFileName, FILE_TXT | FILE_WRITE | FILE_SHARE_READ | FILE_ANSI);
      if(g_journalHandle != INVALID_HANDLE)
        {
         FileWriteString(g_journalHandle, "OTTO EA - Trade Journal\n");
         FileWriteString(g_journalHandle, "Symbol: " + g_symbol + " | Started: " + TimeToString(TimeCurrent()) + "\n");
         FileWriteString(g_journalHandle, "------------------------------------------------------------------\n");
         Print("[INIT] Journal file: ", g_journalFileName);
        }
      else
         Print("[INIT] WARNING: Could not create journal file");
     }
   g_initialized = true;

   Print("==============================================================");
   Print("  OTTO EA INITIALIZED SUCCESSFULLY");
   Print("  Risk: ", (InpFixedRiskUSD > 0 ? ("$" + DoubleToString(InpFixedRiskUSD,2))
                                          : (DoubleToString(RiskPercent,2) + "%")),
         " | DailyDD: ", SafetyDailyDDLimit, "% | TotalDD: ", SafetyTotalDDLimit, "%");
   Print("==============================================================");

   return INIT_SUCCEEDED;
  }


//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("==============================================================");
   Print("  OTTO EA â€” DEINITIALIZING (reason ", reason, ")");

   Print("  --- News Filter ---");
   Print("  Blackouts: ", g_newsFilter.GetBlackoutCount());
   Print("  --- Block Manager ---");
   Print("  Created: ", g_blockManager.GetBlocksCreated(),
         " | Broken: ", g_blockManager.GetBlocksBroken(),
         " | Vetoed: ", g_blockManager.GetBlocksVetoed());
   Print("  --- Order Manager ---");
   Print("  Placed: ", g_orderManager.GetOrdersPlaced(),
         " | Filled: ", g_orderManager.GetOrdersFilled(),
         " | Rejected: ", g_orderManager.GetOrdersRejected());
   Print("  --- Trade Manager ---");
   Print("  HalfRisk: ", g_tradeManager.GetHalfRiskTriggers(),
         " | BE: ", g_tradeManager.GetBreakevenTriggers(),
         " | Trail: ", g_tradeManager.GetTrailActivations());

   // Cancel all pending orders
   int pending = g_orderManager.CountMyPending();
   if(pending > 0)
     {
      Print("  Cancelling ", pending, " pending orders...");
      g_orderManager.CancelAllPendingOrders();
     }

   // Close log file
   if(g_fileHandle != INVALID_HANDLE)
     {
      FileClose(g_fileHandle);
      g_fileHandle = INVALID_HANDLE;
     }
// Close journal file
   if(g_journalHandle != INVALID_HANDLE)
     {
      FileClose(g_journalHandle);
      g_journalHandle = INVALID_HANDLE;
     }
   g_journal.Close();   // COttoJournal detailed .txt journal

   g_initialized = false;
   Print("==============================================================");
  }

//+------------------------------------------------------------------+
//| Checks daily balance reset at midnight server time               |
//+------------------------------------------------------------------+
void CheckDailyReset(void)
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime todayMidnight = StructToTime(dt);

   if(todayMidnight != g_lastMidnightCheck)
     {
      g_midnightBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyEquityHigh = AccountInfoDouble(ACCOUNT_EQUITY);
      g_lastMidnightCheck = todayMidnight;
      if(g_dailyDD_Paused)
        {
         g_dailyDD_Paused = false;
         if(EnableLogging)
            Print("[Safety] New day â€” daily DD pause LIFTED");
        }
     }
  }

//+------------------------------------------------------------------+
//| New-bar detection â€” gates the block formation + veto funnel      |
//+------------------------------------------------------------------+
bool IsNewBar(void)
  {
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(barTime == g_lastBarTime)
      return false;
   g_lastBarTime = barTime;
   return true;
  }

//+------------------------------------------------------------------+
//| Market-day counter â€” increments when the daily bar changes.      |
//| Weekends are naturally skipped (no daily bars on Sat/Sun). This  |
//| mirrors Pine ta.change(time("D")).                               |
//+------------------------------------------------------------------+
void UpdateMarketDay(void)
  {
   datetime dailyBar = iTime(_Symbol, PERIOD_D1, 0);
   if(dailyBar != g_lastDailyBarTime)
     {
      g_marketDay++;
      g_lastDailyBarTime = dailyBar;
     }
  }

//+------------------------------------------------------------------+
//| Hive Mind â€” broadcast bias and resolve bidirectional conflicts   |
//+------------------------------------------------------------------+
void HiveMind(void)
  {
   if(g_dailyDD_Paused) return;

   SSniperBlock allBlocks[];
   int total = g_blockManager.GetAllBlocks(allBlocks);
   bool hasSupport = false, hasResistance = false;
   for(int b = 0; b < total; b++)
     {
      if(allBlocks[b].isVetoed) continue;
      if(allBlocks[b].type == BLOCK_SUPPORT) hasSupport = true;
      if(allBlocks[b].type == BLOCK_RESISTANCE) hasResistance = true;
     }

   int myBias = 0;
   if(hasSupport && !hasResistance)
      myBias = 1;
   else if(hasResistance && !hasSupport)
      myBias = -1;
   else if(hasSupport && hasResistance)
     {
      int resolution = g_correlationFilter.ResolveBidirectionalConflict();
      if(resolution == 1)
        {
         g_blockManager.DeleteBlockType(BLOCK_RESISTANCE);
         myBias = 1;
         if(EnableLogging) Print("[HiveMind] CONFLICT: peers Long â†’ kept Support");
        }
      else if(resolution == -1)
        {
         g_blockManager.DeleteBlockType(BLOCK_SUPPORT);
         myBias = -1;
         if(EnableLogging) Print("[HiveMind] CONFLICT: peers Short â†’ kept Resistance");
        }
      else
        {
         g_blockManager.DeleteBlockType(BLOCK_SUPPORT);
         g_blockManager.DeleteBlockType(BLOCK_RESISTANCE);
         myBias = 0;
         if(EnableLogging) Print("[HiveMind] CONFLICT: no consensus â†’ deleted both");
        }
     }
   g_correlationFilter.BroadcastBias(myBias);
  }


//+------------------------------------------------------------------+
//| Expert tick function â€” Main Orchestration Loop                   |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   if(!g_initialized) return;
   if(g_totalDD_Halted) return;

   g_tickCount++;
   CheckDailyReset();

   // ================================================================
   // STEP 0: PROP FIRM SAFETY CHECKS (highest priority)
   // ================================================================
   if(!g_dailyDD_Paused)
     {
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double dailyDD = (g_midnightBalance > 0) ? 100.0 * (g_midnightBalance - equity) / g_midnightBalance : 0;
      double totalDD = (g_initialBalance  > 0) ? 100.0 * (g_initialBalance  - equity) / g_initialBalance  : 0;

      if(dailyDD >= SafetyDailyDDLimit)
        {
         g_dailyDD_Paused = true;
         g_dailyDD_ResumeTime = g_lastMidnightCheck + 86400;
         g_orderManager.CancelAllPendingOrders();
         if(EnableLogging)
            Print("[Safety] DAILY DRAWDOWN: ", DoubleToString(dailyDD, 2),
                  "% â‰¥ ", SafetyDailyDDLimit, "% â€” paused new orders");
        }

      if(totalDD >= SafetyTotalDDLimit)
        {
         g_totalDD_Halted = true;
         g_orderManager.CancelAllPendingOrders();
         if(g_orderManager.HasActiveTrade())
            g_orderManager.ForceClose(g_orderManager.GetActiveTrade().ticket);
         Print("==============================================================");
         Print("  FATAL: TOTAL DRAWDOWN LIMIT REACHED â€” EA PERMANENTLY HALTED");
         Print("  DD: ", DoubleToString(totalDD, 2), "% â‰¥ ", SafetyTotalDDLimit, "%");
         Print("==============================================================");
         return;
        }
     }

   // ================================================================
   // STEP 1: Update News Filter (real calendar blackout)
   // ================================================================
   g_newsFilter.Update();

   // ================================================================
   // STEP 2: NEW BAR â€” block formation + veto funnel (bar-close logic)
   // Mirrors calc_on_every_tick=false.
   // ================================================================
   if(IsNewBar())
     {
      UpdateMarketDay();               // advance the trading-day counter

      // Cancel orders on freshly-invalidated blocks BEFORE the funnel reaps them
      g_orderManager.CancelOrdersForInvalidBlocks();

      // Run the funnel (W1/W2 formation + all v4.70 vetoes)
      g_blockManager.Update(g_marketDay);

      // Cancel any orders declared invalid during this bar's funnel
      g_orderManager.CancelOrdersForInvalidBlocks();

      // Hive Mind (correlation tie-breaker)
      HiveMind();
     }


   // ================================================================
   // STEP 3: INTRA-BAR TARGET CHECKS (inside OnTick)
   // Front-Run 1:3 target + 6-day near-miss expiry, live.
   // ================================================================
   g_blockManager.CheckVetoesInTick(g_marketDay);
   g_orderManager.CancelOrdersForInvalidBlocks();

   // ================================================================
   // STEP 4: ORDER PLACEMENT â€” Pine-gated limit orders for armed blocks
   // Gated further by news blackout + daily-DD pause.
   // ================================================================
   if(!g_newsFilter.IsInNewsBlackout() && !g_dailyDD_Paused)
      g_orderManager.PlaceOrdersForArmedBlocks();

   // ================================================================
   // STEP 5: MANAGE ACTIVE TRADES â€” dynamic trail (every tick)
   // ================================================================
   g_tradeManager.Update();

   // ================================================================
   // STEP 6: ORDER LIFECYCLE â€” fill detection + reversal completion
   // ================================================================
   g_orderManager.Update();

   // ================================================================
   // STEP 7: DIRECTION CONFLICT â€” cancel same-direction pending orders
   // ================================================================
   g_orderManager.ManageDirectionConflict();

// ================================================================
   // STEP 7B: TRADE JOURNAL — one-shot human-readable event log
   // ================================================================
   if(EnableJournal)
      JournalCheckEvents();
   // ================================================================
   // STEP 8: PERIODIC STATUS LOGGING
   // ================================================================
   if(EnableLogging && TimeCurrent() - g_lastStatusLog >= 3600)
     {
      LogStatus();
      g_lastStatusLog = TimeCurrent();
     }
  }

//+------------------------------------------------------------------+
//| Periodic status logging to console and file                      |
//+------------------------------------------------------------------+
void LogStatus(void)
  {
   string statusLine;
   StringConcatenate(statusLine,
                     "[STATUS] Day=", g_marketDay,
                     " | News: ", g_newsFilter.IsInNewsBlackout() ? "BLACKOUT" : "CLEAR",
                     " | Blocks: ", g_blockManager.GetBlockCount(),
                     " | ActiveTrade: ", g_orderManager.HasActiveTrade() ? "YES" : "NO",
                     " | Pending: ", g_orderManager.CountMyPending(),
                     " | ATR: ", DoubleToString(g_blockManager.GetATR(), _Digits),
                     " | DailyDD: ", g_dailyDD_Paused ? "PAUSED" : "OK",
                     " | TotalDD: ", g_totalDD_Halted ? "HALTED" : "OK");
   Print(statusLine);
   if(g_fileHandle != INVALID_HANDLE)
     {
      FileWrite(g_fileHandle, TimeToString(TimeCurrent()), g_symbol, "STATUS", statusLine);
      FileFlush(g_fileHandle);
     }
  }

//+------------------------------------------------------------------+
//| OnChartEvent â€” reserved                                          |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Writes a line to the human-readable .txt trade journal            |
//+------------------------------------------------------------------+
void JournalWrite(string event, string details)
  {
   if(g_journalHandle == INVALID_HANDLE) return;
   string line = TimeToString(TimeCurrent()) + "  | " + event + "  | " + details;
   FileWriteString(g_journalHandle, line + "\n");
   FileFlush(g_journalHandle);
  }

//+------------------------------------------------------------------+
//| One-shot journal hooks for the EA's OnTick (counter-diff based)  |
//+------------------------------------------------------------------+
void JournalCheckEvents(void)
  {
   // --- NEW ORDER(S) PLACED ---
   long placed = g_orderManager.GetOrdersPlaced();
   if(placed > g_lastPlacedCount)
     {
      g_lastPlacedCount = placed;
      JournalWrite("ORDER PLACED", "pending count now " + IntegerToString((int)placed));
     }

   // --- FILLED ---
   long filled = g_orderManager.GetOrdersFilled();
   if(filled > g_lastFilledCount)
     {
      g_lastFilledCount = filled;
      JournalWrite("FILLED", "");
     }

   // --- REJECTED ---
   long rejected = g_orderManager.GetOrdersRejected();
   if(rejected > g_lastRejectedCount)
     {
      g_lastRejectedCount = rejected;
      JournalWrite("REJECTED", "");
     }

   // --- TRADE MANAGER STEP CHANGES ---
   int halfRisk = g_tradeManager.GetHalfRiskTriggers();
   if(halfRisk > g_lastHalfRisk)
     { g_lastHalfRisk = halfRisk; JournalWrite("SL -> HALF-RISK", "risk now -0.5R"); }

   int be = g_tradeManager.GetBreakevenTriggers();
   if(be > g_lastBE)
     { g_lastBE = be; JournalWrite("SL -> BREAKEVEN (COST-COVERING)", ""); }

   int trail = g_tradeManager.GetTrailActivations();
   if(trail > g_lastTrail)
     { g_lastTrail = trail; JournalWrite("SL -> DYNAMIC TRAIL ACTIVE", ""); }

   // --- TRADE CLOSED (active->flat transition) ---
   bool nowActive = g_orderManager.HasActiveTrade();
   if(g_lastHadTrade && !nowActive)
     JournalWrite("TRADE CLOSED", "");
   g_lastHadTrade = nowActive;
  }
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
  }

//+------------------------------------------------------------------+
//| OnTrade â€” re-sync active trade state on trade events             |
//+------------------------------------------------------------------+
void OnTrade(void)
  {
   if(g_initialized)
      g_orderManager.SyncActiveTrade();
  }

//+------------------------------------------------------------------+
//| OnTimer â€” reserved heartbeat                                      |
//+------------------------------------------------------------------+
void OnTimer(void)
  {
  }

double   g_dailyEquityHigh     = 0;
