//+------------------------------------------------------------------+
//|                                                 COttoNewsFilter.mqh |
//|              MODULE — High-Impact News Shield (5 min window)     |
//|              OTTO EA — Institutional news blackout filter        |
//+------------------------------------------------------------------+
#property copyright "OTTO EA"
#property version   "4.83"

#ifndef __OTTO_NEWS_FILTER__
#define __OTTO_NEWS_FILTER__

#include "OttoDefines.mqh"

//+------------------------------------------------------------------+
//| COttoNewsFilter class                                            |
//| Pauses new order placement during high-impact news windows.      |
//| Mirrors the Pine "sim_news_shield" gate using the real broker    |
//| MQL5 calendar API.                                               |
//+------------------------------------------------------------------+
class COttoNewsFilter
  {
private:
   string            m_symbol;               // Trading symbol (e.g. "GBPUSD")
   string            m_baseCurrency;         // Base currency (e.g. "GBP")
   string            m_profitCurrency;       // Profit/counter currency (e.g. "USD")

   // --- News blackout state ---
   bool              m_inBlackout;           // Currently inside a blackout window
   datetime          m_blackoutEnd;          // When the current blackout ends
   datetime          m_lastCheck;            // Last bar time we checked

   // --- Calendar country mapping ---
   string            m_countryCodes[];       // Country codes relevant to this pair
   int               m_countryCount;
   long              m_baseCountryId;        // Numeric country ID for base currency
   long              m_profitCountryId;      // Numeric country ID for profit currency

   // --- Counters for logging ---
   int               m_blackoutsTriggered;   // Total blackout events since init

   //+------------------------------------------------------------------+
   //| Maps a currency code to its country name for Calendar functions |
   //+------------------------------------------------------------------+
   string            MapCurrencyToCountry(string currency)
     {
      if(currency == "USD") return "United States";
      if(currency == "EUR") return "European Union";
      if(currency == "GBP") return "United Kingdom";
      if(currency == "JPY") return "Japan";
      if(currency == "AUD") return "Australia";
      if(currency == "NZD") return "New Zealand";
      if(currency == "CAD") return "Canada";
      if(currency == "CHF") return "Switzerland";
      if(currency == "CNY") return "China";
      if(currency == "XAU") return "United States";
      return "";
     }

   //+------------------------------------------------------------------+
   //| Converts a currency code to an ISO 2-letter code (diagnostics)  |
   //+------------------------------------------------------------------+
   string            GetISOCode(string currency)
     {
      if(currency == "USD") return "US";
      if(currency == "EUR") return "EU";
      if(currency == "GBP") return "GB";
      if(currency == "JPY") return "JP";
      if(currency == "AUD") return "AU";
      if(currency == "NZD") return "NZ";
      if(currency == "CAD") return "CA";
      if(currency == "CHF") return "CH";
      if(currency == "CNY") return "CN";
      if(currency == "XAU") return "US";
      return "";
     }

   //+------------------------------------------------------------------+
   //| Resolves a numeric country ID from a country name string        |
   //+------------------------------------------------------------------+
   long              ResolveCountryId(string countryName)
     {
      if(countryName == "")
         return -1;
      for(int id = 1; id <= 100; id++)
        {
         MqlCalendarCountry c;
         ResetLastError();
         if(CalendarCountryById(id, c))
           {
            if(c.name == countryName)
               return id;
           }
        }
      return -1;
     }


   //+------------------------------------------------------------------+
   //| Scans the broker calendar for a high-impact blackout window     |
   //+------------------------------------------------------------------+
   bool              ScanCalendarForBlackout(string            currency,
                                             long              targetCountryId,
                                             datetime          fromTime,
                                             datetime          toTime,
                                             datetime         &outBlackoutStart,
                                             datetime         &outBlackoutEnd)
     {
      if(targetCountryId < 0)
         return false;

      MqlCalendarEvent event;
      MqlCalendarValue eventValues[];
      datetime dayStart = fromTime;
      datetime dayEnd   = fromTime + 86400 * 2; // 2 days ahead

      int eventsToCheck = 200; // Window of potential event IDs
      for(int eventId = 1; eventId <= eventsToCheck; eventId++)
        {
         ResetLastError();
         if(!CalendarEventById(eventId, event))
            continue;

         // Only HIGH-impact events relevant to this currency
         if(event.country_id == 0 || event.country_id == targetCountryId)
           {
            if(event.importance != CALENDAR_IMPORTANCE_HIGH)
               continue;

            if(CalendarValueHistoryByEvent(eventId, eventValues, dayStart, dayEnd))
              {
               int valueCount = ArraySize(eventValues);
               for(int v = 0; v < valueCount; v++)
                 {
                  datetime eventTime = eventValues[v].time;
                  if(eventTime > 0)
                    {
                     datetime blackoutStart = eventTime - (NewsMinutesBefore * 60);
                     datetime blackoutEnd   = eventTime + (NewsMinutesAfter * 60);
                     datetime now = TimeCurrent();
                     if(now >= blackoutStart && now <= blackoutEnd)
                       {
                        outBlackoutStart = blackoutStart;
                        outBlackoutEnd   = blackoutEnd;
                        return true;
                       }
                    }
                 }
              }
           }
        }
      return false;
     }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
                     COttoNewsFilter(void)
     {
      m_symbol          = "";
      m_baseCurrency    = "";
      m_profitCurrency  = "";
      m_inBlackout      = false;
      m_blackoutEnd     = 0;
      m_lastCheck       = 0;
      m_countryCount    = 0;
      m_baseCountryId   = -1;
      m_profitCountryId = -1;
      m_blackoutsTriggered = 0;
     }

   //+------------------------------------------------------------------+
   //| Destructor                                                       |
   //+------------------------------------------------------------------+
                    ~COttoNewsFilter(void)
     {
      ArrayFree(m_countryCodes);
     }


   //+------------------------------------------------------------------+
   //| Initialize — parse symbol currencies and resolve country IDs    |
   //+------------------------------------------------------------------+
   bool              Initialize(string symbol)
     {
      m_symbol = symbol;

      int len = StringLen(symbol);
      if(len < 6)
        {
         Print("[NewsFilter] ERROR: Invalid symbol length for ", symbol);
         return false;
        }

      m_baseCurrency   = StringSubstr(symbol, 0, 3);
      m_profitCurrency = StringSubstr(symbol, 3, 3);

      if(len >= 7 && (StringSubstr(symbol, 0, 4) == "USDM" ||
                      StringSubstr(symbol, 0, 4) == "EURM"))
        {
         Print("[NewsFilter] WARNING: Non-standard symbol format: ", symbol);
        }

      ArrayResize(m_countryCodes, 2);
      m_countryCodes[0] = m_baseCurrency;
      m_countryCodes[1] = m_profitCurrency;
      m_countryCount    = 2;

      m_baseCountryId   = ResolveCountryId(MapCurrencyToCountry(m_baseCurrency));
      m_profitCountryId = ResolveCountryId(MapCurrencyToCountry(m_profitCurrency));

      if(EnableLogging)
         Print("[NewsFilter] Initialized for ", m_symbol,
               " | Currencies: ", m_baseCurrency, " + ", m_profitCurrency,
               " | Country IDs: ", m_baseCountryId, " / ", m_profitCountryId);

      return true;
     }

   //+------------------------------------------------------------------+
   //| Main update — called every tick; checks the calendar once/bar   |
   //+------------------------------------------------------------------+
   void              Update(void)
     {
      datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
      if(currentBarTime == m_lastCheck)
         return;
      m_lastCheck = currentBarTime;

      if(!EnableNewsFilter)
        {
         m_inBlackout = false;
         return;
        }

      // If already in a blackout, check whether it has expired
      if(m_inBlackout)
        {
         if(TimeCurrent() >= m_blackoutEnd)
           {
            m_inBlackout = false;
            if(EnableLogging)
               Print("[NewsFilter] Blackout ended at ", TimeToString(m_blackoutEnd));
           }
         return;
        }

      // Scan upcoming high-impact events for both currencies
      datetime now = TimeCurrent();
      datetime lookAhead = now + 86400; // 24h ahead
      bool foundBlackout = false;
      datetime earliestBlackoutStart = 0;
      datetime earliestBlackoutEnd   = 0;

      for(int c = 0; c < m_countryCount && !foundBlackout; c++)
        {
         if(GetISOCode(m_countryCodes[c]) == "")
            continue;

         long targetCountryId = (c == 0) ? m_baseCountryId : m_profitCountryId;
         m_inBlackout = ScanCalendarForBlackout(m_countryCodes[c], targetCountryId,
                                                now, lookAhead,
                                                earliestBlackoutStart, earliestBlackoutEnd);
         if(m_inBlackout)
           {
            m_blackoutEnd = earliestBlackoutEnd;
            m_blackoutsTriggered++;
            if(EnableLogging)
               Print("[NewsFilter] BLACKOUT ACTIVE for ", m_symbol,
                     " | ", m_countryCodes[c], " event",
                     " | Until: ", TimeToString(m_blackoutEnd),
                     " | Total blackouts: ", m_blackoutsTriggered);
            foundBlackout = true;
            break;
           }
        }

      if(!foundBlackout)
         m_inBlackout = false;
     }

   //+------------------------------------------------------------------+
   //| Returns true if we are currently in a news blackout window      |
   //+------------------------------------------------------------------+
   bool              IsInNewsBlackout(void) const
     {
      return m_inBlackout;
     }

   //+------------------------------------------------------------------+
   //| Returns the datetime when the current blackout ends (or 0)      |
   //+------------------------------------------------------------------+
   datetime          GetNextBlackoutEnd(void) const
     {
      return m_blackoutEnd;
     }

   //+------------------------------------------------------------------+
   //| Returns the blackout trigger counter                             |
   //+------------------------------------------------------------------+
   int               GetBlackoutCount(void) const
     {
      return m_blackoutsTriggered;
     }
  };

//+------------------------------------------------------------------+
#endif  // __OTTO_NEWS_FILTER__

