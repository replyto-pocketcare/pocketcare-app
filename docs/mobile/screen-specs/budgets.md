# Screen spec — Budgets

> Source: `apps/web/app/budgets/page.tsx` (read 2026-08-05, 392 lines).

## Data model (`budgets` table, `BudgetLike`)

`id, name (nullable), period ("daily"|"weekly"|"monthly"|"yearly"), start_date/end_date (nullable — set together for a one-off custom range, both null for recurring), limit_amount (minor units), currency, threshold_pct (1-100), alert_time_utc ("HH:MM"), rollover`. Scope (which spend counts toward this budget) lives in junction tables, not columns: `budget_categories` (budget↔category, expense-kind only) and `budget_labels` (budget↔label, find-or-create by name). No scope rows at all = "all spending" (`t("allSpending")`).

## List screen

- Header: "Budgets" title + "+ New budget" button.
- Empty state: centered card, ◔ glyph, "no budgets yet" copy, "+ Create first" CTA.
- Each row (`BudgetRow`): title = `budget.name` if set, else the scope label (joined category+label names, or "All spending"); subtitle = timeframe — custom range shows `{start} – {end}` (day+month), recurring shows `{period label} · {current window label}` (the window is computed client-side per period, see `periodWindow()` — e.g. monthly = 1st to last day of current month). Progress bar (color: `--negative` if over limit, `--warning` if ≥ threshold%, else `--positive`) + `spent`/`remaining-or-over` line below it (`spentThisPeriod()` from the shared `@sanvya/budget` `budgetProgress()` helper — reuse the existing repo method, don't recompute). A cumulative-spend-vs-limit area chart underneath (dashed reference line at the limit) — **defer the chart this pass** (matches this session's established "chart = its own follow-up" precedent from Dashboard's sparkline vs. tile catalog), track as a new TODO row.
- Edit affordance inline (not a separate screen/modal on web — an in-place expand within the same card) with Delete (confirm dialog, soft-delete).

## Create/Edit form fields (same field set both times)

1. Name (optional, `FloatingInput`) — falls back to the scope label when blank.
2. Limit amount + currency picker (`INR/USD/EUR/GBP/JPY/AUD/CAD/SGD/AED`) — **currency is fixed once created** (edit form has no currency picker, only create does).
3. Alert threshold: "% of limit" number field (1-100, default 80) + a time-of-day picker (default "09:00", stored as UTC via `localToUtcTime`/read back via `utcToLocalTime` — **do this conversion**, don't store local time raw).
4. Categories (optional): multi-select from expense-kind categories.
5. Labels (optional): multi-select/free-text-add, same `LabelPicker` pattern as Transactions' label picker.
6. Timeframe: two chip-toggled modes —
   - **Recurring** (default): period chips (Daily/Weekly/Monthly/Yearly).
   - **Custom dates**: start+end date pickers (end has `min = start`).
   Editing an existing custom-dated budget hides the period chips entirely (can't convert custom→recurring in the edit form — matches web's `{!budget.start_date && <period chips>}` guard).
7. Validation: limit must be > 0; custom mode requires both dates.

## Port notes

- Android's `BudgetsViewModel.kt` (pre-existing, not written this session) only supports the list read path (id/name/period/spentFormatted/limitFormatted/progress) and hardcodes `categories = listOf("All")` with a comment admitting the real category-name lookup isn't wired — needs labels support added too, plus create/update/delete methods (mirror `LedgerRepository`'s `watchCategories()`/`watchLabels()` pattern already built for Transactions), plus the junction-table scope read (`budget_categories`/`budget_labels` joins) instead of the placeholder.
- iOS's `BudgetsView.swift`/`BudgetsViewModel.swift` (pre-existing, never checked against this spec) needs the same audit Accounts/Transactions got — check before assuming any of create/edit/delete/categories/labels/custom-dates/threshold-time actually work.
- `BudgetRepository` (both platforms) already has `list()`/`spentThisPeriod()` — needs `create`/`update`/`delete`/scope-junction read+write added, following `LedgerRepository`'s established `writeTransaction`/`getAll`/`mapper` conventions exactly (this session's repeated real-compiler lesson: match the established SDK call shape file-for-file, don't improvise a new one).

## Explicitly deferred (own TODO rows, not silently dropped)

- Cumulative spend-vs-limit area chart (both list-row chart and its per-day query).
- Rollover (`rollover` column exists, no UI touches it on web either — genuinely unused today, not a mobile gap).
