-- 0050_group_demographics_and_triggers.sql
-- Adds demographics tracking, opt-in mapping via triggers, and seeds default lists.

set search_path = pocketcare, public;

-- 1. Add demographic fields to profiles
alter table pocketcare.profiles
  add column if not exists ip_region text;

-- 2. Add sys_key to groups to strictly identify system-managed groups
alter table pocketcare.notification_groups
  add column if not exists sys_key text unique;

-- 3. Seed default system groups for settings opt-ins
insert into pocketcare.notification_groups (name, description, sys_key) values
  ('Alerts: Upcoming EMIs & bills', 'Users opted into EMI/Bill due reminders', 'opt-in:emi_due'),
  ('Alerts: Budget limits', 'Users opted into Budget threshold alerts', 'opt-in:budget'),
  ('Alerts: Low balance', 'Users opted into Low balance warnings', 'opt-in:low_balance'),
  ('Alerts: Unusual transactions', 'Users opted into AI outlier alerts', 'opt-in:outlier'),
  ('Alerts: Group activity', 'Users opted into Group invite/join alerts', 'opt-in:group_invite'),
  ('Alerts: Shared expenses', 'Users opted into Split expense alerts', 'opt-in:group_expense')
on conflict (sys_key) do nothing;

-- 4. Create trigger to sync prefs to groups
create or replace function pocketcare.sync_notification_prefs_to_groups()
returns trigger as $$
declare
  v_group_id uuid;
begin
  -- emi_due
  select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:emi_due';
  if v_group_id is not null then
    if new.emi_due = true then
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, new.user_id) on conflict do nothing;
    else
      delete from pocketcare.notification_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  -- budget
  select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:budget';
  if v_group_id is not null then
    if new.budget = true then
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, new.user_id) on conflict do nothing;
    else
      delete from pocketcare.notification_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  -- low_balance
  select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:low_balance';
  if v_group_id is not null then
    if new.low_balance = true then
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, new.user_id) on conflict do nothing;
    else
      delete from pocketcare.notification_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  -- outlier
  select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:outlier';
  if v_group_id is not null then
    if new.outlier = true then
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, new.user_id) on conflict do nothing;
    else
      delete from pocketcare.notification_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  -- group_invite
  select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:group_invite';
  if v_group_id is not null then
    if new.group_invite = true then
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, new.user_id) on conflict do nothing;
    else
      delete from pocketcare.notification_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  -- group_expense
  select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:group_expense';
  if v_group_id is not null then
    if new.group_expense = true then
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, new.user_id) on conflict do nothing;
    else
      delete from pocketcare.notification_group_members where group_id = v_group_id and user_id = new.user_id;
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_sync_notification_prefs on pocketcare.notification_prefs;
create trigger trg_sync_notification_prefs
  after insert or update on pocketcare.notification_prefs
  for each row execute function pocketcare.sync_notification_prefs_to_groups();

-- 5. One-time backfill of existing prefs
do $$
declare
  pref record;
  v_group_id uuid;
begin
  for pref in select * from pocketcare.notification_prefs loop
    if pref.emi_due = true then
      select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:emi_due';
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, pref.user_id) on conflict do nothing;
    end if;
    if pref.budget = true then
      select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:budget';
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, pref.user_id) on conflict do nothing;
    end if;
    if pref.low_balance = true then
      select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:low_balance';
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, pref.user_id) on conflict do nothing;
    end if;
    if pref.outlier = true then
      select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:outlier';
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, pref.user_id) on conflict do nothing;
    end if;
    if pref.group_invite = true then
      select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:group_invite';
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, pref.user_id) on conflict do nothing;
    end if;
    if pref.group_expense = true then
      select id into v_group_id from pocketcare.notification_groups where sys_key = 'opt-in:group_expense';
      insert into pocketcare.notification_group_members (group_id, user_id) values (v_group_id, pref.user_id) on conflict do nothing;
    end if;
  end loop;
end;
$$;
