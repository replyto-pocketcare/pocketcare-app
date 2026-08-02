-- 0048_native_push.sql
-- Add support for native push notifications (FCM + APNs + Live Activities)
-- Converts push_subscriptions from a purely Web Push table to a cross-platform table.
--
-- Re-runnable: uses if exists / if not exists.

set search_path = pocketcare, public;

-- 1. Drop the unique constraint on endpoint (it was created inline so the default name applies)
alter table if exists pocketcare.push_subscriptions
  drop constraint if exists push_subscriptions_endpoint_key;

-- 2. Add the new native columns
alter table pocketcare.push_subscriptions
  add column if not exists platform text not null default 'web',
  add column if not exists token text,
  add column if not exists live_activity_token text;

-- 3. Relax NOT NULL constraints for the Web Push columns
--    Native devices will not supply endpoint, p256dh, or auth.
alter table pocketcare.push_subscriptions
  alter column endpoint drop not null,
  alter column p256dh drop not null,
  alter column auth drop not null;

-- 4. Add new unique constraints to prevent duplicating subscriptions
--    A user should only have one subscription per native token or web endpoint.
--    We use coalesce so we can create a single unique index instead of multiple partial ones if desired,
--    or we can just add unique constraints directly.
do $$ 
begin
  if not exists (select 1 from pg_constraint where conname = 'push_subscriptions_native_token_unique') then
    alter table pocketcare.push_subscriptions
      add constraint push_subscriptions_native_token_unique unique (token);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'push_subscriptions_endpoint_unique') then
    alter table pocketcare.push_subscriptions
      add constraint push_subscriptions_endpoint_unique unique (endpoint);
  end if;
end $$;
