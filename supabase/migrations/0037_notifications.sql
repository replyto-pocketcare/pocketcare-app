-- 0037_notifications.sql
-- In-app + Web Push notifications.
--   notifications        : per-user inbox rows (synced via PowerSync).
--   notification_prefs    : per-user toggles + thresholds (synced).
--   push_subscriptions    : browser Web Push endpoints (server-side only; NOT
--                           synced through PowerSync — written directly by the
--                           client and read by the notify-dispatch edge fn).

set search_path = pocketcare, public;

-- ---------------------------------------------------------------------------
-- Inbox
-- ---------------------------------------------------------------------------
create table if not exists pocketcare.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references pocketcare.profiles(id) on delete cascade,
  kind        text not null,                    -- emi_due | budget | low_balance | outlier | system
  title       text not null,
  body        text,
  severity    text not null default 'info',     -- info | warn | urgent
  href        text,                             -- in-app deep link (e.g. /loans/<id>)
  data        jsonb,                            -- structured payload for the client
  dedupe_key  text,                             -- stops re-alerting the same event
  read_at     timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- One live notification per (user, dedupe_key): the dispatcher upserts on this
-- so re-running the job doesn't spam duplicates for the same EMI/budget/etc.
create unique index if not exists notifications_user_dedupe_idx
  on pocketcare.notifications(user_id, dedupe_key) where dedupe_key is not null and deleted_at is null;
create index if not exists notifications_user_unread_idx
  on pocketcare.notifications(user_id, read_at) where deleted_at is null;

alter table pocketcare.notifications enable row level security;
create policy notif_all on pocketcare.notifications for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.notifications to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Preferences (one row per user; id kept for PowerSync's required text pk)
-- ---------------------------------------------------------------------------
create table if not exists pocketcare.notification_prefs (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null unique references pocketcare.profiles(id) on delete cascade,
  push_enabled           boolean not null default false,
  emi_due                boolean not null default true,
  budget                 boolean not null default true,
  low_balance            boolean not null default true,
  outlier                boolean not null default true,
  low_balance_threshold  integer not null default 0,   -- minor units; 0 = alert only on negative
  emi_lead_days          integer not null default 3,   -- how many days before an EMI/bill to alert
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  deleted_at             timestamptz
);

alter table pocketcare.notification_prefs enable row level security;
create policy notif_prefs_all on pocketcare.notification_prefs for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.notification_prefs to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Web Push subscriptions (server-side; not synced)
-- ---------------------------------------------------------------------------
create table if not exists pocketcare.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references pocketcare.profiles(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  user_agent  text,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on pocketcare.push_subscriptions(user_id);

alter table pocketcare.push_subscriptions enable row level security;
create policy push_sub_all on pocketcare.push_subscriptions for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.push_subscriptions to anon, authenticated, service_role;
