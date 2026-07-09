-- 0017_category_rules.sql
-- Table for offline, on-device auto-categorization engine.
-- Stores user-specific phrase and token rules.

set search_path = pocketcare, public;

create table if not exists pocketcare.category_rules (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references pocketcare.profiles(id) on delete cascade,
    kind text not null check (kind in ('phrase', 'token')),
    key text not null,
    category_id uuid not null references pocketcare.categories(id) on delete cascade,
    weight integer not null default 1,
    corrections integer not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz
);

-- Ensure a single user doesn't have duplicate keys for the same category and kind
create unique index if not exists category_rules_user_kind_key_category_idx on pocketcare.category_rules(user_id, kind, key, category_id) where deleted_at is null;

alter table pocketcare.category_rules enable row level security;

create policy cr_all on pocketcare.category_rules for all 
  using (user_id = auth.uid()) 
  with check (user_id = auth.uid());

grant all on table pocketcare.category_rules to anon, authenticated, service_role;
