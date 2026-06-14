\# IDEA Money Management EA — Development Handoff

\*\*Date:\*\* June 14, 2026  

\*\*Developer:\*\* Farid Gazani — Omran IDEA  

\*\*Status:\*\* Phases 1–4 complete, Phase 5 (control panel) pending



\---



\## What's Built



\### Phase 1 — Architecture

\- Full MQL5 skeleton with all enums, inputs, globals, and function stubs

\- Input groups: Risk/Lot, SL/TP, Risk-Free/BE, Partial Close, Daily Limit, Visual



\### Phase 2 — Core Engine ✅

\- `NormalizeLot()` — clamps and rounds to symbol volume step

\- `CalculateLotSize(entry, sl)` — risk-based lot sizing from account balance

\- `OpenBuy / OpenSell` — market orders with SL/TP and lot size validation

\- `ClosePosition(ticket, percent)` — full and partial close

\- `CheckDailyLimit()` — dual-mode (% and USD), day rollover via MqlDateTime

\- `OnInit` — fill mode probe (FOK → IOC → RETURN), input validation



\### Phase 3 — Line-Based UI ✅

\- `DrawLines(entry, sl, tp)` — 3 draggable OBJ\_HLINE objects on chart

\- `DeleteLines()` — clean removal on deinit

\- `GetLinePrice(name)` — safe price reader with ObjectFind guard

\- `OnChartEvent` — live label update on drag: Lot / Risk $ / R:R ratio

\- Tested on XAUUSD M3 demo — lines confirmed working



\### Phase 4 — Position Management ✅

\- `ManagePosition()` — loops open positions by magic + symbol

\- `CheckRiskFree()` — two modes: TP1 cross and percent-based trigger

\- `CheckBreakEven()` — pip-based trigger with buffer offset

\- `MoveSL(ticket, newSL)` — safe SL modification with TP preservation



\---



\## What's Remaining



\### Phase 5 — Control Panel (next session)

Floating on-chart panel with:

\- Risk +/− buttons with % / $ toggle

\- Buy / Sell / Set > buttons

\- Pend. Buy / Pend. Sell / Cancel buttons

\- Open Positions collapsible section

\- Status dot (green = trading allowed, red = daily limit hit)



\### Phase 6 — Polish

\- News filter (disable X min before high-impact events)

\- Max daily loss auto-disable

\- Error handling edge cases



\### Phase 7 — Testing

\- Strategy Tester backtest

\- 1–2 week demo forward test



\### Phase 8 — Packaging

\- Clean input descriptions

\- Persian + English user guide

\- Export `.ex5` for distribution



\---



\## Known Issues / Notes

\- `g\_dayStartBalance` fix needed in OnInit (currently may read 0 on first attach)

\- MT5 build ≥ 2361 required for `PositionClosePartial(ulong, double)` overload

\- EA file must live in MT5 `MQL5/Experts/` folder to run — keep repo in sync manually or via symlink

\- Line colors: Entry=blue, SL=red dashed, TP=green dashed



\---



\## Tech Stack

| Layer | Tool |

|---|---|

| Language | MQL5 |

| IDE | MetaEditor (MT5 built-in) |

| AI Assistant | Claude Code |

| Version Control | Git + GitHub |

| Test Account | XAUUSD M3 Demo |



\---



\## File Structure

```

IDEA-Money-Management/

├── src/

│   └── IDEA\_MoneyManagement.mq5   ← main EA source

├── docs/

│   ├── HANDOFF.md                 ← this file

│   ├── user-guide-en.md

│   └── user-guide-fa.md

├── assets/

├── tests/

├── .gitignore

└── README.md

```

