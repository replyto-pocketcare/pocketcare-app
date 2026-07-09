-- PocketCare — expense splitting (Phase 1 foundation).
-- Shared-fact tables (split groups, expenses, shares, payers) + the link from a
-- shared expense to the owner's PRIVATE ledger postings. Phase 1 is single-user
-- (all rows owned by user_id, existing per-user RLS/sync); the schema is shaped
-- so Phase 3 can widen visibility to group members.
-- All objects are explicitly qualified to the `pocketcare` schema.
set search_path to pocketcare, public;

-- Virtual account kinds: 'real' (default), 'receivable' (others owe you),
-- 'payable' (you owe others). Receivable/Payable are hidden from account UIs.
alter table pocketcare.accounts add column if not exists kind text not null default 'real';

-- People you split with. Placeholders now; linkable to a real user in Phase 3.
create table if not exists pocketcare.contacts (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  name           text not null,
  email          text,
  avatar_color   text,
  linked_user_id uuid,                         -- set when a placeholder is claimed (Phase 3)
  is_placeholder int  not null default 1,
  archived       int  not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

create table if not exists pocketcare.split_groups (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  name         text not null,
  kind         text not null default 'group',  -- 'group' | 'trip'
  start_date   date,
  end_date     date,
  auto_split   int  not null default 0,
  default_mode text not null default 'equal',  -- 'equal' | 'exact' | 'percent'
  currency     text not null default 'INR',
  archived     int  not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

create table if not exists pocketcare.split_group_members (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  group_id   uuid not null references pocketcare.split_groups(id) on delete cascade,
  contact_id uuid,                             -- null = self (the owner)
  weight     int  not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- The canonical split fact (shared in later phases).
create table if not exists pocketcare.shared_expenses (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  created_by   uuid not null,
  group_id     uuid references pocketcare.split_groups(id) on delete set null,
  description  text,
  total_amount int  not null,                  -- minor units
  currency     text not null,
  occurred_at  timestamptz not null,
  split_mode   text not null default 'equal',
  category_id  uuid,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

-- Who owes what (consumption side). Sum(share_amount) = total_amount.
create table if not exists pocketcare.shared_expense_shares (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  expense_id   uuid not null references pocketcare.shared_expenses(id) on delete cascade,
  contact_id   uuid,                            -- null = self
  share_amount int  not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

-- Who paid (only the self payer carries an account_id). Sum(paid_amount)=total.
create table if not exists pocketcare.shared_expense_payers (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  expense_id  uuid not null references pocketcare.shared_expenses(id) on delete cascade,
  contact_id  uuid,                             -- null = self
  paid_amount int  not null,
  account_id  uuid,                             -- only for the self payer
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- Links a shared expense to the owner's private ledger postings (idempotent).
create table if not exists pocketcare.expense_postings (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  expense_id     uuid not null references pocketcare.shared_expenses(id) on delete cascade,
  transaction_id uuid not null,
  role           text not null,                 -- 'own_share' | 'lend' | 'borrow' | 'settlement'
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

create index if not exists contacts_user_idx on pocketcare.contacts(user_id);
create index if not exists split_groups_user_idx on pocketcare.split_groups(user_id);
create index if not exists split_members_group_idx on pocketcare.split_group_members(group_id);
create index if not exists shared_expenses_user_idx on pocketcare.shared_expenses(user_id, occurred_at desc);
create index if not exists shares_expense_idx on pocketcare.shared_expense_shares(expense_id);
create index if not exists payers_expense_idx on pocketcare.shared_expense_payers(expense_id);
create index if not exists postings_expense_idx on pocketcare.expense_postings(expense_id);

-- RLS: owner-only (Phase 1). Grants mirror the rest of the schema.
alter table pocketcare.contacts enable row level security;
create policy contacts_owner on pocketcare.contacts using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.contacts to anon, authenticated, service_role;

alter table pocketcare.split_groups enable row level security;
create policy split_groups_owner on pocketcare.split_groups using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.split_groups to anon, authenticated, service_role;

alter table pocketcare.split_group_members enable row level security;
create policy split_group_members_owner on pocketcare.split_group_members using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.split_group_members to anon, authenticated, service_role;

alter table pocketcare.shared_expenses enable row level security;
create policy shared_expenses_owner on pocketcare.shared_expenses using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.shared_expenses to anon, authenticated, service_role;

alter table pocketcare.shared_expense_shares enable row level security;
create policy shared_expense_shares_owner on pocketcare.shared_expense_shares using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.shared_expense_shares to anon, authenticated, service_role;

alter table pocketcare.shared_expense_payers enable row level security;
create policy shared_expense_payers_owner on pocketcare.shared_expense_payers using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.shared_expense_payers to anon, authenticated, service_role;

alter table pocketcare.expense_postings enable row level security;
create policy expense_postings_owner on pocketcare.expense_postings using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.expense_postings to anon, authenticated, service_role;
