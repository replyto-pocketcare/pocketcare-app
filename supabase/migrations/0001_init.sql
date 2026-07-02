-- PocketCare — normalized schema (single-file init for a fresh Supabase project).
-- Enums are lookup tables (code = id); many-to-many relations use junction tables;
-- foreign keys enforce referential integrity throughout.
--
-- Money is INTEGER minor units; account balances derive from an append-only ledger.
-- Every user-owned row is isolated by RLS and cascades on user deletion.
--
-- NOTE: enable Anonymous sign-ins in Supabase Auth so each user gets a real
-- auth.users UID from first launch. For email OTP sign-up, disable "Secure email
-- change" and add {{ .Token }} to the Change-Email template.

create extension if not exists "pgcrypto" with schema extensions;

-- ======================= Dedicated schema =======================
-- All PocketCare objects live in `pocketcare`, not `public`.
-- IMPORTANT: also add "pocketcare" under Supabase → Settings → API → Exposed
-- schemas (so PostgREST/the PowerSync connector can write to it), and include
-- the schema in the PowerSync publication (see supabase/README or DEPLOY.md).
create schema if not exists pocketcare;
grant usage on schema pocketcare to anon, authenticated, service_role;
-- New objects created below inherit these grants; explicit grants repeated at end.
alter default privileges in schema pocketcare grant all on tables to anon, authenticated, service_role;
alter default privileges in schema pocketcare grant all on sequences to anon, authenticated, service_role;
-- Every unqualified object below resolves to `pocketcare` first.
set search_path to pocketcare, public;

-- ======================= Lookup tables (id = code) =======================
create table account_types      (id text primary key, label text not null, sort int not null default 0);
create table transaction_types  (id text primary key, label text not null, sort int not null default 0);
create table category_kinds     (id text primary key, label text not null, sort int not null default 0);
create table periods            (id text primary key, label text not null, sort int not null default 0);
create table commitment_kinds   (id text primary key, label text not null, sort int not null default 0);
create table tiers              (id text primary key, label text not null, sort int not null default 0);
create table rate_modes         (id text primary key, label text not null, sort int not null default 0);
create table payment_methods    (id text primary key, label text not null, sort int not null default 0);

insert into account_types (id, label, sort) values
  ('savings','Savings',1),('current','Current',2),('credit_card','Credit Card',3),
  ('cash','Cash',4),('mutual_funds','Mutual Funds',5),('stocks','Stocks',6);
insert into transaction_types (id, label, sort) values
  ('income','Income',1),('expense','Expense',2),('transfer','Transfer',3),
  ('opening_balance','Opening balance',4),('adjustment','Adjustment',5);
insert into category_kinds (id, label, sort) values ('income','Income',1),('expense','Expense',2);
insert into periods (id, label, sort) values ('daily','Daily',1),('weekly','Weekly',2),('monthly','Monthly',3),('yearly','Yearly',4);
insert into commitment_kinds (id, label, sort) values ('emi','EMI',1),('subscription','Subscription',2),('recurring_expense','Recurring Expense',3);
insert into tiers (id, label, sort) values ('free','Free',1),('premium','Premium',2);
insert into rate_modes (id, label, sort) values ('historical','Historical',1),('current','Current',2);
insert into payment_methods (id, label, sort) values
  ('upi','UPI',1),('debit_card','Debit Card',2),('net_banking','Net Banking',3),('credit_card','Credit Card',4),('cash','Cash',5);

-- Which payment methods apply to which account type (many-to-many mapping).
create table account_type_payment_methods (
  id                uuid primary key default gen_random_uuid(),
  account_type_id   text not null references account_types(id) on delete cascade,
  payment_method_id text not null references payment_methods(id) on delete cascade,
  unique (account_type_id, payment_method_id)
);
insert into account_type_payment_methods (account_type_id, payment_method_id)
select a, m from (values
  ('savings','upi'),('savings','debit_card'),('savings','net_banking'),
  ('current','upi'),('current','debit_card'),('current','net_banking'),
  ('cash','cash'),
  ('credit_card','credit_card')
) as v(a, m);

-- ======================= Shared updated_at trigger =======================
create or replace function set_updated_at() returns trigger
language plpgsql set search_path = pocketcare, public as $$
begin new.updated_at := now(); return new; end;
$$;

-- ============================ profiles ============================
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  base_currency text not null default 'INR',
  locale        text not null default 'en',
  rate_mode     text not null default 'historical' references rate_modes(id),
  theme         text not null default 'system',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ============================ accounts ============================
create table accounts (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references auth.users(id) on delete cascade,
  name                 text not null,
  type                 text not null references account_types(id),
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
  kind       text not null references category_kinds(id),
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
  type              text not null references transaction_types(id),
  amount            bigint not null,
  currency          text not null,
  category_id       uuid references categories(id) on delete set null,
  note              text,
  description       text,
  payment_method    text references payment_methods(id),
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

-- transaction <-> labels (many-to-many)
create table transaction_labels (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  transaction_id uuid not null references transactions(id) on delete cascade,
  label_id       uuid not null references labels(id) on delete cascade,
  created_at     timestamptz not null default now(),
  unique (transaction_id, label_id)
);
create index transaction_labels_txn_idx on transaction_labels(transaction_id);
create index transaction_labels_label_idx on transaction_labels(label_id);

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

create or replace function check_items_reconcile() returns trigger
language plpgsql set search_path = pocketcare, public as $$
declare txn_id uuid; txn_amount bigint; items_sum bigint;
begin
  txn_id := coalesce(new.transaction_id, old.transaction_id);
  select amount into txn_amount from transactions where id = txn_id;
  if txn_amount is null then return null; end if;
  select coalesce(sum(amount),0) into items_sum from transaction_items where transaction_id = txn_id and deleted_at is null;
  if items_sum <> 0 and items_sum <> txn_amount then
    raise exception 'Breakdown items (%) must sum to transaction amount (%)', items_sum, txn_amount;
  end if;
  return null;
end;
$$;
create constraint trigger trg_items_reconcile
  after insert or update or delete on transaction_items
  deferrable initially deferred for each row execute function check_items_reconcile();

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
  period        text not null references periods(id),
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

-- budget <-> categories / labels (many-to-many)
create table budget_categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  budget_id   uuid not null references budgets(id) on delete cascade,
  category_id uuid not null references categories(id) on delete cascade,
  unique (budget_id, category_id)
);
create table budget_labels (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references auth.users(id) on delete cascade,
  budget_id uuid not null references budgets(id) on delete cascade,
  label_id  uuid not null references labels(id) on delete cascade,
  unique (budget_id, label_id)
);

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
  billing_cycle text not null default 'monthly' references periods(id),
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
  kind            text not null references commitment_kinds(id),
  amount          bigint not null,
  currency        text not null,
  frequency       text not null references periods(id),
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
  symbol text not null, price bigint not null, currency text not null, as_of date not null,
  primary key (symbol, as_of)
);
create table exchange_rates (
  base_currency text not null, quote_currency text not null,
  rate double precision not null check (rate > 0), as_of date not null,
  primary key (base_currency, quote_currency, as_of)
);

-- ============================ entitlements ============================
create table entitlements (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  tier       text not null default 'free' references tiers(id),
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
    execute format('create trigger trg_%1$s_updated_at before update on %1$s for each row execute function set_updated_at();', t);
  end loop;
end $$;

-- ==================== Row Level Security ====================
-- User-owned tables (owner = auth.uid()).
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','accounts','categories','labels','transactions','transaction_labels','transaction_items',
    'transaction_audit','budgets','budget_categories','budget_labels','credit_card_details','goals',
    'goal_allocations','loans','subscriptions','recurring_commitments','holdings','entitlements',
    'guest_sessions','statements'
  ] loop
    execute format('alter table %I enable row level security;', t);
    if t = 'profiles' then
      execute format($f$create policy %1$s_owner on %1$s using (id = auth.uid()) with check (id = auth.uid());$f$, t);
    else
      execute format($f$create policy %1$s_owner on %1$s using (user_id = auth.uid()) with check (user_id = auth.uid());$f$, t);
    end if;
  end loop;
end $$;

-- Global reference tables: read-only to any authenticated user.
do $$
declare t text;
begin
  foreach t in array array[
    'account_types','transaction_types','category_kinds','periods','commitment_kinds','tiers',
    'rate_modes','payment_methods','account_type_payment_methods','exchange_rates','price_snapshots'
  ] loop
    execute format('alter table %I enable row level security;', t);
    execute format($f$create policy %1$s_read on %1$s for select using (auth.role() = 'authenticated');$f$, t);
  end loop;
end $$;

-- ==================== Default seeding ====================
create or replace function seed_default_categories(uid uuid) returns void
language plpgsql security definer set search_path = pocketcare, public as $$
begin
  insert into categories (user_id, name, kind, is_system)
  select uid, v.name, v.kind, true from (values
    ('Food & Dining','expense'),('Groceries','expense'),('Transport','expense'),
    ('Housing','expense'),('Utilities','expense'),('Health','expense'),
    ('Shopping','expense'),('Entertainment','expense'),('Education','expense'),
    ('Travel','expense'),('Personal Care','expense'),('Gifts & Donations','expense'),
    ('Fees & Charges','expense'),('Insurance','expense'),('Kids','expense'),
    ('Pets','expense'),('Subscriptions','expense'),('Taxes','expense'),('Miscellaneous','expense'),
    ('Salary','income'),('Business','income'),('Freelance','income'),('Bonus','income'),
    ('Interest','income'),('Dividends','income'),('Rental Income','income'),
    ('Refunds','income'),('Gifts Received','income'),('Other Income','income')
  ) as v(name, kind)
  where not exists (select 1 from categories c where c.user_id = uid and c.name = v.name and c.parent_id is null);

  insert into categories (user_id, name, kind, is_system, parent_id)
  select uid, ch.name, ch.kind, true, p.id from (values
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
  select uid, v.name, v.color from (values
    ('Essential','#5f7a52'),('Wants','#c08a3e'),('Work','#3e4a38'),('Family','#b06a4f'),
    ('Trip','#9cae8e'),('Emergency','#a8503a'),('Recurring','#5f6647'),('One-off','#c98a72')
  ) as v(name, color)
  on conflict (user_id, name) do nothing;
end;
$$;

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = pocketcare, public as $$
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
create trigger on_auth_user_created after insert on auth.users for each row execute function pocketcare.handle_new_user();

-- ==================== Guest purge (schedule daily) ====================
create or replace function purge_expired_guests() returns int
language plpgsql security definer set search_path = pocketcare, public as $$
declare deleted int;
begin
  with gone as (
    delete from auth.users u using guest_sessions g
    where u.id = g.user_id
      and coalesce((u.raw_app_meta_data->>'is_anonymous')::boolean, u.is_anonymous, false)
      and g.expires_at < now()
    returning u.id
  ) select count(*) into deleted from gone;
  return deleted;
end;
$$;

-- ==================== Grants (PostgREST roles) ====================
-- RLS still governs row access; these grant table-level reach to the API roles.
grant all on all tables in schema pocketcare to anon, authenticated, service_role;
grant all on all sequences in schema pocketcare to anon, authenticated, service_role;
grant execute on all functions in schema pocketcare to anon, authenticated, service_role;

-- OPTIONAL: expose the schema to PostgREST from SQL instead of the dashboard.
-- (Prefer the dashboard toggle; uncomment if you manage config via SQL.)
-- alter role authenticator set pgrst.db_schemas = 'public, graphql_public, pocketcare';
-- notify pgrst, 'reload config';
