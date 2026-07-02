-- PocketCare — consolidated schema (single-file init for a fresh Supabase project).
-- Combines all prior migrations (0001–0007) into final definitions.
--
-- Financial integrity: money is INTEGER minor units; balances derive from an
-- append-only ledger; breakdown items must reconcile to their transaction total.
-- Every user-owned row is isolated by RLS and cascades on user deletion.
--
-- NOTE: enable Anonymous sign-ins in Supabase Auth so each user gets a real
-- auth.users UID from first launch (guest identity). For email OTP sign-up,
-- disable "Secure email change" and add {{ .Token }} to the Change-Email template.

create extension if not exists "pgcrypto";

-- ============================ Enums ============================
create type account_type     as enum ('savings','current','credit_card','cash','mutual_funds','stocks');
create type transaction_type as enum ('income','expense','transfer','opening_balance','adjustment');
create type category_kind    as enum ('income','expense');
create type budget_period    as enum ('daily','weekly','monthly','yearly');
create type budget_scope     as enum ('overall','category','label');
create type commitment_kind  as enum ('emi','subscription','recurring_expense');
create type tier             as enum ('free','premium');
create type rate_mode        as enum ('historical','current');

-- ==================== Shared updated_at trigger ====================
create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ============================ profiles ============================
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  base_currency text not null default 'USD',
  locale        text not null default 'en',
  rate_mode     rate_mode not null default 'historical',
  theme         text not null default 'system',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ============================ accounts ============================
create table accounts (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references auth.users(id) on delete cascade,
  name                 text not null,
  type                 account_type not null,
  currency             text not null,
  icon                 text,
  color                text,
  is_archived          boolean not null default false,
  include_in_net_worth boolean not null default true,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz
);
create index accounts_user_idx on accounts(user_id) where deleted_at is null;

-- ============================ categories ============================
create table categories (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  kind       category_kind not null,
  icon       text,
  color      text,
  is_system  boolean not null default false,
  parent_id  uuid references categories(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index categories_user_idx on categories(user_id);

-- ============================ labels ============================
create table labels (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  color      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, name)
);
create index labels_user_idx on labels(user_id);

-- ============================ transactions (ledger) ============================
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
  transfer_group_id uuid,
  to_account_id     uuid references accounts(id) on delete cascade,
  to_amount         bigint,
  fx_rate           double precision,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  constraint transfer_needs_target check (type <> 'transfer' or to_account_id is not null)
);
create index transactions_account_idx on transactions(account_id, occurred_at desc) where deleted_at is null;
create index transactions_user_idx    on transactions(user_id, occurred_at desc)   where deleted_at is null;
create index transactions_search_idx  on transactions using gin (to_tsvector('simple', coalesce(label,'') || ' ' || coalesce(note,'')));

-- ============================ transaction_items (breakdown) ============================
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

-- Breakdown must reconcile to the transaction total WHEN items exist (deferred to commit).
create or replace function check_items_reconcile() returns trigger
language plpgsql as $$
declare
  txn_id uuid;
  txn_amount bigint;
  items_sum bigint;
begin
  txn_id := coalesce(new.transaction_id, old.transaction_id);
  select amount into txn_amount from transactions where id = txn_id;
  if txn_amount is null then return null; end if;
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

-- ============================ transaction_audit ============================
create table transaction_audit (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  transaction_id uuid not null,
  action         text not null default 'update',
  changes        text,
  created_at     timestamptz not null default now()
);
create index transaction_audit_txn_idx on transaction_audit(transaction_id, created_at desc);

-- ============================ budgets ============================
create table budgets (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  name          text,
  scope         budget_scope not null default 'overall',
  scope_ref     text,
  period        budget_period not null,
  start_date    date,
  end_date      date,
  limit_amount  bigint not null,
  currency      text not null,
  threshold_pct int not null default 80 check (threshold_pct between 1 and 100),
  rollover      boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index budgets_user_idx on budgets(user_id);

-- ============================ credit_card_details ============================
create table credit_card_details (
  id            uuid primary key default gen_random_uuid(),
  account_id    uuid not null unique references accounts(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  statement_day int not null check (statement_day between 1 and 31),
  due_day       int not null check (due_day between 1 and 31),
  credit_limit  bigint,
  card_last4    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ============================ goals ============================
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
create unique index one_emergency_fund_per_user on goals(user_id) where is_emergency_fund and deleted_at is null;

-- ============================ goal_allocations ============================
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

-- ============================ loans ============================
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

-- ============================ subscriptions ============================
create table subscriptions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  name          text not null,
  amount        bigint not null,
  currency      text not null,
  billing_cycle budget_period not null default 'monthly',
  purchased_on  date,
  next_renewal  date,
  category_id   uuid references categories(id) on delete set null,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index subscriptions_user_idx on subscriptions(user_id);

-- ============================ recurring_commitments ============================
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

-- ============================ holdings ============================
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

-- ==================== Global reference data ====================
create table price_snapshots (
  symbol   text not null,
  price    bigint not null,
  currency text not null,
  as_of    date not null,
  primary key (symbol, as_of)
);

create table exchange_rates (
  base_currency  text not null,
  quote_currency text not null,
  rate           double precision not null check (rate > 0),
  as_of          date not null,
  primary key (base_currency, quote_currency, as_of)
);

-- ============================ entitlements ============================
create table entitlements (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  tier       tier not null default 'free',
  source     text,
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

-- ============================ guest_sessions ============================
create table guest_sessions (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  device_id  text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '3 days')
);

-- ============================ statements ============================
create table statements (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  period_start date not null,
  period_end   date not null,
  storage_path text,
  created_at   timestamptz not null default now()
);
create index statements_user_idx on statements(user_id);

-- ==================== updated_at triggers ====================
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','accounts','categories','labels','transactions','transaction_items','budgets',
    'credit_card_details','goals','goal_allocations','loans','subscriptions',
    'recurring_commitments','holdings','entitlements'
  ] loop
    execute format(
      'create trigger trg_%1$s_updated_at before update on %1$s
         for each row execute function set_updated_at();', t);
  end loop;
end $$;

-- ==================== Row Level Security ====================
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','accounts','categories','labels','transactions','transaction_items','transaction_audit',
    'budgets','credit_card_details','goals','goal_allocations','loans','subscriptions',
    'recurring_commitments','holdings','entitlements','guest_sessions','statements'
  ] loop
    execute format('alter table %I enable row level security;', t);
    if t = 'profiles' then
      execute format($f$create policy %1$s_owner on %1$s using (id = auth.uid()) with check (id = auth.uid());$f$, t);
    else
      execute format($f$create policy %1$s_owner on %1$s using (user_id = auth.uid()) with check (user_id = auth.uid());$f$, t);
    end if;
  end loop;
end $$;

alter table exchange_rates enable row level security;
alter table price_snapshots enable row level security;
create policy exchange_rates_read on exchange_rates for select using (auth.role() = 'authenticated');
create policy price_snapshots_read on price_snapshots for select using (auth.role() = 'authenticated');

-- ==================== Default seeding ====================
create or replace function seed_default_categories(uid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into categories (user_id, name, kind, is_system)
  select uid, v.name, v.kind::category_kind, true
  from (values
    ('Food & Dining','expense'),('Groceries','expense'),('Transport','expense'),
    ('Housing','expense'),('Utilities','expense'),('Health','expense'),
    ('Shopping','expense'),('Entertainment','expense'),('Education','expense'),
    ('Travel','expense'),('Personal Care','expense'),('Gifts & Donations','expense'),
    ('Fees & Charges','expense'),('Insurance','expense'),('Kids','expense'),
    ('Pets','expense'),('Subscriptions','expense'),('Taxes','expense'),
    ('Miscellaneous','expense'),
    ('Salary','income'),('Business','income'),('Freelance','income'),
    ('Bonus','income'),('Interest','income'),('Dividends','income'),
    ('Rental Income','income'),('Refunds','income'),('Gifts Received','income'),
    ('Other Income','income')
  ) as v(name, kind)
  where not exists (select 1 from categories c where c.user_id = uid and c.name = v.name and c.parent_id is null);

  insert into categories (user_id, name, kind, is_system, parent_id)
  select uid, ch.name, ch.kind::category_kind, true, p.id
  from (values
    ('Restaurants','Food & Dining','expense'),('Coffee & Snacks','Food & Dining','expense'),
    ('Takeout & Delivery','Food & Dining','expense'),
    ('Fuel','Transport','expense'),('Public Transit','Transport','expense'),
    ('Taxi & Rideshare','Transport','expense'),('Parking','Transport','expense'),
    ('Rent','Housing','expense'),('Mortgage','Housing','expense'),('Maintenance','Housing','expense'),
    ('Electricity','Utilities','expense'),('Water','Utilities','expense'),
    ('Gas','Utilities','expense'),('Internet','Utilities','expense'),('Mobile','Utilities','expense'),
    ('Doctor','Health','expense'),('Pharmacy','Health','expense'),('Fitness','Health','expense'),
    ('Clothing','Shopping','expense'),('Electronics','Shopping','expense'),('Home','Shopping','expense'),
    ('Streaming','Entertainment','expense'),('Movies','Entertainment','expense'),
    ('Games','Entertainment','expense'),('Events','Entertainment','expense'),
    ('Courses','Education','expense'),('Books','Education','expense'),('Tuition','Education','expense'),
    ('Flights','Travel','expense'),('Hotels','Travel','expense'),('Activities','Travel','expense'),
    ('Bank Fees','Fees & Charges','expense'),('Interest Charges','Fees & Charges','expense')
  ) as ch(name, parent, kind)
  join categories p on p.user_id = uid and p.name = ch.parent and p.parent_id is null
  where not exists (select 1 from categories c where c.user_id = uid and c.name = ch.name and c.parent_id = p.id);

  insert into labels (user_id, name, color)
  select uid, v.name, v.color
  from (values
    ('Essential','#5f7a52'),('Wants','#c08a3e'),('Work','#3e4a38'),
    ('Family','#b06a4f'),('Trip','#9cae8e'),('Emergency','#a8503a'),
    ('Recurring','#5f6647'),('One-off','#c98a72')
  ) as v(name, color)
  on conflict (user_id, name) do nothing;
end;
$$;

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id) values (new.id) on conflict (id) do nothing;
  insert into entitlements (user_id, tier) values (new.id, 'free') on conflict (user_id) do nothing;
  if coalesce(new.is_anonymous, false) then
    insert into guest_sessions (user_id) values (new.id) on conflict (user_id) do nothing;
  end if;
  perform seed_default_categories(new.id);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ==================== Guest purge (schedule daily) ====================
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
