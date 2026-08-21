-- 0062_planned_cashflow_catchup.sql
--
-- Re-runs the 0060 / 0061 backfills so any planned_cashflow row created AFTER
-- those migrations ran (the /cashflow UI is still live and still writes new
-- rows) gets ported and stamped like the rest.
--
-- Non-destructive and idempotent, exactly like its predecessors: every insert
-- is guarded by the same uniqueness/`not exists` checks, so re-running inserts
-- nothing new. Nothing is ever deleted here — dropping planned_cashflow is a
-- separate, later step that must not happen until this leaves zero unmigrated
-- rows behind.
--
-- DIAGNOSTIC BY CONSTRUCTION: after running this, re-run
--
--   select count(*) from pocketcare.planned_cashflow
--    where deleted_at is null and migrated_at is null;
--
-- 0 → every row is ported; the straggler was simply created after 0060.
-- >0 → what remains is an ACCOUNTLESS SAVING, which 0061 deliberately refuses
--      to port because holdings.account_id is NOT NULL. Those need a decision
--      (assign an investment account, or convert to a recurring contribution)
--      before the table can be dropped. Identify them with:
--
--   select id, direction, bucket, amount, currency, frequency, next_due, name
--     from pocketcare.planned_cashflow
--    where deleted_at is null and migrated_at is null;

set search_path = pocketcare, public;

-- ---------------------------------------------------------------------------
-- 1. income / payment → recurring_items  (mirrors 0060 backfill 2)
-- ---------------------------------------------------------------------------
insert into pocketcare.recurring_items
  (user_id, direction, group_id, name, amount, currency, frequency, interval_count,
   next_due, account_id, category_id, auto_post, active, source_table, source_id)
select p.user_id,
       case when p.direction = 'income' then 'income' else 'expense' end,
       null, p.name, coalesce(p.amount, 0), p.currency, p.frequency, 1,
       p.next_due, p.account_id, p.category_id, 0, coalesce(p.is_active, 1),
       'planned_cashflow', p.id
from pocketcare.planned_cashflow p
where p.deleted_at is null and p.direction in ('income', 'payment')
on conflict (user_id, source_table, source_id)
  where source_id is not null and deleted_at is null do nothing;

update pocketcare.planned_cashflow p set migrated_at = now()
where p.migrated_at is null and p.deleted_at is null and p.direction in ('income', 'payment')
  and exists (select 1 from pocketcare.recurring_items i
              where i.source_table = 'planned_cashflow' and i.source_id = p.id);

-- ---------------------------------------------------------------------------
-- 2. saving (WITH an investment account) → holdings  (mirrors 0061)
--    Accountless savings are still left in place. Nothing is lost.
-- ---------------------------------------------------------------------------
insert into pocketcare.holdings
  (user_id, account_id, symbol, source_account_id, name, currency, asset_class,
   sip_amount, sip_start_date, sip_day, current_value, annual_rate,
   quantity, avg_cost, off_list, planned_id, created_at, updated_at)
select p.user_id,
       p.account_id,
       '',
       p.account_id::text,
       p.name,
       coalesce(p.currency, ''),
       case p.bucket
         when 'sip'         then 'sip'
         when 'mutual_fund' then 'mf'
         when 'stocks'      then 'stock'
         when 'crypto'      then 'crypto'
         when 'fd'          then 'fd'
         else 'other'
       end,
       case when p.bucket = 'sip' then p.amount else null end,
       coalesce(to_char(p.created_at, 'YYYY-MM-DD'),
                to_char(p.next_due, 'YYYY-MM-DD')),
       extract(day from coalesce(p.next_due, p.created_at::date))::int,
       0,
       case when p.expected_return is not null then p.expected_return / 100.0 else null end,
       0,
       0,
       1,
       p.id::text,
       now(), now()
from pocketcare.planned_cashflow p
where p.deleted_at is null
  and p.direction = 'saving'
  and p.account_id is not null
  and not exists (select 1 from pocketcare.holdings h
                  where h.planned_id = p.id::text and h.deleted_at is null);

update pocketcare.planned_cashflow p set migrated_at = now()
where p.migrated_at is null and p.deleted_at is null and p.direction = 'saving'
  and exists (select 1 from pocketcare.holdings h where h.planned_id = p.id::text and h.deleted_at is null);
