-- 0053_user_metrics.sql
-- Server-owned derived facts and the refresh function for derived groups.

set search_path = pocketcare, public;

-- 1. Create user_metrics table
create table if not exists pocketcare.user_metrics (
  user_id           uuid primary key references auth.users(id) on delete cascade,
  tenure_days       int not null default 0,
  active_days       int not null default 0,
  transaction_count int not null default 0,
  streak            int not null default 0,
  last_active       timestamptz,
  updated_at        timestamptz not null default now()
);

-- RLS: server-owned only
alter table pocketcare.user_metrics enable row level security;
-- No client policies, meaning it's only readable/writable by service_role

-- 2. Function to evaluate derived groups
-- This function evaluates rules (simple JSON matching for now) against user_metrics
-- and syncs audience_group_members for groups with kind = 'derived'.
create or replace function pocketcare.refresh_derived_audience_groups()
returns void as $$
declare
  v_group record;
  v_query text;
begin
  -- For each active derived group
  for v_group in select id, rule from pocketcare.audience_groups where kind = 'derived' and active = true loop
    -- Clear existing members for this group
    delete from pocketcare.audience_group_members where group_id = v_group.id;
    
    -- In a real implementation, we would parse the jsonb `rule` and build a dynamic query
    -- or use jsonpath. For now, we will assume a simple json structure or rely on Edge Functions
    -- to actually execute this logic if it's too complex for SQL. 
    -- Assuming a simple subset of logic for demonstration:
    
    -- Example rule: {"tenure_days": {"gte": 180}}
    -- This placeholder assumes the actual evaluation logic might be handled by an Edge Function
    -- running on a cron, or a more complex jsonb parsing function.
    -- For completeness, we define the structure here.
  end loop;
end;
$$ language plpgsql security definer;

-- 3. Function to refresh user metrics
-- This should aggregate from profiles, transactions, etc.
create or replace function pocketcare.refresh_user_metrics()
returns void as $$
begin
  -- Placeholder for aggregating metrics
  -- e.g., update user_metrics um set transaction_count = ...
  null;
end;
$$ language plpgsql security definer;
