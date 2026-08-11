# Plan — `/friends` group tiles + removing Planned Cashflow

Status: proposed. Owner: TBD. Both parts are front-end-heavy; part B also ships a
data migration and must be done in a typecheck-verified pass.

## A. `/friends` — show groups as account-style tiles

Replace the expandable EMI-style group cards in `apps/web/app/friends/page.tsx`
(the `groups.map(...)` block, ~L248–334) with a compact colored-tile grid that
mirrors the dashboard Accounts card.

- **Grid:** `repeat(auto-fill, minmax(min(150px,100%), 1fr))`, gap 8–12.
- **Each tile** is a `Link` to `/groups/[id]`: colored background via the existing
  `colorFor(g.group.id)`, white text; a small kind label ("Trip"/"Group") on top,
  the group name, and your net balance (`g.net`, green/red/neutral) at the bottom.
  Optional: a small stacked-avatar row or member count.
- **Trade-off:** account tiles don't expand inline, so the per-person breakdown and
  the "Add expense / Open group" actions move to the group detail page (the tile
  links there). Alternative: keep the toggle but restyle the *collapsed* state as a
  colored tile — decide before building.
- **Unchanged:** the "Who owes whom" and "Friends" sections below.
- Effort: ~1 focused edit, front-end only, no migration.

## B. Remove Planned Cashflow → consolidate into `/recurring`

### Current data reality (why a migration is required)
- `/cashflow` writes: incomes/household/savings → `planned_cashflow`,
  subscriptions → legacy `subscriptions` table, loans → `loans`.
- `/recurring` uses `recurring_rules` + `transaction_templates` (via
  `createRecurring`).
- Readers/writers of `planned_cashflow`/`subscriptions` today: `cashflow/model.ts`,
  `cashflow/RecurringModal.tsx`, `cashflow/recurring.ts`, `dashboard/Suggestions.tsx`,
  `dashboard/tiles.tsx`, `sync/repair.ts`, `app/cashflow/page.tsx`,
  `app/recurring/page.tsx`.

### Steps (each independently testable; do in order)
1. **Audit** — enumerate every read/write of `planned_cashflow` and `subscriptions`.
2. **Migration** `00xx_cashflow_to_recurring.sql` — non-destructive + idempotent:
   - For each `planned_cashflow` row and each legacy `subscriptions` row, create a
     `transaction_templates` row (name/amount/currency/type from direction) + a
     `recurring_rules` row (frequency/next_due/active), carrying `source_table` +
     `source_id` with a unique index so re-runs no-op.
   - Preserve the bucket (subscription/loan/household/…) on the template — add a
     `bucket` column to `transaction_templates` if absent — so `/recurring` can
     group them (incl. a "Subscriptions" group).
   - Stamp originals with `migrated_at` (new column) instead of deleting.
   - Add the new columns to `AppSchema` (`packages/db/src/index.ts`); synced tables,
     so no PowerSync stream change needed.
3. **Repoint writers** — all new writes go through `createRecurring`
   (`recurring_rules`); remove `planned_cashflow`/`subscriptions` insert paths in
   `RecurringModal`, `cashflow/model.ts`, `Suggestions`, `sync/repair`.
4. **Repoint readers** — dashboard `SubscriptionsTile` + `UpcomingTile` (and any
   others) read `recurring_rules` (joined to templates) filtered by bucket/group
   instead of `planned_cashflow`/`subscriptions`.
5. **Remove the page** — `app/cashflow/page.tsx` → `redirect("/recurring")` (like
   `/subscriptions`); rewrite every `/cashflow#payments` link to `/recurring`; drop
   the Cashflow nav item and the `cashflow` dashboard tile (or repoint it).
6. **Verify** — typecheck; grep to prove zero remaining `planned_cashflow`/
   `subscriptions` reads/writes outside the migration; manually confirm migrated
   items render on `/recurring`.

### Sequencing
Migration + schema → writers → readers → page removal/redirect → verify. Ship as
one focused, typecheck-verified change once the workspace is healthy.
