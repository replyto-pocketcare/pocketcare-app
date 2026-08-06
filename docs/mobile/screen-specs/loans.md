# Loans — screen spec

> Source-verified against `apps/web/app/loans/page.tsx` (244 lines), `apps/web/app/loans/[id]/page.tsx` (484 lines), `apps/web/src/loans/ui.tsx`, `apps/web/src/loans/funding.ts`, and `packages/core/finance/src/index.ts` on 2026-08-06 (task #27/#41/#42). Android had no loan screens at all before this pass (`LoansViewModel.kt` was constructor-injected dead code — no consuming `Screen.kt`, no nav route, a placeholder `"Day N"` next-due string). iOS's `LoansView.swift`/`LoansViewModel.swift` were real and wired into `MainTabView.swift`, but read-only with non-optional access on now-nullable `Loan` fields (a real crash risk once the repository was fixed to match web's actually-nullable columns), a non-functional "Mark EMI Paid" `.alert` with a literal `// TODO: Handle confirm`, and a `"Loans & Recurring"` title that appears to be invented drift merging with a separate, unbuilt "Recurring" nav item (same class of bug as the earlier-fixed Goals/Cashflow merge).

## Data

`loans` table columns used by the UI: `id`, `lender` (nullable), `principal`, `currency`, `interest_rate` (nullable), `tenure_months` (nullable — absent for some variable-rate loans), `emi_amount` (nullable — absent for variable-rate loans, computed for fixed via `emiFromPrincipal`), `start_date` (nullable), `emis_paid` (nullable — legacy count-only fallback, see below), `emi_payments` (nullable JSON — the real per-EMI paid-on-date source of truth), `emi_due_day` (nullable, 1-31), `auto_mark_paid` (0/1), `rate_type` (nullable, `"fixed"`/`"variable"`), `emi_amounts` (nullable JSON — variable-rate loans' per-month EMI amounts, `{ "1": amountMinor }`), `funding_account_id` (nullable — remembered from the last mark-paid confirm), `alert_time_utc` (nullable). Every one of these except `id`/`principal`/`currency`/`auto_mark_paid` is genuinely nullable per web's own `Loan` interface — both repositories originally mapped several as non-nullable via non-optional cursor getters, a real crash risk fixed this pass (same bug class as Budgets/Investments).

## EMI domain math (`packages/core/finance/src/index.ts`, ported verbatim)

- `emiFromPrincipal(principal, annualRatePct, tenureMonths)`: standard reducing-balance EMI, `EMI = P·r·(1+r)^n / ((1+r)^n − 1)`, `r` = monthly rate. 0% rate gives flat `P/n`. Returns 0 for non-positive tenure.
- `amortizationSchedule(principal, annualRatePct, emi, maxMonths)`: month-by-month interest/principal/balance breakdown, capped at 1200 months, empty if the EMI can't cover the first month's interest; final row is a partial payment that exactly zeroes the balance.
- `emiDueDate(startIso, dueDay, emiNo)`: due date of a 1-based EMI number. First EMI is the first occurrence of `dueDay` on/after the start date (rolls to next month if the start date's own day is already past `dueDay`); subsequent EMIs are one calendar month later, day clamped to the month length (a 31 due-day lands on Feb 28/29).
- `effectivePaidEmis(manual, totalEmis, autoMark, startIso, dueDay, asOfIso)`: the union of manually-marked EMI numbers and (if `autoMark`) every EMI whose due date has passed as of `asOfIso` — **derived, never persisted**, so toggling auto-mark off instantly reverts the auto-marked ones.
- All money is integer minor units; every intermediate rounds half-away-from-zero (`Math.round` in TS, matching Kotlin's `Math.round(Double): Long` and Swift's default `.rounded()` for the always-non-negative values these functions handle).

Ported verbatim to `packages/domain/loans/LoansModel.kt` (Android) and `Domain/Sources/Domain/LoansModel.swift` (iOS).

## `emis_paid` legacy fallback

Pre-per-EMI-tracking rows have only a plain paid-count in `emis_paid`, no `emi_payments` map. `paidCount()`/`buildUiModel()` treat an empty `emi_payments` with `emis_paid > 0` as "the first N EMIs are manually paid" (`1..emisPaid`), matching web's page-local `paidCount()` exactly.

## List (`loans/page.tsx`)

Total-EMI card (base-currency-converted sum of every loan's `emi_amount`, matching web's `conv()`), then a card per loan: lender, Active/Closed pill (`tenure > 0 && remaining === 0` ⇒ Closed), a date-range or rate string (`loanRange()`: `"Mar '26 – Nov '26"`, falls back to `"{rate}% p.a."` with no tenure), paid-count text, a progress bar (hidden if no tenure), principal, EMI amount (`"Varies"` for variable-rate with no fixed EMI). Empty state points at "Add first loan".

## Add loan (`AddLoan` modal)

Lender, fixed/variable interest-type chips, principal + tenure + rate + EMI (EMI auto-calculated for fixed via `emiFromPrincipal`, user-overridable — an "Auto-calculated EMI was X / Use it" toggle lets them revert), start date, due day (1-31), alert time, funding-account picker (every non-investment account, credit cards sorted first — `ORDER BY (type = 'credit_card') DESC, created_at`; "Not linked" is a first-class choice meaning the user marks each EMI paid manually), auto-mark-paid checkbox. Requires a lender name or a principal. Loans are always created in the base currency (`"INR"` hardcoded on both native ports, matching Dashboard/Investments' own simplification — no per-loan currency picker exists on web either).

## Loan detail (`[id]/page.tsx`)

Summary cards (principal / monthly EMI / interest rate / EMIs paid), a next-due/remaining strip (variable loans show "paid so far" instead of "total interest"), an auto-mark-paid toggle (only shown once there's a schedule), then either:
- **Fixed-rate**: the full `amortizationSchedule` as stacked EMI cards (principal/interest or balance per row, depending on whether the rate is >0%).
- **Variable-rate**: a month-by-month list (1..max known month) where each row has an inline "EMI this month" amount field (`setAmount`) since there's no fixed schedule to compute.

Each row shows a status dot/pill (paid / auto-marked / due) and a due-or-paid-on date. Tapping "Mark paid" on a due row opens the mark-paid sheet; tapping a paid chip undoes it (`setManualPaid(month, null)`).

### Mark-paid (`MarkPaidDialog`)

Paid-on date (defaults today) + an optional funding-account picker (defaults to the loan's remembered `funding_account_id`, "Don't record" is first-class). Confirming: (1) writes `emi_payments[month] = paidOnIso` and bumps `emis_paid` to the new manual-paid count — a real ledger write, not deferred, per CLAUDE.md's golden rule that balances derive from an append-only ledger; (2) if an account was chosen and the row has a real EMI amount, posts a real `expense` transaction on that account (`emiDescription(emiNo, lender)` = `` `EMI #${emiNo}${lender ? ` — ${lender}` : ""}` `` as the description, occurring at noon UTC on the paid-on date) and remembers the chosen account as the loan's new `funding_account_id` (`setLoanFundingAccount` on web — mobile always uses the real `funding_account_id` column instead of web's localStorage fallback, which predates that column).

### Edit / delete

`EditLoan` is the same field set as Add minus the funding-account/auto-mark fields (those only ever change via a mark-paid confirm or the add form, matching web exactly — funding account and auto-mark are absent from web's own edit form too). Delete confirms, then soft-deletes the loan row only (no cascade to its EMI history, same "accepted asymmetry" class as Goals' allocation-delete).

## Deferred (own follow-up, not built this pass)

- **`autoPost.ts`** — background EMI auto-posting (a scheduled job that posts the expense transaction automatically once an EMI's due date passes, for auto-mark loans with a linked funding account). No reliable background execution context exists on mobile without additional infra (a native background-task/WorkManager setup); the manual mark-paid flow above is real and unaffected.
- **`settleEmis.ts`** — matching a credit-card statement settlement back to the EMI(s) it covers. Complex cross-feature (touches Credit Cards, not yet built — task #29); its own follow-up once Credit Cards lands.
- Auto-post's dedupe check (matching `emiDescription()` against existing transactions to avoid double-posting) is irrelevant here since the manual mark-paid flow does no dedupe check either, matching web's own manual flow exactly.

## Platform notes

- **Android**: `LoansScreen.kt` (list) → `LoanDetailScreen.kt` (detail, with `EditLoanScreen.kt` shown inline via a local `editing` toggle, not a separate route) → `AddLoanScreen.kt`. Routes: `"loans"`, `"loans/new"`, `"loans/{loanId}"`. `LoansViewModel`/`LoanDetailViewModel` are both real `KoinComponent`s driven by `LoansRepository.watchLoans()`/`watchLoan()` (genuine `db.watch()`, not a one-shot snapshot — see the list-staleness fix below).
- **iOS**: `LoansView.swift` (list + in-screen detail, matching Investments' own drill-in convention rather than a pushed `NavigationStack` destination) → `LoanDetailContentView` (inline `EditLoanView` toggle) → `AddLoanView.swift`/`EditLoanView.swift`. `LoansViewModel`/`LoanDetailViewModel` mirror Android, driven by `LoansRepository.watchLoans()`/`watchLoan()` (`AsyncThrowingStream`).
- Both `LoansRepository`s' `Loan` model/mapper were fixed this pass to match web's actual nullability (see Data section) — a real crash-risk bug, same class as Budgets/Investments this engagement.

## List staleness fix (2026-08-06, same pass)

While testing this arc, newly-added/edited Goals and Budgets didn't appear on their list screens until the whole screen was torn down and recreated (e.g. navigating elsewhere and back) — `GoalsViewModel`/`BudgetsViewModel` (both platforms) were driven by a one-shot `list()`/`reload()` call instead of a real live query, and Add/Edit are separate routes (Android) or `.sheet` presentations (iOS) with their own ViewModel instance, so a save there never refreshed the list screen's own instance. Fixed by adding `watchGoals()`/`watchAllocations()`/`watchBudgets()` (real `db.watch()`) to both repositories on both platforms and rewiring both ViewModels to be driven by those live streams — matching the pattern Loans/Investments/Accounts already used correctly. See `AUDIT_HISTORY.md`'s 2026-08-06 entry for the full write-up.
