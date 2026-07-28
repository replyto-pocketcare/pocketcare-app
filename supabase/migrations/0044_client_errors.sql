-- 0044_client_errors.sql
--
-- Automatic client error reporting, so failures reach the admin panel WITHOUT
-- the user having to notice, care, and file a bug report.
--
-- The motivating case: a user says "syncing isn't working". On a phone there is
-- no console to look at, and most people never file a report — so the one place
-- the actual PostgREST error exists is a device nobody can reach.
--
-- DESIGN NOTES
-- ------------
-- * Errors are DEDUPED by fingerprint. One row per (fingerprint, user), with a
--   `count` and `last_seen`, so a tight retry loop produces one row that says
--   "×412" rather than 412 rows. Without this the table is unusable within a day.
-- * Reported via an RPC, NOT through PowerSync. The failure we most need to see
--   is the sync queue being stuck — routing the report through that same queue
--   would guarantee it never arrives. The client calls this directly over HTTP.
-- * Payloads are redacted ON THE CLIENT before they are sent
--   (packages/core/diagnostics): no amounts, descriptions, merchants, emails or
--   payment handles. Table names, operations, error codes and row ids survive.
-- * Rate limited server-side as well as client-side — a client-side cap is a
--   suggestion, not a guarantee.

set search_path = pocketcare, public;

create table if not exists pocketcare.client_errors (
  id           uuid primary key default gen_random_uuid(),
  -- Stable hash of scope + normalised message: groups the same bug together.
  fingerprint  text not null,
  -- SET NULL, not CASCADE: a deleted account shouldn't erase the evidence of a
  -- bug it hit. The row keeps no personal data anyway.
  user_id      uuid references pocketcare.profiles(id) on delete set null,
  level        text not null default 'error',
  scope        text,
  message      text not null,
  detail       jsonb,
  route        text,
  app_version  text,
  platform     text,
  user_agent   text,
  count        int not null default 1,
  first_seen   timestamptz not null default now(),
  last_seen    timestamptz not null default now(),
  -- Set from the admin panel once you've dealt with it.
  resolved_at  timestamptz,
  resolved_note text
);

create unique index if not exists client_errors_fingerprint_user_idx
  on pocketcare.client_errors (fingerprint, coalesce(user_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index if not exists client_errors_last_seen_idx on pocketcare.client_errors (last_seen desc);
create index if not exists client_errors_unresolved_idx on pocketcare.client_errors (resolved_at) where resolved_at is null;

-- No client reads or writes go through RLS — everything is via the RPC below
-- (SECURITY DEFINER) and the admin panel's service-role client.
alter table pocketcare.client_errors enable row level security;
grant select, insert, update on table pocketcare.client_errors to service_role;

-- ---------------------------------------------------------------------------
-- report_client_error — the only way a client writes here.
--
-- Upserts on (fingerprint, user), bumping count and last_seen. Returns nothing:
-- reporting must never become something the app waits on or reacts to.
-- ---------------------------------------------------------------------------
create or replace function pocketcare.report_client_error(
  p_fingerprint text,
  p_message     text,
  p_level       text default 'error',
  p_scope       text default null,
  p_detail      jsonb default null,
  p_route       text default null,
  p_version     text default null,
  p_platform    text default null,
  p_user_agent  text default null
) returns void
language plpgsql security definer
set search_path = pocketcare, public as $$
declare
  uid uuid := auth.uid();
  recent int;
begin
  if p_fingerprint is null or p_message is null then
    return;
  end if;

  -- Server-side rate limit. A client-side cap is a suggestion; a runaway loop,
  -- an old build, or a hostile client would otherwise flood the table.
  select count(*) into recent
    from pocketcare.client_errors
   where user_id is not distinct from uid
     and last_seen > now() - interval '1 hour';
  if recent > 50 then
    return;
  end if;

  insert into pocketcare.client_errors (
    fingerprint, user_id, level, scope, message, detail,
    route, app_version, platform, user_agent
  )
  values (
    p_fingerprint, uid, coalesce(p_level, 'error'), p_scope, left(p_message, 1000), p_detail,
    p_route, p_version, p_platform, left(coalesce(p_user_agent, ''), 300)
  )
  on conflict (fingerprint, coalesce(user_id, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set
    count      = pocketcare.client_errors.count + 1,
    last_seen  = now(),
    -- Keep the most recent context: where it happened last is more useful than
    -- where it happened first.
    route      = coalesce(excluded.route, pocketcare.client_errors.route),
    detail     = coalesce(excluded.detail, pocketcare.client_errors.detail),
    app_version = coalesce(excluded.app_version, pocketcare.client_errors.app_version),
    -- Re-opens if it recurs after being marked resolved.
    resolved_at = null;
end;
$$;

revoke all on function pocketcare.report_client_error(text, text, text, text, jsonb, text, text, text, text) from public;
grant execute on function pocketcare.report_client_error(text, text, text, text, jsonb, text, text, text, text)
  to authenticated, anon, service_role;
