# Plan — remove Planned Cashflow; dedicated recurring/subscription tables;
# savings → investments; recurring UI; `/friends` group tiles

Status: proposed / partially designed. **Must ship in a typecheck-verified pass**
(schema + two data migrations + multi-page rewrites). SQL migrations can be
pre-validated with `pip install pglast --break-system-packages`.

---

## Decisions (from product)
1. **Do not build recurring/subscriptions on `transaction_templates`.** Use a
   dedicated, self-contained table so recurring tracking is decoupled from the
   quick-apply templates feature.
2. **Recurring has only Income and Expense** — the **Savings** direction is
   removed from `/recurring`.
3. **Savings live in Investments.** Port existing `planned_cashflow` saving rows
   into the investments (`holdings`) tables.
4. **SIP entry is amount-based:** ask for a **monthly amount + a date of
   investment**; do **not** ask for NAV / units / price for an amount SIP.
5. **`/recurring` UI:** two top-level buttons **Income** and **Expenses**; each
   opens the **groups** within that direction; each group card shows **total per
   month** and **spent so far**.
6. **Remove the Planned Cashflow page** entirely (redirect `/cashflow` →
   `/recurring`), no data loss.
7. **`/friends`:** show groups as compact colored account-style tiles.

---

## A. New data model

### `recurring_items` (new table — replaces recurring_rules + templates for tracking)
Self-contained; no join to `transaction_templates`.

| column | type | notes |
|---|---|---|
| id | uuid pk | |
| user_id | uuid | RLS owner |
| direction | text | `income` \| `expense` (no `saving`) |
| group_id | uuid | → `recurring_groups.id` |
| name | text | |
| amount | integer | minor units |
| currency | text | |
| frequency | text | Period: daily/weekly/monthly/yearly |
| interval_count | integer | default 1 |
| next_due | text | ISO date |
| account_id | uuid null | |
| category_id | uuid null | |
| auto_post | integer | 0/1 |
| active | integer | 0/1 |
| alert_time_utc | text null | |
| source_table | text null | migration provenance |
| source_id | uuid null | migration provenance (unique w/ source_table) |
| created_at/updated_at/deleted_at | text/ts | |

- Add to `AppSchema` (`packages/db/src/index.ts`) and `sync-streams.yaml`
  (`user_data`). Keep `recurring_groups` as-is but **drop the `saving` seed rows**
  (`recurring/groups.ts` `DEFAULT_GROUPS.saving` removed).
- **Subscriptions are just `recurring_items` in the "Subscription" group** —
  satisfies "separate table for subscriptions" without a third table.
- `recurring_rules` + the template-join path are retired once migrated.

### `holdings` — add SIP-by-amount + two dates
Add columns (migration + `AppSchema`):

| column | type | notes |
|---|---|---|
| sip_amount | integer null | monthly SIP amount (minor); set ⇒ amount-based SIP |
| sip_start_date | text null | date the SIP began (ISO) — anchors "invested for N months" |
| sip_day | integer null | **day of month (1–28) the amount is debited** from the funding account to be invested; drives the upcoming-payments schedule |
| total_invested | integer null | running sum of contributions (minor) |

For an **amount SIP**: `asset_class='sip'`, `sip_amount` + `sip_start_date` +
`sip_day` set, `quantity`/`avg_cost` left null, valuation via `current_value`
(+ optional `annual_rate`). The Add-investment dialog collects **amount, start
date, and monthly debit day** and hides symbol/NAV/units/price. `source_account_id`
is the funding account the monthly debit comes from.
(`invested_on` from the earlier draft is superseded by `sip_start_date`.)

---

## B. Migrations (non-destructive, idempotent; validate with pglast)

### `00xx_recurring_items.sql`
1. Create `recurring_items` (+ RLS owner policy, grants, unique
   `(user_id, source_table, source_id)` where not null).
2. **Backfill from templates+rules:** insert one `recurring_items` row per
   `recurring_rules` r JOIN `transaction_templates` t, direction from t.type
   (income vs expense; **skip `saving`** — handled in the savings migration),
   group_id = t.group_id, source_table='recurring_rules', source_id=r.id.
3. **Backfill from `planned_cashflow`** where direction in ('income','payment')
   → recurring_items (payment→expense), mapping `bucket`→group by name, source
   provenance set. Stamp originals `migrated_at`.
4. Leave originals in place; add `migrated_at timestamptz` to
   `recurring_rules` + `planned_cashflow`.

### `00xx_savings_to_investments.sql`
1. Add `sip_amount`, `sip_start_date`, `sip_day`, `total_invested` to `holdings`.
2. For each `planned_cashflow` where `direction='saving'` and not already linked
   (`holdings.planned_id`), insert a `holdings` row: `asset_class` from bucket
   (sip→sip, fd→fd, mutual_fund→mf, stocks→stock, crypto→crypto, other→other),
   `sip_amount = amount` (for sip), `sip_start_date = coalesce(created_at::date,
   next_due)`, `sip_day = extract(day from coalesce(next_due, created_at))`,
   `current_value` seeded 0/null, `planned_id = <source>`, `source_account_id`
   carried if present. Idempotent on `planned_id`.
3. Stamp source `planned_cashflow` rows `migrated_at`.

> pg_cron/stream note: `holdings` + `recurring_items` are synced tables; add the
> new columns/table to `AppSchema` so the device mirror has them (else
> "table … has no column …" at runtime), and add `recurring_items` to
> `sync-streams.yaml`. `SELECT *` streams pick new columns up automatically.

---

## C. UI changes

### `/recurring` — two buttons → groups → group cards
- Top: **Income** / **Expenses** toggle (segmented). No Savings tab.
- Body: the `recurring_groups` for the chosen direction, each rendered as a
  **card** showing: group name + icon, **total/month** (Σ monthly-equivalent of
  its `recurring_items`), and **spent so far** (Σ matching posted transactions
  this period, or contributions to date). Tapping a group expands/branches to its
  items (add/edit/delete inline as today).
- Rewrite reads to `recurring_items` (drop the templates join). `createRecurring`
  / `RecurringModal` / `cashflow/model.ts` / `Suggestions` / `sync/repair` write
  `recurring_items` directly.

### Investments — SIP by amount
- Add-investment dialog: when asset class = SIP, show **amount + date** fields;
  hide symbol/NAV/units/price. Persist `sip_amount`, `invested_on`,
  `asset_class='sip'`. Existing unit-based holdings unaffected.
- Investments page groups already handle `asset_class` — show SIPs with their
  monthly amount + invested-on; valuation from `current_value`.

### Dashboard — unified "Upcoming payments this month"
The upcoming/planned-payments card is the **single home for every scheduled
outflow**. `useUpcomingPayments` aggregates, deduped and normalised to base
currency, and sorted by date:
- **Recurring expenses** (incl. Subscriptions) — `recurring_items` where
  `direction='expense'`, next occurrence from `next_due` + `frequency`.
- **SIP debits** — `holdings` where `asset_class='sip'` and `sip_amount` set: next
  debit computed from `sip_day` (+ `sip_start_date` as the floor).
- **Loan EMIs** — `loans` via `emiDueDate` (already wired).
- **Credit-card dues** — `credit_card_details.pending_due` / `due_on` (already).
- Anything else scheduled to be paid lands here too (one source of truth). The
  tile's "Due in the next 30 days" total sums all of the above.
- `SubscriptionsTile` reads the Subscription group of `recurring_items`.
- Drop or repoint the `cashflow` dashboard tile; savings surface via Investments.

### Dashboard — "Recommended actions" card/bar (new, below Net Worth hero)
A context-aware strip that surfaces the most likely thing to record right now,
each as a one-tap chip that opens the add flow **prefilled** (reuse the existing
`/transactions/new?type=&amount=&desc=` deep-link + template prefill).

Signals (deterministic, on-device, offline-first):
- **Time of month:**
  - End of month → **record salary** (income) if a Salary recurring-income exists
    or history shows a monthly credit — show a salary template chip.
  - Start of month → **pay rent** / due recurring expenses in the next few days.
- **Time of week:** Sunday evening / end of weekend → "Add any **cafe / outing**
  you missed this weekend" (nudge for commonly-forgotten discretionary spend).
- **Daily / routine:** frequent low-value categories from the user's own history
  (groceries, milk, vegetables) → quick-add chips seeded with the usual
  category/amount.
- **Due recurring items:** any `recurring_items` / SIP / EMI due today or overdue
  → "Record <name>" prefilled with its amount + category.

Design:
- Ranking: due/overdue scheduled items first, then salary/rent windows, then
  habitual quick-adds; cap ~3–4 chips; dismissible per suggestion for the day
  (localStorage), never nags.
- Source of "usual activities": aggregate the user's transactions by
  (category, weekday/day-of-month) to learn routines; combine with
  `recurring_items` for the scheduled ones. Pure client-side; renders nothing
  until there's enough history (like `Suggestions` already does).
- New component `src/dashboard/RecommendedActions.tsx`, rendered in `app/page.tsx`
  directly under `<NetWorthHero />`. No new table (reads existing data +
  localStorage for dismissals).
- Open question: should chips also cover **income** prompts beyond salary (e.g.
  freelance, rent received) — yes, gated on matching recurring-income/history.

### Remove the page
- `app/cashflow/page.tsx` → `redirect("/recurring")`. Rewrite all
  `/cashflow#payments` links to `/recurring`. Remove the Cashflow nav item.

### `/friends` — group tiles
- Replace the expandable group cards (`friends/page.tsx` ~L248–334) with a colored
  account-style tile grid (`repeat(auto-fill, minmax(min(150px,100%),1fr))`), each
  a `Link` to `/groups/[id]` (kind label, name, your net balance). Per-person
  breakdown/actions move to the group page.

---

## D. Execution order (one verified pass)
1. Schema: new columns + `recurring_items` in `AppSchema`; `sync-streams.yaml`.
2. Migrations `recurring_items` + `savings_to_investments` (pglast-validated).
3. Repoint recurring writers → `recurring_items`; drop Savings from groups.
4. Investments SIP-by-amount dialog (amount + start date + monthly debit day) + reads.
5. `useUpcomingPayments` unified across recurring_items + SIP debits + EMIs + card
   dues; dashboard readers repointed.
6. `/recurring` two-button + group-card UI.
7. `RecommendedActions` card under the Net Worth hero.
8. `/friends` group tiles.
9. Remove `/cashflow` page + links + nav.
10. Verify: `pnpm --filter @sanvya/web typecheck`; grep proves zero
    `planned_cashflow`/`subscriptions`/template-recurring reads outside migrations;
    manual check that migrated recurring + SIPs render and appear in Upcoming.

## Open questions
- Keep `recurring_groups` (rename "payment"→"expense" direction value) or fold
  groups into a fixed enum? Current plan keeps the table, drops `saving`.
- "Spent so far" definition per group: matched posted transactions vs. a simple
  months-elapsed × amount estimate. Confirm before building the cards.
