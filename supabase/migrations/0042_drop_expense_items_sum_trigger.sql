-- 0042_drop_expense_items_sum_trigger.sql
--
-- Removes the `expense_items_sum_check` constraint trigger added in 0040.
--
-- WHY IT WAS WRONG
-- ----------------
-- The trigger enforced `Σ expense_items.amount = expenses.amount`, deferred to
-- the end of the transaction. That works when a client writes an expense and
-- all of its items in ONE transaction — which is exactly what the app does
-- locally, and what I assumed would reach Postgres.
--
-- It doesn't. PowerSync uploads the local write queue as a series of HTTP
-- requests (see `packages/db/src/connector.ts` — it coalesces only *consecutive*
-- same-table ops), and each request is its own Postgres transaction. So the
-- rows arrive incrementally: the expense lands, then some items, then some
-- shares, then more items. `DEFERRABLE INITIALLY DEFERRED` defers to the end of
-- the enclosing transaction, and every one of those transactions contains a
-- PARTIAL set of items.
--
-- The result was a permanently stuck upload queue:
--   expense_items for <id> sum to 20000 but the expense total is 1258784
-- ...retrying forever, because the next item could never be written either.
--
-- A cross-row sum is simply not expressible as a synchronous constraint against
-- an incremental sync engine. This is a category error, not a tuning problem.
--
-- WHAT ENFORCES IT NOW
-- --------------------
-- Integrity is enforced at write time on the client, where the whole set is
-- known at once, in three independent places:
--   1. `reconcile()` gates the review screen — an unbalanced receipt can't be
--      saved at all (packages/core/receipts/src/reconcile.ts).
--   2. `allocateReceipt()` throws unless every line is fully allocated and the
--      roll-up equals the line total (packages/core/receipts/src/allocate.ts).
--   3. `createSplitExpenseItemized()` re-runs `reconcile()` and refuses to begin
--      writing if it fails (apps/web/src/splits/writeItemized.ts).
-- All three are covered by the `@pocketcare/receipts` test suite.
--
-- Server-side, the invariant is now OBSERVABLE rather than enforced: see
-- `pocketcare.audit_expense_item_sums()` below. Run it as an audit, not a gate.

set search_path = pocketcare, public;

drop trigger if exists expense_items_sum_check on pocketcare.expense_items;
drop function if exists pocketcare.check_expense_items_sum();

-- ---------------------------------------------------------------------------
-- Observability in place of enforcement.
--
-- Returns any itemized expense whose lines don't sum to its total. Expected to
-- be empty; a non-empty result means a client wrote inconsistent data (a bug),
-- OR that a sync is still in flight — so treat a fresh drift as informational
-- and re-run before investigating.
-- ---------------------------------------------------------------------------
create or replace function pocketcare.audit_expense_item_sums()
returns table (expense_id uuid, group_id uuid, expense_total int, items_total int, drift int)
language sql stable security definer
set search_path = pocketcare, public as $$
  select e.id,
         e.group_id,
         e.amount,
         coalesce(sum(i.amount), 0)::int,
         (e.amount - coalesce(sum(i.amount), 0))::int
    from pocketcare.expenses e
    left join pocketcare.expense_items i
      on i.expense_id = e.id and i.deleted_at is null
   where e.has_items
     and e.deleted_at is null
   group by e.id, e.group_id, e.amount
  having e.amount <> coalesce(sum(i.amount), 0);
$$;

revoke all on function pocketcare.audit_expense_item_sums() from public, anon;
grant execute on function pocketcare.audit_expense_item_sums() to authenticated, service_role;
