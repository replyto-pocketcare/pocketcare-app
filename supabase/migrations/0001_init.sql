-- PocketCare — initial schema
-- Financial integrity: money is INTEGER minor units; balances derive from an
-- append-only ledger; breakdown items must reconcile to their transaction total.
-- Every user-owned row is isolated by RLS and cascades on user deletion, so
-- purging a guest (or a user's "delete my account") is a single auth.users delete.
--
-- NOTE: enable Anonymous sign-ins in Supabase Auth settings so each user gets a
-- real auth.users UID from first launch (guest identity — ARCHITECTURE.md §9).

create extension if not exists "pgcrypto";

-- ---------- Enums ----------
create type account_type   as enum ('savings','current','credit_card','cash','mutual_funds','stocks');
create type transaction_type as enum ('income','expense','transfer','opening_balance','adjustment');
create type category_kind   as enum ('income','expense');
create type budget_period   as enum ('daily','weekly','monthly','yearly');
create type budget_scope    as enum ('overall','category','label');
create type commitment_kind as enum ('emi','subscription','recurring_expense');
create type tier            as enum ('free','premium');
create type rate_mode       as enum ('historical','current');

-- ---------- Shared trigger: keep updated_at fresh ----------
create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------- profiles ----------
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  base_currency text not null default 'USD',
  locale        text not null default 'en',
  rate_mode     rate_mode not null default 'historical',
  theme         text not null default 'system',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------- accounts ----------
create table accounts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  type        account_type not null,
  currency    text not null,
  icon        text,
  color       text,
  is_archived boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index accounts_user_idx on accounts(user_id) where deleted_at is null;

-- ---------- categories ----------
create table categories (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  kind       category_kind not null,
  icon       text,
  color      text,
  is_system  boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index categories_user_idx on categories(user_id);

-- ---------- transactions (the ledger) ----------
create table transactions (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  account_id        uuid not null references accounts(id) on delete cascade,
  type              transaction_type not null,
  amount            bigint not null,               -- minor units
  currency          text not null,
  category_id       uuid references categories(id) on delete set null,
  label             text,
  note              text,
  occurred_at       timestamptz not null default now(),
  transfer_group_id uuid,                          -- links the two sides of a transfer
  to_account_id     uuid references accounts(id) on delete cascade,
  to_amount         bigint,                        -- destination minor units (cross-currency)
  fx_rate           double precision,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  constraint transfer_needs_target
    check (type <> 'transfer' or to_account_id is not null)
);
create index transactions_account_idx on transactions(account_id, occurred_at desc) where deleted_at is null;
create index transactions_user_idx    on transactions(user_id, occurred_at desc)   where deleted_at is null;
create index transactions_search_idx  on transactions using gin (to_tsvector('simple', coalesce(label,'') || ' ' || coalesce(note,'')));

-- ---------- transaction_items (breakdown) ----------
create table transaction_items (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  transaction_id uuid not null references transactions(id) on delete cascade,
  description    text not null default 'Item',
  amount         bigint not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);
create index transaction_items_txn_idx on transaction_items(transaction_id);

-- Breakdown must reconcile to the transaction total WHEN items exist.
-- Deferred so a transaction + its items can be inserted in one client tx.
create or replace function check_items_reconcile() returns trigger
language plpgsql as $$
declare
  txn_id uuid;
  txn_amount bigint;
  items_sum bigint;
begin
  txn_id := coalesce(new.transaction_id, old.transaction_id);
  select amount into txn_amount from transactions where id = txn_id;
  if txn_amount is null then
    return null; -- transaction gone (cascade delete); nothing to check
  end if;
  select coalesce(sum(amount),0) into items_sum
    from transaction_items where transaction_id = txn_id and deleted_at is null;
  if items_sum <> 0 and items_sum <> txn_amount then
    raise exception 'Breakdown items (%) must sum to transaction amount (%)', items_sum, txn_amount;
  end if;
  return null;
end;
$$;

create constraint trigger trg_items_reconcile
  after insert or update or delete on transaction_items
  deferrable initially deferred
  for each row execute function check_items_reconcile();

-- ---------- budgets ----------
create table budgets (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  scope         budget_scope not null default 'overall',
  scope_ref     text,
  period        budget_period not null,
  limit_amount  bigint not null,
  currency      text not null,
  threshold_pct int not null default 80 check (threshold_pct between 1 and 100),
  rollover      boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index budgets_user_idx on budgets(user_id);

-- ---------- credit_card_details ----------
create table credit_card_details (
  account_id   uuid primary key references accounts(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  statement_day int not null check (statement_day between 1 and 31),
  due_day       int not null check (due_day between 1 and 31),
  credit_limit  bigint,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ---------- goals ----------
create table goals (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  name              text not null,
  target_amount     bigint not null,
  currency          text not null,
  priority          int not null default 0,
  is_emergency_fund boolean not null default false,
  target_date       date,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index goals_user_idx on goals(user_id);
-- At most one emergency-fund goal per user.
create unique index one_emergency_fund_per_user on goals(user_id) where is_emergency_fund and deleted_at is null;

-- ---------- goal_allocations (blocked amounts) ----------
create table goal_allocations (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  goal_id           uuid not null references goals(id) on delete cascade,
  source_account_id uuid not null references accounts(id) on delete cascade,
  amount_blocked    bigint not null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index goal_allocations_user_idx on goal_allocations(user_id);

-- ---------- loans ----------
create table loans (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  lender        text,
  principal     bigint not null,
  currency      text not null,
  interest_rate double precision not null default 0,
  tenure_months int,
  emi_amount    bigint,
  start_date    date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index loans_user_idx on loans(user_id);

-- ---------- subscriptions ----------
create table subscriptions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  name          text not null,
  amount        bigint not null,
  currency      text not null,
  billing_cycle budget_period not null default 'monthly',
  next_renewal  date,
  category_id   uuid references categories(id) on delete set null,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index subscriptions_user_idx on subscriptions(user_id);

-- ---------- recurring_commitments ----------
create table recurring_commitments (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  kind            commitment_kind not null,
  amount          bigint not null,
  currency        text not null,
  frequency       budget_period not null,
  next_due        date,
  category_id     uuid references categories(id) on delete set null,
  account_id      uuid references accounts(id) on delete set null,
  loan_id         uuid references loans(id) on delete cascade,
  subscription_id uuid references subscriptions(id) on delete cascade,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index recurring_user_idx on recurring_commitments(user_id);

-- ---------- holdings ----------
create table holdings (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references accounts(id) on delete cascade,
  symbol     text not null,
  quantity   double precision not null default 0,
  avg_cost   bigint,
  currency   text not null,
  auto_fetch boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index holdings_user_idx on holdings(user_id);

-- ---------- price_snapshots (global reference) ----------
create table price_snapshots (
  symbol text not null,
  price  bigint not null,
  currency text not null,
  as_of  date not null,
  primary key (symbol, as_of)
);

-- ---------- exchange_rates (global reference) ----------
create table exchange_rates (
  base_currency  text not null,
  quote_currency text not null,
  rate           double precision not null check (rate > 0),
  as_of          date not null,
  primary key (base_currency, quote_currency, as_of)
);

-- ---------- entitlements (freemium) ----------
create table entitlements (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  tier       tier not null default 'free',
  source     text,
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

-- ---------- guest_sessions ----------
create table guest_sessions (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  device_id  text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '3 days')
);

-- ---------- statements ----------
create table statements (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  period_start date not null,
  period_end   date not null,
  storage_path text,
  created_at  timestamptz not null default now()
);
create index statements_user_idx on statements(user_id);

-- ---------- updated_at triggers ----------
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','accounts','categories','transactions','transaction_items','budgets',
    'credit_card_details','goals','goal_allocations','loans','subscriptions',
    'recurring_commitments','holdings','entitlements'
  ] loop
    execute format(
      'create trigger trg_%1$s_updated_at before update on %1$s
         for each row execute function set_updated_at();', t);
  end loop;
end $$;

-- ---------- Row Level Security ----------
-- User-owned tables: owner can do everything with their own rows.
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','accounts','categories','transactions','transaction_items','budgets',
    'credit_card_details','goals','goal_allocations','loans','subscriptions',
    'recurring_commitments','holdings','entitlements','guest_sessions','statements'
  ] loop
    execute format('alter table %I enable row level security;', t);
    -- profiles/entitlements/guest_sessions key on id/user_id = auth.uid()
    if t in ('profiles') then
      execute format($f$
        create policy %1$s_owner on %1$s
          using (id = auth.uid()) with check (id = auth.uid());$f$, t);
    else
      execute format($f$
        create policy %1$s_owner on %1$s
          using (user_id = auth.uid()) with check (user_id = auth.uid());$f$, t);
    end if;
  end loop;
end $$;

-- Global reference data: readable by any authenticated user, writes via service role only.
alter table exchange_rates enable row level security;
alter table price_snapshots enable row level security;
create policy exchange_rates_read on exchange_rates for select using (auth.role() = 'authenticated');
create policy price_snapshots_read on price_snapshots for select using (auth.role() = 'authenticated');

-- ---------- Guest purge (schedule daily via pg_cron or an Edge Function) ----------
create or replace function purge_expired_guests() returns int
language plpgsql security definer as $$
declare deleted int;
begin
  with gone as (
    delete from auth.users u
    using guest_sessions g
    where u.id = g.user_id
      and coalesce((u.raw_app_meta_data->>'is_anonymous')::boolean, u.is_anonymous, false)
      and g.expires_at < now()
    returning u.id
  )
  select count(*) into deleted from gone;
  return deleted;
end;
$$;
