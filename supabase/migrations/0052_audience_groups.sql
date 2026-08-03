-- 0052_audience_groups.sql
-- Promotes notification groups to first-class audience groups.

set search_path = pocketcare, public;

-- 1. Rename tables and constraints
alter table pocketcare.notification_group_members rename to audience_group_members;
alter table pocketcare.notification_groups rename to audience_groups;

-- Rename indices if any
alter index if exists group_members_user_idx rename to audience_group_members_user_idx;
alter index if exists notification_groups_pkey rename to audience_groups_pkey;
alter index if exists notification_group_members_pkey rename to audience_group_members_pkey;
alter table pocketcare.audience_groups rename constraint notification_groups_sys_key_key to audience_groups_sys_key_key;

-- 2. Add new columns
alter table pocketcare.audience_groups
  add column if not exists kind text,
  add column if not exists rule jsonb,
  add column if not exists active boolean not null default true;

alter table pocketcare.audience_group_members
  add column if not exists source text;

-- 3. Backfill new columns
update pocketcare.audience_groups
  set kind = case when sys_key like 'opt-in:%' then 'optin' else 'manual' end
  where kind is null;

update pocketcare.audience_group_members agm
  set source = case when g.sys_key like 'opt-in:%' then 'optin' else 'admin' end
  from pocketcare.audience_groups g
  where agm.group_id = g.id and agm.source is null;

-- Make columns not null where appropriate if required, but leaving it flexible for now.

-- 4. Create compatibility views
create or replace view pocketcare.notification_groups as
  select id, name, description, created_at, sys_key
  from pocketcare.audience_groups;

create or replace view pocketcare.notification_group_members as
  select group_id, user_id, joined_at
  from pocketcare.audience_group_members;

-- 5. Fix RLS policies

-- audience_groups policies
drop policy if exists groups_read on pocketcare.audience_groups;
drop policy if exists audience_groups_read on pocketcare.audience_groups;
create policy audience_groups_read on pocketcare.audience_groups
  for select using (
    exists (
      select 1 from pocketcare.audience_group_members agm
      where agm.group_id = id and agm.user_id = auth.uid()
    )
  );

-- audience_group_members policies
drop policy if exists group_members_read on pocketcare.audience_group_members;
drop policy if exists group_members_insert on pocketcare.audience_group_members;
drop policy if exists group_members_delete on pocketcare.audience_group_members;
drop policy if exists audience_group_members_read on pocketcare.audience_group_members;
drop policy if exists audience_group_members_self_optin on pocketcare.audience_group_members;
drop policy if exists audience_group_members_self_optout on pocketcare.audience_group_members;

create policy audience_group_members_read on pocketcare.audience_group_members
  for select using (user_id = auth.uid());

create policy audience_group_members_self_optin on pocketcare.audience_group_members
  for insert with check (
    user_id = auth.uid()
    and exists (select 1 from pocketcare.audience_groups g
                 where g.id = group_id and g.sys_key like 'opt-in:%')
  );

create policy audience_group_members_self_optout on pocketcare.audience_group_members
  for delete using (
    user_id = auth.uid()
    and exists (select 1 from pocketcare.audience_groups g
                 where g.id = group_id and g.sys_key like 'opt-in:%')
  );

-- 6. Update sync trigger function
create or replace function pocketcare.sync_notification_prefs_to_groups()
returns trigger as $$
declare
  v_group_id uuid;
begin
  -- emi_due
  select id into v_group_id from pocketcare.audience_groups where sys_key = 'opt-in:emi_due';
  if v_group_id is not null then
    if new.emi_due = true then
      insert into pocketcare.audience_group_members (group_id, user_id, source) values (v_group_id, new.user_id, 'optin') on conflict do nothing;
    else
      delete from pocketcare.audience_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  -- budget
  select id into v_group_id from pocketcare.audience_groups where sys_key = 'opt-in:budget';
  if v_group_id is not null then
    if new.budget = true then
      insert into pocketcare.audience_group_members (group_id, user_id, source) values (v_group_id, new.user_id, 'optin') on conflict do nothing;
    else
      delete from pocketcare.audience_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  -- low_balance
  select id into v_group_id from pocketcare.audience_groups where sys_key = 'opt-in:low_balance';
  if v_group_id is not null then
    if new.low_balance = true then
      insert into pocketcare.audience_group_members (group_id, user_id, source) values (v_group_id, new.user_id, 'optin') on conflict do nothing;
    else
      delete from pocketcare.audience_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  -- outlier
  select id into v_group_id from pocketcare.audience_groups where sys_key = 'opt-in:outlier';
  if v_group_id is not null then
    if new.outlier = true then
      insert into pocketcare.audience_group_members (group_id, user_id, source) values (v_group_id, new.user_id, 'optin') on conflict do nothing;
    else
      delete from pocketcare.audience_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  -- group_invite
  select id into v_group_id from pocketcare.audience_groups where sys_key = 'opt-in:group_invite';
  if v_group_id is not null then
    if new.group_invite = true then
      insert into pocketcare.audience_group_members (group_id, user_id, source) values (v_group_id, new.user_id, 'optin') on conflict do nothing;
    else
      delete from pocketcare.audience_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  -- group_expense
  select id into v_group_id from pocketcare.audience_groups where sys_key = 'opt-in:group_expense';
  if v_group_id is not null then
    if new.group_expense = true then
      insert into pocketcare.audience_group_members (group_id, user_id, source) values (v_group_id, new.user_id, 'optin') on conflict do nothing;
    else
      delete from pocketcare.audience_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer;
