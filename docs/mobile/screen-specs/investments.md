# Investments — screen spec

> Source-verified against `apps/web/app/investments/page.tsx` (321 lines), `apps/web/src/investments/model.ts`, `apps/web/src/investments/write.ts`, and `apps/web/src/investments/AddDialog.tsx` on 2026-08-06 (task #26). Both native platforms had only a dead/stub port before this pass: Android's `InvestmentsViewModel.kt` was constructor-injected with no consuming `Screen.kt` and no nav route (ungrouped placeholder shape, see `ui/UiModels.kt`'s former header comment); iOS's `InvestmentsView.swift`/`InvestmentsViewModel.swift` were real and wired into `MainTabView.swift`, but read-only and ungrouped, with a no-op `Button(action: {})` for "+". Both repositories (`InvestmentsRepository.kt`/`.swift`) also had a real bug: `exchange`/`instrument_type`/`avg_cost` were mapped as non-nullable via non-optional cursor getters despite web's `HoldingRow` treating all three as nullable — a genuine crash risk, fixed this pass alongside the port.

## Data

`holdings` table columns used by the UI: `id`, `account_id`, `symbol`, `exchange` (nullable — only stocks have one), `quantity` (REAL), `avg_cost` (nullable, minor units per unit), `currency`, `auto_fetch` (0/1), `instrument_type` (nullable), `off_list` (0/1 — true for every holding this app creates, since there's no live catalog picker on mobile yet), `name` (nullable), `asset_class` (`stock`/`mf`/`sip`/`crypto`/`fd`/`other`), `current_value` (nullable, minor units — the user-entered value for unpriced holdings), `annual_rate` (nullable, FD % p.a.), `maturity_date` (nullable), `source_account_id` (nullable — set when funded via transfer), `planned_id` (nullable — only set by web's SIP flow, always null from mobile since SIP scheduling is deferred).

A holding lives in an "investment account" — one whose `accounts.type` is `demat`, `stocks`, or `mutual_funds` (`DEMAT_TYPES` in `page.tsx`). "Funding accounts" (for the existing-vs-new choice below) are every OTHER account type, not specifically "savings" — matches web's `balances.filter((b) => !DEMAT_TYPES.includes(b.account.type))` exactly.

## Grouping (`src/investments/model.ts`)

Holdings are bucketed for display: listed stocks group **by exchange** (`ex:NSE`, `ex:BSE`, `ex:OTHER` for a blank/unrecognized exchange); everything else groups **by asset class** (`cls:mf`, `cls:sip`, `cls:crypto`, `cls:fd`, `cls:other`). Groups sort exchanges first (alphabetically), then MF → SIP → Crypto → FD → Other. Each group carries `cost`/`value`/`gain`/`gainPct` subtotals in the portfolio's base currency (hardcoded `"INR"` on both native platforms, matching Dashboard's own `watchNetWorth("INR")` simplification — no user-facing base-currency setting exists yet).

`valuation(holding, quote)`: `cost = avg_cost × quantity`. `value` = a live quote × quantity IF the holding is listed, not off-list, and a quote exists; otherwise `current_value ?? cost`. **Both native ports have no live-quote source** (see Deferred below), so `quote` is always `nil`/`null` — every holding, listed or not, values at `current_value ?? cost`. This is a real, documented simplification: an off-list holding on web behaves identically.

`holdingLabel(holding)`: off-list or unlisted holdings show `name ?? symbol`; listed+on-list holdings show `symbol ?? name`.

## List (top of screen)

- Grand-total card: portfolio value + all-time gain (amount + %, tinted positive/negative), computed via `portfolioTotals(groups)`.
- No investment account yet → an empty state pointing at "add an account" (`accounts/new` route on Android; presumably the equivalent on iOS) instead of the list — the "+" toolbar button is hidden entirely in this state (matches web's `invAccounts.length > 0 &&` gate on the Add button).
- Otherwise: a `GroupTile` per group (label, holdings count, value, cost, gain/gainPct) — tapping one drills in.

## Drill-in (one group)

Web's `DrillIn` is page-local state, not a route — both native ports mirror that with in-screen state (`drilledKey`/`drilledGroup`), not a pushed nav destination. Shows: a back affordance (replaces the hamburger/menu icon while drilled in), the group's holdings as `HoldingTile`s, and a "+ Add to {group}" button that opens the Add sheet/screen prefilled with that group's asset class/exchange.

### HoldingTile ("Zerodha-style")

Left: label + an "untracked" chip when `off_list` (always true from this pass's own writes) + a quantity line (`"{qty} {unitWord}"`, blank for FD/Other). Right: value + gain (tinted). Bottom row: asset-class icon+label (+ exchange for stocks), plus FD-only annual-rate/maturity-date suffixes. Edit (pencil) toggles an inline form (quantity, avg cost, current-value for unpriced classes, annual rate for FD) — matches web's `EditHolding`'s exact field set; `save()` calls the repository's `updateHolding` (quantity/avg_cost/current_value/annual_rate only, matching `write.ts`'s `updateRow("holdings", h.id, {...})`). Delete (trash) confirms, then soft-deletes the holding row only — no reversal of whatever funding transaction created it (an accepted, documented asymmetry, same class as Goals' allocation-delete-doesn't-cascade).

## Add investment (scoped-down port of `AddDialog.tsx`'s `AddInvestmentDialog`)

Real, kept from web: asset-class chips (Stock/MF/SIP/Crypto/FD/Other), investment-account picker (when >1 exists), name/exchange fields, quantity+avg-cost (or a single lump "amount invested" field for FD), FD's rate/maturity fields, a current-value field for unpriced classes, and — **the part that must stay real, not cosmetic** — the existing-vs-new funding choice: "already hold it" books an `adjustment` transaction on the investment account; "fund it now" transfers the cost from a chosen funding account, with an over-funds check against that account's live balance. This mirrors `write.ts`'s `addHolding()` exactly (see CLAUDE.md's golden rule: balances are derived from an append-only ledger — skipping this would silently break ledger integrity for any holding added on mobile).

Deferred from web's dialog: the live instrument catalog picker (`InstrumentPicker`/`ExchangeSelect`, symbol search against a downloaded catalog) — every holding added from mobile is free-text/manual, i.e. always `off_list = true`, `auto_fetch = false`. SIP recurring-transfer setup (`transaction_templates`/`recurring_rules` insert) is also deferred — there is no `sip` parameter in either native `addHolding`.

## Deferred (own follow-up, not built this pass)

- **Live market quotes/LTP** (`src/market/hooks.ts`'s `useMarketData`, the instrument catalog download/`useCatalog`) — every holding values at `current_value ?? cost` instead of a live price. This is the single largest scope cut; it gates the catalog picker, auto-fetch, and the accuracy of "value" for any stock/MF holding whose `current_value` isn't kept manually up to date.
- **Dividend panel** (`src/market/DividendPanel.tsx`, `computeDividendEvents`/`inCurrentFYToDate` from `src/market/dividends.ts`) and the FY-dividend stat card on web's Insights section.
- **Projection panel** (`src/market/ProjectionPanel.tsx`).
- **Allocation donut + gain-bar charts** (`src/investments/Charts.tsx`'s `AllocationDonut`/`GainBars`) — same category as Budgets' deferred spend-vs-limit chart.
- **SIP recurring-transfer setup** (see above) — a SIP holding can be added and tracked, but no automatic recurring debit is scheduled.
- **Live instrument catalog picker** (see above) — every mobile-added holding is `off_list = true`.

## Bugs fixed this pass (repository layer, both platforms)

`InvestmentsRepository.kt`/`.swift`'s `Holding`/`avgCost`/`exchange`/`instrumentType` were mapped as non-nullable via non-optional cursor getters despite the schema and web's own `HoldingRow` treating all three as nullable — a real crash risk for any holding legitimately missing one of those (e.g. a freshly-added FD has no exchange). `current_value` was already the right Kotlin/Swift type but iOS's original mapper is unaffected (already used the optional accessor); Android's used the non-optional one. Both platforms were also missing `off_list`/`source_account_id`/`planned_id` from the `Holding` struct/data class entirely, despite the schema already having all three columns (no `AppSchema`/`PocketCareSchema` change needed — this was purely a repository-mapping gap, not a missing-column issue per CLAUDE.md's "adding a column" checklist).
