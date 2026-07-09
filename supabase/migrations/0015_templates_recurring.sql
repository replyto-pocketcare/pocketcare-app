-- PocketCare — transaction templates + recurring rules.
-- Templates = saved transactions for fast entry (incl. an optional split config).
-- Recurring rules = a template on a schedule, materialised client-side on app
-- open (auto-post, or surfaced for confirmation). Owner-scoped, offline-first.
set search_path to pocketcare, public;

create table if not exists pocketcare.transaction_templates (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  name           text not null,
  type           text not null default 'expense',   -- 'expense' | 'income' | 'transfer'
  amount         int,                                -- minor units; null = ask at use time
  currency       text,
  account_id     uuid,
  to_account_id  uuid,                               -- for transfers
  category_id    uuid,
  description    text,
  note           text,
  payment_method text,
  labels         text,                               -- comma-separated label names
  split_group_id uuid,                               -- if set, using it creates a split in this group
  split_mode     text not null default 'equal',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

create table if not exists pocketcare.recurring_rules (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  template_id    uuid not null references pocketcare.transaction_templates(id) on delete cascade,
  frequency      text not null,                      -- 'daily' | 'weekly' | 'monthly' | 'yearly'
  interval_count int  not null default 1,            -- every N periods
  next_due       date not null,
  last_generated date,
  auto_post      int  not null default 0,            -- 1 = post automatically, 0 = ask to confirm
  active         int  not null default 1,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

create index if not exists templates_user_idx on pocketcare.transaction_templates(user_id);
create index if not exists rules_user_idx on pocketcare.recurring_rules(user_id, next_due);

alter table pocketcare.transaction_templates enable row level security;
create policy tmpl_owner on pocketcare.transaction_templates using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.transaction_templates to anon, authenticated, service_role;

alter table pocketcare.recurring_rules enable row level security;
create policy rules_owner on pocketcare.recurring_rules using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.recurring_rules to anon, authenticated, service_role;
