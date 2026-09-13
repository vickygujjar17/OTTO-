//+------------------------------------------------------------------+
//|                                          COttoMarketStructure.mqh |
//|          MODULE — Pivot High/Low Generation (Left=8, Right=3)     |
//|              OTTO EA — exact ta.pivothigh/pivotlow port           |
//+------------------------------------------------------------------+
#property copyright "OTTO EA"
#property version   "4.83"

#ifndef __OTTO_MARKET_STRUCTURE__
#define __OTTO_MARKET_STRUCTURE__

#include "OttoDefines.mqh"

//+------------------------------------------------------------------+
//| COttoMarketStructure class                                       |
//| Detects fractal pivot highs/lows with the EXACT Pine v4.70       |
//| structure: ta.pivothigh(high, lb, rb) / ta.pivotlow(low, lb, rb) |
//| with lb = InpLeftBars (8) and rb = InpRightBars (3).             |
//|                                                                    |
//| Pine semantics: a pivot high at bar i requires bar i to have the |
//| highest HIGH among the lb bars to its left AND rb bars to its    |
//| right (all strictly lower). The pivot is confirmed when the rb-  |
//| th right bar closes. The caller (COttoBlockManager) requests     |
//| pivots at shift = InpRightBars + 1, i.e. the confirmed candle at |
//| the close of the previous bar — matching calc_on_every_tick=false.|
//+------------------------------------------------------------------+
class COttoMarketStructure
  {
private:
   string            m_symbol;

   //+------------------------------------------------------------------+
   //| Strict fractal check: is shift 's' the highest high among +lb/  |
   //| -rb neighbours? (excludes the centre candle)                    |
   //+------------------------------------------------------------------+
   bool              IsFractalHigh(int s, int leftBars, int rightBars)
     {
      double center = iHigh(m_symbol, PERIOD_CURRENT, s);

      // Left side (older bars, larger shift) — all strictly lower
      for(int i = 1; i <= leftBars; i++)
         if(iHigh(m_symbol, PERIOD_CURRENT, s + i) >= center)
            return false;

      // Right side (newer bars, smaller shift) — all strictly lower
      for(int i = 1; i <= rightBars; i++)
        {
         int check = s - i;
         if(check < 0) return false;
         if(iHigh(m_symbol, PERIOD_CURRENT, check) >= center)
            return false;
        }
      return true;
     }

   //+------------------------------------------------------------------+
   //| Strict fractal check: is shift 's' the lowest low among +lb/    |
   //| -rb neighbours?                                                  |
   //+------------------------------------------------------------------+
   bool              IsFractalLow(int s, int leftBars, int rightBars)
     {
      double center = iLow(m_symbol, PERIOD_CURRENT, s);

      for(int i = 1; i <= leftBars; i++)
         if(iLow(m_symbol, PERIOD_CURRENT, s + i) <= center)
            return false;

      for(int i = 1; i <= rightBars; i++)
        {
         int check = s - i;
         if(check < 0) return false;
         if(iLow(m_symbol, PERIOD_CURRENT, check) <= center)
            return false;
        }
      return true;
     }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
                     COttoMarketStructure(void)
     {
      m_symbol = "";
     }

   //+------------------------------------------------------------------+
   //| Destructor                                                       |
   //+------------------------------------------------------------------+
                    ~COttoMarketStructure(void)
     {
     }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool              Initialize(string symbol)
     {
      m_symbol = symbol;
      if(EnableLogging)
         Print("[MarketStructure] Initialized for ", m_symbol,
               " | Pivot: Left=", InpLeftBars, ", Right=", InpRightBars);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Returns true if a PIVOT HIGH is confirmed at the given shift.   |
   //| Uses the configured InpLeftBars / InpRightBars (8 / 3).         |
   //+------------------------------------------------------------------+
   bool              IsPivotHigh(int shift)
     {
      if(shift < InpRightBars) return false;
      if(shift + InpLeftBars >= LookbackBars) return false;
      return IsFractalHigh(shift, InpLeftBars, InpRightBars);
     }

   //+------------------------------------------------------------------+
   //| Returns true if a PIVOT LOW is confirmed at the given shift.    |
   //+------------------------------------------------------------------+
   bool              IsPivotLow(int shift)
     {
      if(shift < InpRightBars) return false;
      if(shift + InpLeftBars >= LookbackBars) return false;
      return IsFractalLow(shift, InpLeftBars, InpRightBars);
     }

   //+------------------------------------------------------------------+
   //| Fills an SFractalPeak with the OHLC data of the candle at shift.|
   //| marketDay is the current market-day counter (attached by caller)|
   //+------------------------------------------------------------------+
   void              GetCandleInfo(int shift, int marketDay, SFractalPeak &out)
     {
      out.time        = iTime(m_symbol, PERIOD_CURRENT, shift);
      out.openPrice   = iOpen(m_symbol, PERIOD_CURRENT, shift);
      out.closePrice  = iClose(m_symbol, PERIOD_CURRENT, shift);
      out.highPrice   = iHigh(m_symbol, PERIOD_CURRENT, shift);
      out.lowPrice    = iLow(m_symbol, PERIOD_CURRENT, shift);
      out.marketDay   = marketDay;
      out.price       = out.highPrice; // default: high (resistance usage)
     }
  };

//+------------------------------------------------------------------+
#endif  // __OTTO_MARKET_STRUCTURE__

