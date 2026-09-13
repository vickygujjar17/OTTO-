//+------------------------------------------------------------------+
//|                                              COttoTradeManager.mqh |
//|       MODULE 6 - Dynamic Trade Management (exact Pine v4.70) + Pyr |
//|            OTTO EA - Cut / Cost-BE / Lock3 / ATR Trail / Pyramiding |
//+------------------------------------------------------------------+
#property copyright "OTTO EA"
#property version   "4.83"

#ifndef __OTTO_TRADE_MANAGER__
#define __OTTO_TRADE_MANAGER__

#include "OttoDefines.mqh"
#include "COttoRiskManager.mqh"
#include "COttoOrderManager.mqh"
#include "COttoBlockManager.mqh"
#include "COttoJournal.mqh"

class COttoTradeManager
  {
private:
   string               m_symbol;
   COttoRiskManager    *m_riskManager;
   COttoOrderManager   *m_orderManager;
   COttoBlockManager   *m_blockManager;
   int                  m_tradesManaged;
   int                  m_halfRiskTriggers;
   int                  m_breakevenTriggers;
   int                  m_trailActivations;
   int                  m_stopsHit;

   double            GetCurrentATR(void)
     { return m_blockManager.GetATR(); }

   // Sum per-position commission from the opening deal. POSITION_COMMISSION
   // is deprecated in modern MT5 builds (compiler warning 89), so the value
   // is read from deal history instead — the same convention used by
   // COttoOrderManager::LogClosedTrade().
   double            GetPositionCommission(ulong ticket)
     {
      double comm = 0.0;
      if(ticket == 0) return 0.0;
      for(int i = HistorySelect(0, TimeCurrent()) - 1; i >= 0; i--)
        {
         ulong dt = HistoryDealGetTicket(i);
         if(dt == 0) continue;
         if(HistoryDealGetInteger(dt, DEAL_POSITION_ID) != (long)ticket) continue;
         comm += HistoryDealGetDouble(dt, DEAL_COMMISSION);
        }
      return comm;
     }

   // Sum negative broker friction (commission+swap) across ALL basket tickets
   double            CalcBasketFriction(bool isLong)
     {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tickValue = m_riskManager.GetTickValuePerLot();
      double tickSize  = m_riskManager.GetTickSize();
      if(point <= 0 || tickValue <= 0 || tickSize <= 0) return 0.0;
      double frictionMoney = 0.0;
      
      for(int i = 0; i < m_orderManager.GetBasketCount(); i++)
        {
         SPyramidTranche t;
         if(!m_orderManager.GetBasketTicket(i, t)) continue;
         if(PositionSelectByTicket(t.ticket))
           {
            double comm = GetPositionCommission(t.ticket);
            double swp  = PositionGetDouble(POSITION_SWAP);
            if(comm < 0.0) frictionMoney += MathAbs(comm);
            else if(comm == 0.0) frictionMoney += 7.0 * t.size;
            if(swp  < 0.0) frictionMoney += MathAbs(swp);
           }
        }
      double frictionPoints = (frictionMoney / (tickValue * 1.0)) * tickSize;
      double spread = SymbolInfoDouble(m_symbol, SYMBOL_ASK) - SymbolInfoDouble(m_symbol, SYMBOL_BID);
      return frictionPoints + (spread * 0.5);
     }

public:
   COttoTradeManager(void)
     {
      m_symbol=""; m_riskManager=NULL; m_orderManager=NULL; m_blockManager=NULL;
      m_tradesManaged=0; m_halfRiskTriggers=0; m_breakevenTriggers=0; m_trailActivations=0; m_stopsHit=0;
     }
   ~COttoTradeManager(void) { }

   bool            Initialize(string symbol, COttoRiskManager *rm, COttoOrderManager *om, COttoBlockManager *bm)
     {
      m_symbol=symbol; m_riskManager=rm; m_orderManager=om; m_blockManager=bm;
      return true;
     }

   void            Update(void)
     {
      if(!m_orderManager.HasActiveTrade()) return;
      SActiveTrade trade;
      if(!m_orderManager.GetActiveTradeRef(trade)) return;
      if(!PositionSelectByTicket(trade.ticket)) return;
      double rrUnit = m_orderManager.GetBasketRRUnit();
      if(rrUnit <= 0.0) rrUnit = trade.rrUnit;
      if(rrUnit <= 0.0) rrUnit = trade.initialSLDistance;
      double primaryEntry = m_orderManager.GetPrimaryEntry();
      if(primaryEntry <= 0.0) primaryEntry = trade.entryPrice;
      ENUM_TRADE_DIRECTION dir = m_orderManager.GetBasketDir();
      if(dir == DIR_NONE) dir = trade.direction;

      double atr = GetCurrentATR();
      if(atr <= 0) return;
      double high0 = iHigh(m_symbol, PERIOD_CURRENT, 0);
      double low0  = iLow(m_symbol, PERIOD_CURRENT, 0);
      // LIVE prices every tick (fixes the +1.0R pyramid trigger): LONG=BID, SHORT=ASK
      double liveBid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double liveAsk = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double currentRR = 0.0;
      double desiredSL = trade.currentTrailSL;

      if(dir == DIR_LONG)
        {
         currentRR = (rrUnit > 0) ? (liveBid - primaryEntry) / rrUnit : 0;
         double halfRiskSL = primaryEntry - (0.5 * rrUnit);
         if(currentRR >= InpCutRiskRR && desiredSL < halfRiskSL)
           { desiredSL = halfRiskSL; m_halfRiskTriggers++; }
         if(currentRR >= InpBreakEvenRR && desiredSL < primaryEntry)
           {
            double beOffset = CalcBasketFriction(true);
            double beSL = primaryEntry + beOffset;
            if(desiredSL < beSL) { desiredSL = beSL; m_breakevenTriggers++; }
           }
         if(currentRR >= InpLock3RRR)
           {
            double strictLock = primaryEntry + (3.0 * rrUnit);
            double dynamicTrail = high0 - (InpTrailATRMultiplier * atr);
            double newSL = MathMax(strictLock, dynamicTrail);
            if(newSL > desiredSL) desiredSL = newSL;
           }
        }
      else // SHORT
        {
         currentRR = (rrUnit > 0) ? (primaryEntry - liveAsk) / rrUnit : 0;
         double halfRiskSL = primaryEntry + (0.5 * rrUnit);
         if(currentRR >= InpCutRiskRR && desiredSL > halfRiskSL)
           { desiredSL = halfRiskSL; m_halfRiskTriggers++; }
         if(currentRR >= InpBreakEvenRR && desiredSL > primaryEntry)
           {
            double beOffset = CalcBasketFriction(false);
            double beSL = primaryEntry - beOffset;
            if(desiredSL > beSL) { desiredSL = beSL; m_breakevenTriggers++; }
           }
         if(currentRR >= InpLock3RRR)
           {
            double strictLock = primaryEntry - (3.0 * rrUnit);
            double dynamicTrail = low0 + (InpTrailATRMultiplier * atr);
            double newSL = MathMin(strictLock, dynamicTrail);
            if(newSL < desiredSL) desiredSL = newSL;
           }
        }

      // --- PYRAMID (unified group stop) ---
      // Tranche 2 at +1.0R: add 50%% tranche, move ALL stops to entry +/- 0.5R
      if(currentRR >= InpCutRiskRR && m_orderManager.IsPyramidPending(2))
        {
         if(m_orderManager.AddPyramidTranche(2))
             {
              double g2 = primaryEntry + (dir==DIR_LONG ? (0.5*rrUnit) : -(0.5*rrUnit));
              m_orderManager.ApplyUnifiedSL(g2);
              m_orderManager.LogGroupStop("Tranche 2 (+1.0R) - Half-Risk Lock", g2);
             }
        }
      // Tranche 3 at +2.0R: add 25%% tranche, move ALL stops to cost-covering BE
      if(currentRR >= InpBreakEvenRR && m_orderManager.IsPyramidPending(3))
        {
         double beOffset = CalcBasketFriction(dir==DIR_LONG);
         double groupBE = primaryEntry + (dir==DIR_LONG ? beOffset : -beOffset);
         if(m_orderManager.AddPyramidTranche(3))
              {
               m_orderManager.ApplyUnifiedSL(groupBE);
               m_orderManager.LogGroupStop("Tranche 3 (+2.0R) - Cost-Covering Breakeven", groupBE);
              }
        }
      // Dynamic ATR Trail at +3.0R: apply SAME trailing SL to every ticket
      if(currentRR >= InpLock3RRR)
         m_orderManager.ApplyUnifiedSL(desiredSL);

      // --- Push the primary stop to the broker (single path, unified) ---
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(MathAbs(desiredSL - trade.currentTrailSL) > point)
        {
         if(m_orderManager.ModifySL(trade.ticket, desiredSL))
           {
            m_orderManager.SetActiveTradeSL(desiredSL);
            if(currentRR >= InpLock3RRR) m_trailActivations++;
           }
        }
      m_tradesManaged++;
     }

   void            SyncTradeState(void)
     {
      if(!m_orderManager.HasActiveTrade()) return;
      SActiveTrade trade;
      if(!m_orderManager.GetActiveTradeRef(trade)) return;
      if(trade.rrUnit <= 0.0) trade.rrUnit = trade.initialSLDistance;
      double price = (trade.direction == DIR_LONG) ? SymbolInfoDouble(m_symbol, SYMBOL_BID) : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double rr = (trade.rrUnit > 0) ? ((trade.direction == DIR_LONG ? price - trade.entryPrice : trade.entryPrice - price) / trade.rrUnit) : 0.0;
      ENUM_TRAIL_STEP step = STEP_NONE;
      if(rr >= InpLock3RRR)        step = STEP_TRAILING;
      else if(rr >= InpBreakEvenRR) step = STEP_BREAKEVEN;
      else if(rr >= InpCutRiskRR)   step = STEP_HALF_RISK;
      m_orderManager.SetActiveTradeStep(step);
      m_orderManager.SetActiveTradeHighWatermark(price);
     }

   int               GetTradesManaged(void) const     { return m_tradesManaged; }
   int               GetHalfRiskTriggers(void) const  { return m_halfRiskTriggers; }
   int               GetBreakevenTriggers(void) const { return m_breakevenTriggers; }
   int               GetTrailActivations(void) const  { return m_trailActivations; }
   int               GetStopsHit(void) const          { return m_stopsHit; }
  };

//+------------------------------------------------------------------+
#endif  // __OTTO_TRADE_MANAGER__