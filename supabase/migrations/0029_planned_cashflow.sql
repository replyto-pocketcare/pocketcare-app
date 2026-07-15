-- PocketCare — Planned Cashflow hub (BETA).
-- One owner-scoped, offline-first table consolidating recurring INCOMES,
-- planned PAYMENTS (household/general — subscriptions & loans keep their own
-- tables and are surfaced in the hub UI), and SAVINGS/investment plans.
--   direction : 'income' | 'payment' | 'saving'
--   bucket    : sub-category within a direction (e.g. 'salary', 'household', 'fd')
--   timeframe : 'monthly' | 'quarterly' | 'yearly' (which summary tab it rolls into)
--   frequency : 'daily' | 'weekly' | 'monthly' | 'yearly' (real cadence for normalisation)
--   expected_return : annual % ×100 stored as int (savings only) → drives projections
set search_path to pocketcare, public;

create table if not exists pocketcare.planned_cashflow (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  name            text not null,
  direction       text not null default 'payment',   -- 'income' | 'payment' | 'saving'
  bucket          text not null default 'other',
  amount          int  not null default 0,           -- minor units
  currency        text,
  frequency       text not null default 'monthly',   -- Period
  timeframe       text not null default 'monthly',    -- 'monthly' | 'quarterly' | 'yearly'
  next_due        date,
  expected_return int,                                -- annual % ×100 (savings only)
  category_id     uuid,
  account_id      uuid,
  notes           text,
  is_active       int  not null default 1,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

create index if not exists planned_cashflow_user_idx
  on pocketcare.planned_cashflow(user_id, direction);

alter table pocketcare.planned_cashflow enable row level security;
create policy planned_cashflow_owner on pocketcare.planned_cashflow
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.planned_cashflow to anon, authenticated, service_role;
