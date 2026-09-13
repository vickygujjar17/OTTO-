//+------------------------------------------------------------------+
//|                                              COttoRiskManager.mqh |
//|                 MODULE — Risk Sizing (RiskPercent% or Fixed $)   |
//|              OTTO EA — Institutional risk manager                |
//+------------------------------------------------------------------+
#property copyright "OTTO EA"
#property version   "4.83"

#ifndef __OTTO_RISK_MANAGER__
#define __OTTO_RISK_MANAGER__

#include "OttoDefines.mqh"

//+------------------------------------------------------------------+
//| COttoRiskManager class                                           |
//| Calculates lot size for an exact risk amount. Mirrors the Pine   |
//| "fixed $25 risk" via InpFixedRiskUSD, else uses institutional    |
//| RiskPercent of the lower of Balance/Equity.                      |
//+------------------------------------------------------------------+
class COttoRiskManager
  {
private:
   string            m_symbol;
   double            m_tickValue;           // Cached SYMBOL_TRADE_TICK_VALUE
   double            m_tickSize;            // Cached SYMBOL_TRADE_TICK_SIZE
   double            m_volumeStep;          // Cached SYMBOL_VOLUME_STEP
   double            m_volumeMin;           // Cached SYMBOL_VOLUME_MIN
   double            m_volumeMax;           // Cached SYMBOL_VOLUME_MAX
   int               m_digits;              // Cached SYMBOL_DIGITS

   double            m_lastRiskAmount;
   double            m_lastLotSize;
   int               m_tradesCalculated;

   //+------------------------------------------------------------------+
   //| Refreshes symbol properties from the market                      |
   //+------------------------------------------------------------------+
   bool              RefreshSymbolProperties(void)
     {
      m_tickValue  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_tickSize   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_volumeStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      m_volumeMin  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_volumeMax  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_digits     = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      if(m_tickValue <= 0 || m_tickSize <= 0 || m_volumeStep <= 0)
        {
         Print("[RiskManager] ERROR: Invalid symbol properties for ", m_symbol,
               " | TickVal=", m_tickValue,
               " | TickSize=", m_tickSize,
               " | VolStep=", m_volumeStep);
         return false;
        }
      return true;
     }

   //+------------------------------------------------------------------+
   //| Resolves the account-currency risk capital for this trade       |
   //+------------------------------------------------------------------+
   double            GetRiskMoney(void)
     {
      // Option A: fixed $ risk per trade (Pine fixed_risk_usd = 25)
      if(InpFixedRiskUSD > 0.0)
         return InpFixedRiskUSD;

      // Option B: 0.25% risk of LIVE ACCOUNT EQUITY (universal, Forex & Gold)
      double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      return accountEquity * (RiskPercent / 100.0);
     }

   //+------------------------------------------------------------------+
   //| Rounds a lot size to the nearest valid volume step              |
   //+------------------------------------------------------------------+
   double            NormalizeLotSize(double rawLot)
     {
      if(m_volumeStep <= 0)
         return rawLot;
      double steps = MathFloor(rawLot / m_volumeStep);   // strict round-DOWN, never overshoot risk
      double normalized = steps * m_volumeStep;
      normalized = MathMax(m_volumeMin, MathMin(m_volumeMax, normalized));
      return normalized;
     }


public:
   //+------------------------------------------------------------------+
   //| Public wrapper for NormalizeLotSize (round-down volume step)      |
   //+------------------------------------------------------------------+
   double            NormalizeLot(double rawLot)
     {
      return NormalizeLotSize(rawLot);
     }

   //+------------------------------------------------------------------+
   //| Exact lot size to risk `riskPct`% of LIVE EQUITY over the given  |
   //| SL distance (price). Uses MathFloor to volume step + min/max clamp|
   //| Returns lot (>=0). Returns 0.0 when below min lot (=> skip tier).|
   //+------------------------------------------------------------------+
   double            RiskPctLotSize(double riskPct, double slDistPrice)
     {
      if(!RefreshSymbolProperties()) return 0.0;
      if(riskPct <= 0.0 || slDistPrice <= 0.0) return 0.0;

      double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskMoney = accountEquity * (riskPct / 100.0);
      double slPoints  = slDistPrice / m_tickSize;
      if(slPoints <= 0.0 || m_tickValue <= 0.0) return 0.0;

      double rawLot = riskMoney / (slPoints * m_tickValue);
      double steps  = MathFloor(rawLot / m_volumeStep);
      double lot    = steps * m_volumeStep;

      // Hard safety: never exceed target risk even after clamping up
      double actualRiskMoney = lot * slPoints * m_tickValue;
      if(actualRiskMoney > (riskMoney * 1.05) && lot > m_volumeMin)
         lot -= m_volumeStep;

      if(lot > m_volumeMax)  lot = m_volumeMax;
      if(lot < m_volumeMin)  return 0.0;   // below min -> cannot size this tier
      return lot;
     }


   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
                     COttoRiskManager(void)
     {
      m_symbol            = "";
      m_tickValue         = 0;
      m_tickSize          = 0;
      m_volumeStep        = 0;
      m_volumeMin         = 0;
      m_volumeMax         = 0;
      m_digits            = 0;
      m_lastRiskAmount    = 0;
      m_lastLotSize       = 0;
      m_tradesCalculated  = 0;
     }

   //+------------------------------------------------------------------+
   //| Destructor                                                       |
   //+------------------------------------------------------------------+
                    ~COttoRiskManager(void)
     {
     }

   //+------------------------------------------------------------------+
   //| Initialize — cache symbol properties                             |
   //+------------------------------------------------------------------+
   bool              Initialize(string symbol)
     {
      m_symbol = symbol;
      if(!RefreshSymbolProperties())
         return false;

      if(EnableLogging)
         Print("[RiskManager] Initialized for ", m_symbol,
               " | TickVal=", DoubleToString(m_tickValue, m_digits),
               " | TickSize=", DoubleToString(m_tickSize, m_digits),
               " | VolMin=", DoubleToString(m_volumeMin, 2),
               " | VolMax=", DoubleToString(m_volumeMax, 2),
               " | VolStep=", DoubleToString(m_volumeStep, 2),
               " | Risk: ", (InpFixedRiskUSD > 0 ? ("$" + DoubleToString(InpFixedRiskUSD,2)) : (DoubleToString(RiskPercent,2) + "% of acct")));
      return true;
     }

   //+------------------------------------------------------------------+
   //| Core lot-size calculation. Returns exact lot to risk the target  |
   //| amount, or 0.0 to signal a prop-firm abort.                      |
   //+------------------------------------------------------------------+
   double            CalculateLotSize(double entryPrice, double stopLossPrice)
     {
      if(!RefreshSymbolProperties())
         return m_volumeMin;

      double riskMoney = GetRiskMoney();
      double slDistancePrice  = MathAbs(entryPrice - stopLossPrice);
      double slDistancePoints = slDistancePrice / m_tickSize;

      if(slDistancePoints <= 0)
        {
         Print("[RiskManager] ERROR: SL distance is zero or negative!");
         return m_volumeMin;
        }

      double tickValuePerLot = m_tickValue;
      if(tickValuePerLot <= 0)
        {
         double contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         if(contractSize > 0)
            tickValuePerLot = contractSize * m_tickSize;
         else
           {
            Print("[RiskManager] FATAL: Cannot determine tick value");
            return m_volumeMin;
           }
        }

      double rawLotSize = riskMoney / (slDistancePoints * tickValuePerLot);
      double finalLotSize = NormalizeLotSize(rawLotSize);

      if(finalLotSize < m_volumeMin) finalLotSize = m_volumeMin;
      if(finalLotSize > m_volumeMax) finalLotSize = m_volumeMax;
      if(finalLotSize <= 0) finalLotSize = m_volumeMin;

      // --- STRICT 0.25% ROUND-DOWN ANTI-OVERSHOOT (NEVER exceed risk) ---
      double actualRiskMoney = finalLotSize * slDistancePoints * tickValuePerLot;
      if(actualRiskMoney > (riskMoney * 1.05) && finalLotSize > m_volumeMin)
         finalLotSize -= m_volumeStep;

      // --- PROP FIRM SAFETY CLAMP: verify actual risk % does not exceed limit ---
      double accountCapital = AccountInfoDouble(ACCOUNT_EQUITY);
      double actualRiskPct = (accountCapital > 0)
                             ? (finalLotSize * slDistancePoints * tickValuePerLot) / accountCapital * 100.0
                             : 0.0;
      if(actualRiskPct > SafetyMaxRiskPct)
        {
         if(EnableLogging)
            Print("[RiskManager] SAFETY CLAMP: risk ", DoubleToString(actualRiskPct,2),
                  "% exceeds max ", SafetyMaxRiskPct, "% — aborting (lot=",
                  DoubleToString(finalLotSize,4), ")");
         m_lastRiskAmount = riskMoney;
         m_lastLotSize    = finalLotSize;
         return 0.0; // abort
        }

      m_lastRiskAmount = riskMoney;
      m_lastLotSize    = finalLotSize;
      m_tradesCalculated++;

      return finalLotSize;
     }

   //+------------------------------------------------------------------+
   //| Calculates lot from a pre-computed SL distance in points        |
   //+------------------------------------------------------------------+
   double            CalculateLotSizeFromPoints(double slDistancePoints)
     {
      if(!RefreshSymbolProperties())
         return m_volumeMin;

      double riskMoney = GetRiskMoney();
      double tickValuePerLot = m_tickValue;
      if(tickValuePerLot <= 0)
        {
         double contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         tickValuePerLot = (contractSize > 0) ? contractSize * m_tickSize : 0.01;
        }

      double rawLotSize = riskMoney / (slDistancePoints * tickValuePerLot);
      double finalLotSize = NormalizeLotSize(rawLotSize);
      finalLotSize = MathMax(m_volumeMin, MathMin(m_volumeMax, finalLotSize));
      if(finalLotSize <= 0) finalLotSize = m_volumeMin;
      return finalLotSize;
     }


   //+------------------------------------------------------------------+
   //| Returns the tick value per standard lot (cached)                 |
   //+------------------------------------------------------------------+
   double            GetTickValuePerLot(void) const
     {
      return m_tickValue;
     }

   //+------------------------------------------------------------------+
   //| Returns the tick size (cached)                                   |
   //+------------------------------------------------------------------+
   double            GetTickSize(void) const
     {
      return m_tickSize;
     }

   //+------------------------------------------------------------------+
   //| Returns the symbol digits (cached)                               |
   //+------------------------------------------------------------------+
   int               GetDigits(void) const
     {
      return m_digits;
     }

   //+------------------------------------------------------------------+
   //| Returns minimum volume                                           |
   //+------------------------------------------------------------------+
   double            GetVolumeMin(void) const
     {
      return m_volumeMin;
     }

   //+------------------------------------------------------------------+
   //| Returns maximum volume                                           |
   //+------------------------------------------------------------------+
   double            GetVolumeMax(void) const
     {
      return m_volumeMax;
     }

   //+------------------------------------------------------------------+
   //| Returns volume step                                              |
   //+------------------------------------------------------------------+
   double            GetVolumeStep(void) const
     {
      return m_volumeStep;
     }

   //+------------------------------------------------------------------+
   //| Returns the last calculated risk amount                           |
   //+------------------------------------------------------------------+
   double            GetLastRiskAmount(void) const
     {
      return m_lastRiskAmount;
     }

   //+------------------------------------------------------------------+
   //| Returns the last calculated lot size                              |
   //+------------------------------------------------------------------+
   double            GetLastLotSize(void) const
     {
      return m_lastLotSize;
     }

   //+------------------------------------------------------------------+
   //| Returns total number of lot calculations performed               |
   //+------------------------------------------------------------------+
   int               GetTradesCalculated(void) const
     {
      return m_tradesCalculated;
     }

   //+------------------------------------------------------------------+
   //| Checks if there is sufficient margin for a given lot size        |
   //+------------------------------------------------------------------+
   bool              HasSufficientMargin(double lotSize)
     {
      double marginRequired;
      if(!OrderCalcMargin(ORDER_TYPE_BUY, m_symbol, lotSize,
                          SymbolInfoDouble(m_symbol, SYMBOL_ASK), marginRequired))
        {
         Print("[RiskManager] ERROR: OrderCalcMargin failed");
         return false;
        }
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      bool sufficient = (freeMargin > marginRequired * 1.1); // 10% buffer
      if(!sufficient && EnableLogging)
         Print("[RiskManager] Insufficient margin: Required=",
               DoubleToString(marginRequired, 2),
               " Free=", DoubleToString(freeMargin, 2));
      return sufficient;
     }
  };

//+------------------------------------------------------------------+
#endif  // __OTTO_RISK_MANAGER__
