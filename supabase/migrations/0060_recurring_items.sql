-- 0060_recurring_items.sql
-- Dedicated table for recurring incomes & expenses (incl. subscriptions),
-- replacing the transaction_templates + recurring_rules pair for TRACKING.
-- Self-contained: no join to transaction_templates.
--
-- Only two directions now: income | expense. (The old "saving" direction —
-- backed by transfer-typed templates and planned_cashflow saving rows — moves to
-- Investments; see 0061_savings_to_investments.sql.)
--
-- Non-destructive + idempotent: sources are backfilled and stamped `migrated_at`,
-- never deleted. `group_id` is nullable and WITHOUT a foreign key for the same
-- reason as transaction_templates.group_id (migration 0046): the client seeds
-- groups with stable UUIDs and PowerSync uploads related rows in separate
-- transactions, so an FK would risk a head-of-line block on the write queue.

set search_path = pocketcare, public;

create table if not exists pocketcare.recurring_items (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  direction      text not null check (direction in ('income', 'expense')),
  group_id       uuid,                                -- → recurring_groups.id (nullable, no FK)
  name           text not null,
  amount         integer not null default 0,          -- minor units
  currency       text,
  frequency      text not null default 'monthly',     -- Period: daily|weekly|monthly|yearly
  interval_count integer not null default 1,
  next_due       date,
  account_id     uuid,
  category_id    uuid,
  auto_post      integer not null default 0,
  active         integer not null default 1,
  alert_time_utc text,
  source_table   text,                                -- migration provenance
  source_id      uuid,                                -- migration provenance
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

create index if not exists recurring_items_user_due_idx
  on pocketcare.recurring_items (user_id, next_due) where deleted_at is null;

-- Idempotency guard for the backfills below (and any re-run).
create unique index if not exists recurring_items_source_uidx
  on pocketcare.recurring_items (user_id, source_table, source_id)
  where source_id is not null and deleted_at is null;

alter table pocketcare.recurring_items enable row level security;
drop policy if exists recurring_items_owner on pocketcare.recurring_items;
create policy recurring_items_owner on pocketcare.recurring_items
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.recurring_items to anon, authenticated, service_role;

-- Provenance columns on the sources (idempotent).
alter table pocketcare.recurring_rules  add column if not exists migrated_at timestamptz;
alter table pocketcare.planned_cashflow add column if not exists migrated_at timestamptz;

-- ---------------------------------------------------------------------------
-- Backfill 1: recurring_rules + transaction_templates → recurring_items.
-- income templates → income, everything else that isn't a transfer → expense.
-- Transfer-typed templates were the "saving" direction and are handled by 0061.
-- ---------------------------------------------------------------------------
insert into pocketcare.recurring_items
  (user_id, direction, group_id, name, amount, currency, frequency, interval_count,
   next_due, account_id, category_id, auto_post, active, alert_time_utc, source_table, source_id)
select t.user_id,
       case when t.type = 'income' then 'income' else 'expense' end,
       t.group_id, t.name, coalesce(t.amount, 0), t.currency, r.frequency, r.interval_count,
       r.next_due, t.account_id, t.category_id, r.auto_post, r.active, r.alert_time_utc,
       'recurring_rules', r.id
from pocketcare.recurring_rules r
join pocketcare.transaction_templates t on t.id = r.template_id
where r.deleted_at is null and t.deleted_at is null and t.type in ('income', 'expense')
on conflict (user_id, source_table, source_id)
  where source_id is not null and deleted_at is null do nothing;

update pocketcare.recurring_rules r set migrated_at = now()
where r.migrated_at is null and r.deleted_at is null
  and exists (select 1 from pocketcare.recurring_items i
              where i.source_table = 'recurring_rules' and i.source_id = r.id);

-- ---------------------------------------------------------------------------
-- Backfill 2: planned_cashflow income/payment → recurring_items.
-- group_id left NULL (the client reconciles buckets → seeded groups); payment →
-- expense. Savings (direction='saving') are intentionally excluded (see 0061).
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
