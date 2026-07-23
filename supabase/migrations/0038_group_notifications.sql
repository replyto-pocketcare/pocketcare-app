-- 0038_group_notifications.sql
-- Event-driven notifications for shared groups/trips:
--   * someone joins a group you're in            (kind: group_invite)
--   * someone adds a split expense to your group  (kind: group_expense)
-- Plus two new preference toggles and a `pushed_at` flag so the dispatcher can
-- deliver Web Push for rows created here (not just cron-computed ones).

set search_path = pocketcare, public;

-- --- prefs + push bookkeeping ------------------------------------------------
alter table pocketcare.notification_prefs
  add column if not exists group_invite  boolean not null default true,
  add column if not exists group_expense boolean not null default true;

alter table pocketcare.notifications
  add column if not exists pushed_at timestamptz;

create index if not exists notifications_user_unpushed_idx
  on pocketcare.notifications(user_id, pushed_at) where pushed_at is null and deleted_at is null;

-- --- helper: does a user want this kind? (default yes when no prefs row) ------
-- Inlined into the triggers below via a LEFT JOIN on notification_prefs.

-- --- group membership: notify existing members + the joiner ------------------
create or replace function pocketcare.tg_notify_group_join()
returns trigger
language plpgsql
security definer
set search_path = pocketcare, public
as $$
declare
  gname text;
  jname text;
  has_others boolean;
begin
  select name into gname from pocketcare.split_groups where id = NEW.group_id;
  select coalesce(nullif(display_name, ''), email, 'Someone')
    into jname from pocketcare.profiles where id = NEW.user_id;

  select exists(
    select 1 from pocketcare.split_group_members
    where group_id = NEW.group_id and user_id <> NEW.user_id and deleted_at is null
  ) into has_others;

  -- Solo group creation (owner adds themselves, nobody else present) → silent.
  if not has_others then
    return NEW;
  end if;

  -- Tell the existing members that someone joined.
  insert into pocketcare.notifications (user_id, kind, title, body, severity, href, dedupe_key)
  select m.user_id, 'group_invite',
         jname || ' joined ' || coalesce(gname, 'a group'),
         null, 'info', '/groups/' || NEW.group_id, 'gjoin:' || NEW.id
  from pocketcare.split_group_members m
  left join pocketcare.notification_prefs p on p.user_id = m.user_id and p.deleted_at is null
  where m.group_id = NEW.group_id and m.deleted_at is null and m.user_id <> NEW.user_id
    and coalesce(p.group_invite, true)
  on conflict (user_id, dedupe_key) where dedupe_key is not null and deleted_at is null do nothing;

  -- Tell the joiner they're now in the group.
  if coalesce((select group_invite from pocketcare.notification_prefs
               where user_id = NEW.user_id and deleted_at is null limit 1), true) then
    insert into pocketcare.notifications (user_id, kind, title, body, severity, href, dedupe_key)
    values (NEW.user_id, 'group_invite', 'You joined ' || coalesce(gname, 'a group'),
            null, 'info', '/groups/' || NEW.group_id, 'gjoined:' || NEW.id)
    on conflict (user_id, dedupe_key) where dedupe_key is not null and deleted_at is null do nothing;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_notify_group_join on pocketcare.split_group_members;
create trigger trg_notify_group_join
  after insert on pocketcare.split_group_members
  for each row execute function pocketcare.tg_notify_group_join();

-- --- group expense: notify everyone in the group except the payer ------------
create or replace function pocketcare.tg_notify_group_expense()
returns trigger
language plpgsql
security definer
set search_path = pocketcare, public
as $$
declare
  gname text;
  cname text;
  amt   text;
begin
  select name into gname from pocketcare.split_groups where id = NEW.group_id;
  select coalesce(nullif(display_name, ''), email, 'Someone')
    into cname from pocketcare.profiles where id = NEW.created_by;
  amt := NEW.currency || ' ' || trim(to_char(NEW.amount / 100.0, 'FM999999990.00'));

  insert into pocketcare.notifications (user_id, kind, title, body, severity, href, dedupe_key)
  select m.user_id, 'group_expense',
         cname || ' added an expense in ' || coalesce(gname, 'a group'),
         coalesce(nullif(NEW.description, ''), 'Expense') || ' · ' || amt,
         'info', '/groups/' || NEW.group_id, 'gexp:' || NEW.id
  from pocketcare.split_group_members m
  left join pocketcare.notification_prefs p on p.user_id = m.user_id and p.deleted_at is null
  where m.group_id = NEW.group_id and m.deleted_at is null and m.user_id <> NEW.created_by
    and coalesce(p.group_expense, true)
  on conflict (user_id, dedupe_key) where dedupe_key is not null and deleted_at is null do nothing;

  return NEW;
end;
$$;

drop trigger if exists trg_notify_group_expense on pocketcare.expenses;
create trigger trg_notify_group_expense
  after insert on pocketcare.expenses
  for each row execute function pocketcare.tg_notify_group_expense();
