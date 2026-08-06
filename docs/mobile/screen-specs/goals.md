# Goals — screen spec

> Source-verified against `apps/web/app/goals/page.tsx` (290 lines) + `apps/web/src/goals/GoalCelebration.tsx` on 2026-08-06. This is the ONLY real web source for the Goals feature — there is no separate new/edit route (unlike Accounts/Transactions/Budgets); creation is an inline form at the bottom of the list page, and editing happens in-place within a goal's own card (same in-card-edit pattern as Budgets' web page).
>
> **"Planned Cashflow" is a separate, unrelated drawer item** (`docs/mobile/screen-specs/navigation-drawer.md`'s Planning group has both "Goals" and "Planned Cashflow" as distinct entries) with no real web source read yet — it is explicitly OUT OF SCOPE for this spec and stays `comingSoonRoute("Planned Cashflow")` on Android / a placeholder tab on iOS until it gets its own pass. iOS's pre-existing `GoalsView.swift` had merged the two into one segmented-tab screen ("Goals & Cashflow") with a `CashflowUiModel` fed from nowhere real — this was invented UI with no counterpart in web or Android, same class of drift as the Dashboard "Recent Activity" section removed earlier this session. Fixed by this pass: the Cashflow tab is removed from Goals entirely.

## Data

`goals` table columns used by the UI: `id`, `name`, `target_amount` (minor units), `currency`, `is_emergency_fund` (0/1), `priority` (int, ties `ORDER BY`), `alert_time_utc` (`"HH:MM"`, UTC — same convention as Budgets, converted to/from device-local time for display/editing via `utcToLocalTime`/`localToUtcTime`). `target_date` is a real column (confirmed in `PocketCareSchema`/migrations) but is **not read or written anywhere in this page** — its only real usage is `apps/web/src/assistant/tools.ts` (the AI assistant's goal-creation tool). Not part of this screen's scope.

`goal_allocations` table: `id`, `goal_id`, `source_account_id`, `amount_blocked` (minor units). Insert-only from this screen — there is no edit/delete/un-allocate UI anywhere in `page.tsx`. A goal's "saved" amount is `SUM(amount_blocked)` over its non-deleted allocations, computed client-side (`saved(goalId)`), not a stored column.

Emergency-fund gating: at most one goal may have `is_emergency_fund = 1` (enforced client-side in `addGoal()`: `isEf && !hasEf`, not a DB constraint). If an EF goal exists and isn't yet fully funded (`saved(ef.id) < ef.target_amount`), every OTHER goal is `locked` (dimmed to 55% opacity, its allocate button disabled, "lockedUntil" text shown instead of the allocate button) and a banner ("fund your emergency fund first") shows above the list. No EF goal at all ⇒ nothing is locked.

## List (top of page)

- `h1` title.
- Conditional banner card when an EF exists and isn't funded (`efFirst` copy).
- A `list-grid` of `GoalCard`s, ordered `is_emergency_fund DESC, priority` (EF goal always first). Empty state: a skeleton while loading, else a plain "no goals yet" muted line — no illustrated empty-state card like Budgets/Accounts/Dashboard have; keep it minimal, matching web exactly.

### GoalCard (per goal)

Non-editing display:
- Name (bold) + inline status suffix: a green checkmark + "Funded" if `saved >= target_amount`, else (EF only) a muted "liquid" note, else nothing.
- Kebab menu: Edit (opens inline edit, prefilling name/target/alert-time — **not** currency, EF flag, or priority, which are create-only/immutable from this screen) and Delete (confirm dialog, then soft-delete the goal row only — **no cascade to its allocations**, matching web's `softDelete("goals", goal.id)` exactly; a stale allocation pointing at a deleted goal is an accepted, unfixed asymmetry already present in the real product, not something to invent a fix for here).
- A compact "`saved` / `target`" line (locale-aware compact notation, e.g. "₹1.5L / ₹5L" for INR, "$1.2K / $10K" otherwise — `Intl.NumberFormat(..., { notation: "compact", maximumFractionDigits: 1 })`; native equivalent below).
- A progress bar (`min(100, saved/target*100)`), tinted sage for the EF goal, accent for everything else.
- Below the bar: if `locked`, muted "locked until EF funded" text (no button); if `funded`, an accent "Goal reached!" line (no button); otherwise a ghost "+ Add funds" (EF) / "+ Block funds" (non-EF) button, disabled if there are zero eligible source accounts.
- Funded goals additionally get a distinct card treatment (accent-tinted radial background/border) — worth a subtle native equivalent (e.g. a thin accent border + tinted background) but not essential to block on.

Editing (inline, replaces the display block above — same card, not a separate sheet/screen on web): name field, target-amount field (currency is fixed/shown as a label, not editable), alert-time field, Save / Cancel. Matches Budgets' own in-card-edit precedent closely enough that both native ports use a dedicated Edit screen/sheet instead (already the established translate-logic-not-widget-shape convention from Budgets/Accounts/Transactions), not a literal inline-replace.

### Allocate modal (+ Add/Block funds)

Opens a modal scoped to one goal: a source-account picker (`accounts WHERE type = 'savings' AND deleted_at IS NULL AND is_archived = 0`, defaulting to the first one), an amount field, a "X left to reach your target" hint, and a submit button labeled "Add" (EF) / "Block" (non-EF). The entered amount is **capped at `remaining = max(0, target_amount - saved)`** before insert — never lets an allocation push saved past the target. If there are zero eligible savings accounts, the modal instead shows "add a savings account first" and no form.

## New Goal form (bottom of page, inline card — not a separate route)

Fields: name, target amount + currency select (`GOAL_CURRENCIES` = INR/USD/EUR/GBP/JPY/AUD/CAD/SGD/AED, defaulting to the user's base currency), alert time (`"09:00"` default), and — only shown when no EF goal exists yet — an "this is my emergency fund" checkbox. Validation: non-empty trimmed name, target > 0. On success the form resets to its defaults; `priority` is set to the current goal count (append-to-end).

## Deferred (own follow-up, not built this pass)

- **`GoalCelebration`** (`src/goals/GoalCelebration.tsx`): a full 3D CSS "goal tile morphs into a birthday cake" animation (confetti canvas, draggable orbit, candles, reduced-motion fallback) that fires once per goal on the saved→funded transition (tracked via a `localStorage` "already celebrated" set so it's a one-time moment, re-armed if the goal later dips back under target). This is a substantial, purely-decorative sub-feature — same category as Budgets' deferred spend-vs-limit chart or Dashboard's 12-tile catalog. The **information** it conveys (goal is fully funded) is NOT deferred — both native ports show the inline "Funded"/checkmark/tinted-card treatment from the list itself; only the celebratory animation overlay is out of scope. New TODO row: P3.5c.
- Compact-currency formatting's exact `Intl` locale/threshold behavior (e.g. the precise L/Cr breakpoints for `en-IN`) is approximated with each platform's own currency formatter at reduced fraction digits rather than a byte-for-byte reimplementation of `Intl.NumberFormat`'s compact algorithm — acceptable drift, not pixel-critical.
