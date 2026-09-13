//+------------------------------------------------------------------+
//|                                        COttoCorrelationFilter.mqh |
//|              MODULE — Weighted Correlation Matrix (-3 to +3)      |
//|              OTTO EA — Institutional portfolio filter            |
//+------------------------------------------------------------------+
#property copyright "OTTO EA"
#property version   "4.83"

#ifndef __OTTO_CORRELATION_FILTER__
#define __OTTO_CORRELATION_FILTER__

#include "OttoDefines.mqh"

//+------------------------------------------------------------------+
//| COttoCorrelationFilter class                                     |
//| Weighted -3 to +3 correlation matrix for 12 pairs.               |
//| Veto threshold: |score| >= 2.                                    |
//| Hive Mind tie-breaker: Total >= 2 or <= -2, else delete both.    |
//+------------------------------------------------------------------+
class COttoCorrelationFilter
  {
private:
   string            m_symbol;
   string            m_allSymbols[];

   //+------------------------------------------------------------------+
   //| MODULE 1: GetCorrelationScore — weighted -3 to +3 matrix lookup  |
   //+------------------------------------------------------------------+
   int               GetCorrelationScore(string sym1, string sym2)
     {
      if(sym1 == sym2) return 0;

      // --- EURUSD ---
      if(sym1 == "EURUSD")
        {
         if(sym2 == "GOLD" || sym2 == "XAUUSD") return 2;
         if(sym2 == "GBPUSD") return 2;
         if(sym2 == "USDJPY") return -1;
         if(sym2 == "AUDUSD") return 2;
         if(sym2 == "NZDUSD") return 2;
         if(sym2 == "USDCHF") return -3;
         if(sym2 == "USDCAD") return -1;
         if(sym2 == "EURJPY") return 1;
         if(sym2 == "GBPJPY") return 0;
         if(sym2 == "EURCHF") return 2;
         if(sym2 == "AUDJPY") return 1;
         return 0;
        }

      // --- GBPUSD ---
      if(sym1 == "GBPUSD")
        {
         if(sym2 == "GOLD" || sym2 == "XAUUSD") return 1;
         if(sym2 == "EURUSD") return 2;
         if(sym2 == "USDJPY") return -1;
         if(sym2 == "AUDUSD") return 1;
         if(sym2 == "NZDUSD") return 1;
         if(sym2 == "USDCHF") return -2;
         if(sym2 == "USDCAD") return -1;
         if(sym2 == "EURJPY") return 0;
         if(sym2 == "GBPJPY") return 1;
         if(sym2 == "EURCHF") return 1;
         if(sym2 == "AUDJPY") return 0;
         return 0;
        }

      // --- AUDUSD ---
      if(sym1 == "AUDUSD")
        {
         if(sym2 == "GOLD" || sym2 == "XAUUSD") return 2;
         if(sym2 == "EURUSD") return 2;
         if(sym2 == "GBPUSD") return 1;
         if(sym2 == "USDJPY") return 1;
         if(sym2 == "NZDUSD") return 3;
         if(sym2 == "USDCHF") return -1;
         if(sym2 == "USDCAD") return -1;
         if(sym2 == "EURJPY") return 1;
         if(sym2 == "GBPJPY") return 1;
         if(sym2 == "EURCHF") return 0;
         if(sym2 == "AUDJPY") return 2;
         return 0;
        }

      // --- NZDUSD ---
      if(sym1 == "NZDUSD")
        {
         if(sym2 == "GOLD" || sym2 == "XAUUSD") return 1;
         if(sym2 == "EURUSD") return 2;
         if(sym2 == "GBPUSD") return 1;
         if(sym2 == "USDJPY") return 1;
         if(sym2 == "AUDUSD") return 3;
         if(sym2 == "USDCHF") return -1;
         if(sym2 == "USDCAD") return -1;
         if(sym2 == "EURJPY") return 1;
         if(sym2 == "GBPJPY") return 1;
         if(sym2 == "EURCHF") return 0;
         if(sym2 == "AUDJPY") return 2;
         return 0;
        }

      // --- USDJPY ---
      if(sym1 == "USDJPY")
        {
         if(sym2 == "GOLD" || sym2 == "XAUUSD") return -1;
         if(sym2 == "EURUSD") return -1;
         if(sym2 == "GBPUSD") return -1;
         if(sym2 == "AUDUSD") return 1;
         if(sym2 == "NZDUSD") return 1;
         if(sym2 == "USDCHF") return 1;
         if(sym2 == "USDCAD") return 1;
         if(sym2 == "EURJPY") return 2;
         if(sym2 == "GBPJPY") return 2;
         if(sym2 == "EURCHF") return 0;
         if(sym2 == "AUDJPY") return 2;
         return 0;
        }


      // --- USDCHF ---
      if(sym1 == "USDCHF")
        {
         if(sym2 == "GOLD" || sym2 == "XAUUSD") return -2;
         if(sym2 == "EURUSD") return -3;
         if(sym2 == "GBPUSD") return -2;
         if(sym2 == "USDJPY") return 1;
         if(sym2 == "AUDUSD") return -1;
         if(sym2 == "NZDUSD") return -1;
         if(sym2 == "USDCAD") return 1;
         if(sym2 == "EURJPY") return -1;
         if(sym2 == "GBPJPY") return -1;
         if(sym2 == "EURCHF") return -1;
         if(sym2 == "AUDJPY") return -1;
         return 0;
        }

      // --- USDCAD ---
      if(sym1 == "USDCAD")
        {
         if(sym2 == "GOLD" || sym2 == "XAUUSD") return -1;
         if(sym2 == "EURUSD") return -1;
         if(sym2 == "GBPUSD") return -1;
         if(sym2 == "USDJPY") return 1;
         if(sym2 == "AUDUSD") return -1;
         if(sym2 == "NZDUSD") return -1;
         if(sym2 == "USDCHF") return 1;
         if(sym2 == "EURJPY") return 0;
         if(sym2 == "GBPJPY") return 0;
         if(sym2 == "EURCHF") return 0;
         if(sym2 == "AUDJPY") return -1;
         return 0;
        }

      // --- EURJPY ---
      if(sym1 == "EURJPY")
        {
         if(sym2 == "GOLD" || sym2 == "XAUUSD") return 0;
         if(sym2 == "EURUSD") return 1;
         if(sym2 == "GBPUSD") return 0;
         if(sym2 == "USDJPY") return 2;
         if(sym2 == "AUDUSD") return 1;
         if(sym2 == "NZDUSD") return 1;
         if(sym2 == "USDCHF") return -1;
         if(sym2 == "USDCAD") return 0;
         if(sym2 == "GBPJPY") return 2;
         if(sym2 == "EURCHF") return 1;
         if(sym2 == "AUDJPY") return 2;
         return 0;
        }

      // --- GBPJPY ---
      if(sym1 == "GBPJPY")
        {
         if(sym2 == "GOLD" || sym2 == "XAUUSD") return 0;
         if(sym2 == "EURUSD") return 0;
         if(sym2 == "GBPUSD") return 1;
         if(sym2 == "USDJPY") return 2;
         if(sym2 == "AUDUSD") return 1;
         if(sym2 == "NZDUSD") return 1;
         if(sym2 == "USDCHF") return -1;
         if(sym2 == "USDCAD") return 0;
         if(sym2 == "EURJPY") return 2;
         if(sym2 == "EURCHF") return 0;
         if(sym2 == "AUDJPY") return 2;
         return 0;
        }

      // --- EURCHF ---
      if(sym1 == "EURCHF")
        {
         if(sym2 == "GOLD" || sym2 == "XAUUSD") return -1;
         if(sym2 == "EURUSD") return 2;
         if(sym2 == "GBPUSD") return 1;
         if(sym2 == "USDJPY") return 0;
         if(sym2 == "AUDUSD") return 0;
         if(sym2 == "NZDUSD") return 0;
         if(sym2 == "USDCHF") return -1;
         if(sym2 == "USDCAD") return 0;
         if(sym2 == "EURJPY") return 1;
         if(sym2 == "GBPJPY") return 0;
         if(sym2 == "AUDJPY") return 0;
         return 0;
        }

      // --- AUDJPY ---
      if(sym1 == "AUDJPY")
        {
         if(sym2 == "GOLD" || sym2 == "XAUUSD") return 0;
         if(sym2 == "EURUSD") return 1;
         if(sym2 == "GBPUSD") return 0;
         if(sym2 == "USDJPY") return 2;
         if(sym2 == "AUDUSD") return 2;
         if(sym2 == "NZDUSD") return 2;
         if(sym2 == "USDCHF") return -1;
         if(sym2 == "USDCAD") return -1;
         if(sym2 == "EURJPY") return 2;
         if(sym2 == "GBPJPY") return 2;
         if(sym2 == "EURCHF") return 0;
         return 0;
        }

      // --- XAUUSD (GOLD) ---
      if(sym1 == "XAUUSD" || sym1 == "GOLD")
        {
         if(sym2 == "EURUSD") return 2;
         if(sym2 == "GBPUSD") return 1;
         if(sym2 == "USDJPY") return -1;
         if(sym2 == "AUDUSD") return 2;
         if(sym2 == "NZDUSD") return 1;
         if(sym2 == "USDCHF") return -2;
         if(sym2 == "USDCAD") return -1;
         if(sym2 == "EURJPY") return 0;
         if(sym2 == "GBPJPY") return 0;
         if(sym2 == "EURCHF") return 1;
         if(sym2 == "AUDJPY") return 0;
         return 0;
        }

      return 0;
     }

   //+------------------------------------------------------------------+
   //| Scans all open positions for correlation conflicts               |
   //+------------------------------------------------------------------+
   bool              ScanPositionsForVeto(int proposedDir)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

         string posSymbol = PositionGetString(POSITION_SYMBOL);
         long   posType   = PositionGetInteger(POSITION_TYPE);
         int    posDir    = (posType == POSITION_TYPE_BUY) ? 1 : -1;
         int    score     = GetCorrelationScore(m_symbol, posSymbol);

         // |score| >= 2 is strong correlation — apply veto
         if(proposedDir == 1)  // Proposed LONG
           {
            if(posDir == 1 && score <= -2) return true;
            if(posDir == -1 && score >= 2) return true;
           }
         if(proposedDir == -1) // Proposed SHORT
           {
            if(posDir == -1 && score <= -2) return true;
            if(posDir == 1 && score >= 2) return true;
           }
        }
      return false;
     }


public:
   //+------------------------------------------------------------------+
   //| Constructor — populate the symbol universe                       |
   //+------------------------------------------------------------------+
                     COttoCorrelationFilter(void)
     {
      m_symbol = "";
      ArrayResize(m_allSymbols, 12);
      m_allSymbols[0]  = "EURUSD";
      m_allSymbols[1]  = "GBPUSD";
      m_allSymbols[2]  = "AUDUSD";
      m_allSymbols[3]  = "NZDUSD";
      m_allSymbols[4]  = "USDJPY";
      m_allSymbols[5]  = "USDCHF";
      m_allSymbols[6]  = "USDCAD";
      m_allSymbols[7]  = "EURJPY";
      m_allSymbols[8]  = "GBPJPY";
      m_allSymbols[9]  = "EURCHF";
      m_allSymbols[10] = "AUDJPY";
      m_allSymbols[11] = "XAUUSD";
     }

                    ~COttoCorrelationFilter(void) { ArrayFree(m_allSymbols); }

   //+------------------------------------------------------------------+
   //| Initialize                                                       |
   //+------------------------------------------------------------------+
   bool              Initialize(string symbol)
     {
      m_symbol = symbol;
      if(EnableLogging)
         Print("[Correlation] Initialized for ", m_symbol,
               " | Matrix: 12-pair weighted -3 to +3");
      return true;
     }

   //+------------------------------------------------------------------+
   //| MODULE 2: IsTradeVetoed — Weighted Portfolio Veto                |
   //+------------------------------------------------------------------+
   bool              IsTradeVetoed(ENUM_TRADE_DIRECTION proposedDirection)
     {
      if(proposedDirection != DIR_LONG && proposedDirection != DIR_SHORT)
         return false;
      int dir = (proposedDirection == DIR_LONG) ? 1 : -1;
      return ScanPositionsForVeto(dir);
     }

   //+------------------------------------------------------------------+
   //| BroadcastBias — write bias to MT5 Global Variable                |
   //+------------------------------------------------------------------+
   void              BroadcastBias(int bias)
     {
      string varName = "TS_Bias_" + m_symbol;   // Key shared across EA instances
      if(bias == 0)
         GlobalVariableDel(varName);
      else
         GlobalVariableSet(varName, bias);
     }

   //+------------------------------------------------------------------+
   //| MODULE 3: GetWeightedBiasSum — matrix-weighted peer bias sum     |
   //+------------------------------------------------------------------+
   int               GetWeightedBiasSum(void)
     {
      int totalBias = 0;
      for(int i = 0; i < ArraySize(m_allSymbols); i++)
        {
         if(m_allSymbols[i] == m_symbol) continue;
         string varName = "TS_Bias_" + m_allSymbols[i];
         if(GlobalVariableCheck(varName))
           {
            int peerBias = (int)GlobalVariableGet(varName);
            int score = GetCorrelationScore(m_symbol, m_allSymbols[i]);
            totalBias += peerBias * score;
           }
        }
      return totalBias;
     }

   //+------------------------------------------------------------------+
   //| MODULE 3: ResolveBidirectionalConflict — weighted tie-breaker   |
   //+------------------------------------------------------------------+
   int               ResolveBidirectionalConflict(void)
     {
      int totalBias = GetWeightedBiasSum();
      if(EnableLogging)
         Print("[Correlation] Weighted Bias Sum for ", m_symbol, " = ", totalBias);

      if(totalBias >= 2) return 1;    // Strongly Long -> keep Support
      if(totalBias <= -2) return -1;  // Strongly Short -> keep Resistance
      return 0;                       // Mixed -> delete both
     }

   //+------------------------------------------------------------------+
   //| Public access to matrix score (for diagnostics)                 |
   //+------------------------------------------------------------------+
   int               DebugScore(string sym1, string sym2)
     {
      return GetCorrelationScore(sym1, sym2);
     }
  };

//+------------------------------------------------------------------+
#endif  // __OTTO_CORRELATION_FILTER__
