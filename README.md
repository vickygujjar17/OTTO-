# OTTO EA

MetaTrader 5 Expert Advisor — MQL5 port of the Pine Script `prop_guard_tester.pine`
master build. **Current base: v4.83**

## Layout

| File | Role |
|---|---|
| `OttoDefines.mqh` | Central enums, structs and `input` parameters |
| `COttoNewsFilter.mqh` | News shield |
| `COttoRiskManager.mqh` | Position sizing / risk |
| `COttoMarketStructure.mqh` | Market-day counter, structure helpers |
| `COttoBlockManager.mqh` | Wick1+Wick2 S/R block lifecycle and vetoes |
| `COttoOrderManager.mqh` | Order placement, pyramiding basket, journal hooks |
| `COttoCorrelationFilter.mqh` | Cross-symbol correlation veto |
| `COttoTradeManager.mqh` | Cut / cost-BE / lock3 / ATR trail / pyramiding |
| `COttoJournal.mqh` | Human-readable trade journal |
| `otto.mq5` | EA entry point and event handlers |

## Build (strict gate)

Sources are CRLF and the EA resolves its modules through
`#include "../Include/Otto/<file>.mqh"`, so it is compiled from a staged tree
that mirrors the terminal layout:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File _tools\build_check.ps1
```

The gate is only passed on **0 errors, 0 warnings**.

## Line endings

`_tools\normalize_eol.py` rewrites MQL5 sources to strict CRLF byte-safely
(non-ASCII content is preserved exactly):

```powershell
python _tools\normalize_eol.py .            # rewrite
python _tools\normalize_eol.py . --check    # report only
```

## Version policy

Every update bumps `#property version` in **all** `.mqh`/`.mq5` files, the
banner in `OttoDefines.mqh`, and the startup `Print()` banner in `otto.mq5`.