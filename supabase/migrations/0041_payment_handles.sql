-- 0041_payment_handles.sql
--
-- Pay a friend over UPI to settle a split balance.
--
-- PocketCare NEVER touches the money. We hand the payer's own UPI app a
-- prefilled Intent link (upi://pay?...) and the transfer happens bank-to-bank
-- between two individuals. No payment aggregator, no escrow, no merchant
-- account. See docs/features/upi-settle-up.md.
--
-- Three parts:
--   payment_handles              — a user's UPI ID. SERVER-ONLY, NOT SYNCED.
--   payment_handle_disclosures   — audit of who fetched whose handle.
--   settlements.status + friends — two-sided confirmation of a claimed payment.
--
-- SECURITY MODEL (deliberately NOT zero-trust — read this before changing it):
-- The existing zero-trust scheme wraps a DEK with a passphrase-derived KEK
-- owned by ONE user, so a co-member could never decrypt another user's field.
-- A shared payment handle fundamentally has to be readable by the payer, so it
-- cannot use that scheme. Instead the handle is encrypted at rest with a
-- SERVER-held key and released just-in-time by the `payment-handle` edge
-- function, only to a caller who shares a group AND has a live balance with the
-- owner, with an audit row written per release. The server can read these
-- values; personal protected fields it still cannot.
--
-- Apply: supabase db push → redeploy sync-streams.yaml (settlements gained
-- columns) → supabase functions deploy payment-handle.

set search_path = pocketcare, public;

-- pgcrypto gives us pgp_sym_encrypt/decrypt for the at-rest envelope.
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- payment_handles — server-only, never added to sync-streams.yaml
-- ---------------------------------------------------------------------------
create table if not exists pocketcare.payment_handles (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references pocketcare.profiles(id) on delete cascade,
  kind         text not null default 'upi',        -- upi | bank | iban (future)
  handle_enc   text not null,                      -- encrypted VPA; never plaintext at rest
  handle_hint  text not null,                      -- masked, e.g. akh••••@okhdfcbank
  display_name text,                               -- prefilled as pn= in the intent link
  is_primary   boolean not null default true,
  -- Reserved. We do NOT verify handle ownership: doing so needs a penny-drop
  -- through a PSP, which is exactly the regulated path this design avoids.
  verified_at  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  constraint payment_handles_kind_valid check (kind in ('upi', 'bank', 'iban'))
);

-- One live primary handle per kind per user.
create unique index if not exists payment_handles_primary_idx
  on pocketcare.payment_handles (user_id, kind)
  where is_primary and deleted_at is null;

alter table pocketcare.payment_handles enable row level security;
-- Owner may read their own row (to see the hint) but the ciphertext is useless
-- to the client — only the edge function holds the key.
drop policy if exists payment_handles_owner on pocketcare.payment_handles;
create policy payment_handles_owner on pocketcare.payment_handles for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table pocketcare.payment_handles to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- payment_handle_disclosures — who fetched whose handle, and when
-- ---------------------------------------------------------------------------
create table if not exists pocketcare.payment_handle_disclosures (
  id             uuid primary key default gen_random_uuid(),
  owner_user_id  uuid not null references pocketcare.profiles(id) on delete cascade,
  viewer_user_id uuid not null references pocketcare.profiles(id) on delete cascade,
  group_id       uuid references pocketcare.split_groups(id) on delete set null,
  created_at     timestamptz not null default now()
);

create index if not exists phd_owner_idx  on pocketcare.payment_handle_disclosures(owner_user_id, created_at desc);
create index if not exists phd_viewer_idx on pocketcare.payment_handle_disclosures(viewer_user_id, created_at desc);

alter table pocketcare.payment_handle_disclosures enable row level security;
-- The OWNER reads their own audit trail. Viewers don't need to see it.
drop policy if exists phd_owner_read on pocketcare.payment_handle_disclosures;
create policy phd_owner_read on pocketcare.payment_handle_disclosures for select
  using (owner_user_id = auth.uid());
grant all on table pocketcare.payment_handle_disclosures to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Guests may not save a payment handle
--
-- A UPI ID is a financial identifier tied to a real identity; a 3-day throwaway
-- guest account is the wrong place for one. Enforced in the DB rather than only
-- in the UI, because the edge function runs as service_role and would otherwise
-- bypass a client-side check.
-- ---------------------------------------------------------------------------
-- Checks auth.users.is_anonymous rather than the presence of a guest_sessions
-- row: guest→registered is an in-place UID upgrade that leaves the
-- guest_sessions row behind, so keying off that table would permanently lock
-- out anyone who started as a guest. (It also has no deleted_at column.)
create or replace function pocketcare.check_handle_not_guest()
returns trigger language plpgsql security definer
set search_path = pocketcare, public, auth as $$
begin
  if coalesce((select u.is_anonymous from auth.users u where u.id = NEW.user_id), false) then
    raise exception 'Guest accounts cannot save a payment handle. Create an account first.'
      using errcode = 'check_violation';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_handle_not_guest on pocketcare.payment_handles;
create trigger trg_handle_not_guest
  before insert or update on pocketcare.payment_handles
  for each row execute function pocketcare.check_handle_not_guest();

revoke all on function pocketcare.check_handle_not_guest() from public;
grant execute on function pocketcare.check_handle_not_guest() to authenticated, anon, service_role;

-- ---------------------------------------------------------------------------
-- RPCs used ONLY by the `payment-handle` edge function (service_role).
--
-- The encryption key is passed in as an argument so it lives in the function's
-- secrets and never in the database. Plaintext exists only inside these
-- function bodies — it is never selectable from a column.
-- ---------------------------------------------------------------------------

create or replace function pocketcare.upsert_payment_handle(
  p_user uuid, p_vpa text, p_hint text, p_name text, p_key text
) returns void language plpgsql security definer
set search_path = pocketcare, public, extensions as $$
begin
  update pocketcare.payment_handles
     set deleted_at = now(), is_primary = false, updated_at = now()
   where user_id = p_user and kind = 'upi' and deleted_at is null;

  insert into pocketcare.payment_handles (user_id, kind, handle_enc, handle_hint, display_name, is_primary)
  values (p_user, 'upi', extensions.pgp_sym_encrypt(p_vpa, p_key), p_hint, p_name, true);
end;
$$;

create or replace function pocketcare.read_payment_handle(p_user uuid, p_key text)
returns table (vpa text, display_name text)
language plpgsql security definer
set search_path = pocketcare, public, extensions as $$
begin
  return query
    select extensions.pgp_sym_decrypt(h.handle_enc::bytea, p_key), h.display_name
      from pocketcare.payment_handles h
     where h.user_id = p_user and h.kind = 'upi' and h.is_primary and h.deleted_at is null
     limit 1;
end;
$$;

/**
 * The disclosure gate: may `p_viewer` see `p_owner`'s payment handle?
 *
 * Returns the shared group (null = no relationship) and whether any shared
 * financial activity exists. `has_activity` deliberately checks for the
 * EXISTENCE of shared expenses or settlements rather than an exactly non-zero
 * pairwise net: the net is allocated client-side (pairwiseEdges) and
 * reimplementing that here would risk the gate disagreeing with the balance the
 * user can see. This is still a hard block on harvesting handles from strangers.
 */
create or replace function pocketcare.payment_handle_gate(p_viewer uuid, p_owner uuid)
returns table (shared_group uuid, has_activity boolean)
language plpgsql security definer
set search_path = pocketcare, public as $$
declare
  g uuid;
begin
  select m1.group_id into g
    from pocketcare.split_group_members m1
    join pocketcare.split_group_members m2 on m1.group_id = m2.group_id
   where m1.user_id = p_viewer and m2.user_id = p_owner
     and m1.deleted_at is null and m2.deleted_at is null
   limit 1;

  if g is null then
    return query select null::uuid, false;
    return;
  end if;

  return query
    select g, exists (
      select 1
        from pocketcare.expenses e
        join pocketcare.expense_participants pv on pv.expense_id = e.id and pv.user_id = p_viewer
        join pocketcare.expense_participants po on po.expense_id = e.id and po.user_id = p_owner
       where e.deleted_at is null and pv.deleted_at is null and po.deleted_at is null
    ) or exists (
      select 1 from pocketcare.settlements s
       where s.deleted_at is null
         and ((s.from_user = p_viewer and s.to_user = p_owner)
           or (s.from_user = p_owner and s.to_user = p_viewer))
    );
end;
$$;

revoke all on function pocketcare.upsert_payment_handle(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function pocketcare.read_payment_handle(uuid, text) from public, anon, authenticated;
revoke all on function pocketcare.payment_handle_gate(uuid, uuid) from public, anon, authenticated;
grant execute on function pocketcare.upsert_payment_handle(uuid, text, text, text, text) to service_role;
grant execute on function pocketcare.read_payment_handle(uuid, text) to service_role;
grant execute on function pocketcare.payment_handle_gate(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- settlements: two-sided confirmation
--
-- `status` defaults to 'confirmed' so every existing row, and the current
-- in-app "mark settled" flow, keep their exact present meaning. Only the new
-- UPI flow writes 'pending'.
-- ---------------------------------------------------------------------------
alter table pocketcare.settlements
  add column if not exists status       text not null default 'confirmed',
  add column if not exists confirmed_at timestamptz,
  add column if not exists confirmed_by uuid,
  add column if not exists upi_ref      text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'settlements_status_valid'
  ) then
    alter table pocketcare.settlements
      add constraint settlements_status_valid
      check (status in ('confirmed', 'pending', 'disputed'));
  end if;
end
$$;

create index if not exists settlements_status_idx on pocketcare.settlements(status);

-- ---------------------------------------------------------------------------
-- Notify the payee that a payment is claimed and needs confirming
-- ---------------------------------------------------------------------------
alter table pocketcare.notification_prefs
  add column if not exists settlement_confirm boolean not null default true;

create or replace function pocketcare.tg_notify_settlement_pending()
returns trigger language plpgsql security definer
set search_path = pocketcare, public as $$
declare
  recip     uuid;
  oname     text;
  amt_major text;
begin
  if NEW.status is distinct from 'pending' then
    return NEW;
  end if;

  -- The party who did NOT record it is the one who can actually verify arrival.
  recip := case when NEW.created_by = NEW.from_user then NEW.to_user else NEW.from_user end;
  if recip is null or recip = NEW.created_by then
    return NEW;
  end if;

  amt_major := trim(to_char(NEW.amount / 100.0, 'FM999999990.00'));
  select coalesce(nullif(display_name, ''), email, 'Someone') into oname
    from pocketcare.profiles where id = NEW.created_by;

  if coalesce((select settlement_confirm from pocketcare.notification_prefs
               where user_id = recip and deleted_at is null limit 1), true) then
    insert into pocketcare.notifications (user_id, kind, title, body, severity, href, dedupe_key)
    values (
      recip, 'settlement',
      'Confirm a payment',
      oname || ' says they paid you ' || NEW.currency || ' ' || amt_major
        || ' · tap to confirm it arrived',
      'info',
      '/friends?confirm=' || NEW.id,
      'settle-confirm:' || NEW.id
    )
    on conflict (user_id, dedupe_key) where dedupe_key is not null and deleted_at is null do nothing;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_notify_settlement_pending on pocketcare.settlements;
create trigger trg_notify_settlement_pending
  after insert on pocketcare.settlements
  for each row execute function pocketcare.tg_notify_settlement_pending();

revoke all on function pocketcare.tg_notify_settlement_pending() from public;
grant execute on function pocketcare.tg_notify_settlement_pending() to authenticated, anon, service_role;

-- ---------------------------------------------------------------------------
-- Pending settlements must not hang forever
--
-- If the payee never opens the app, the payer is left looking like they still
-- owe money they've already sent. Nudge at 3 days, auto-confirm at 14 — called
-- from the notify-dispatch cron.
-- ---------------------------------------------------------------------------
create or replace function pocketcare.sweep_pending_settlements()
returns void language plpgsql security definer
set search_path = pocketcare, public as $$
begin
  -- Nudge: a reminder for anything pending over 3 days but not yet expired.
  insert into pocketcare.notifications (user_id, kind, title, body, severity, href, dedupe_key)
  select
    case when s.created_by = s.from_user then s.to_user else s.from_user end,
    'settlement',
    'Still waiting on your confirmation',
    'A payment of ' || s.currency || ' ' || trim(to_char(s.amount / 100.0, 'FM999999990.00'))
      || ' is waiting for you to confirm it arrived.',
    'info',
    '/friends?confirm=' || s.id,
    'settle-nudge:' || s.id
  from pocketcare.settlements s
  where s.status = 'pending'
    and s.deleted_at is null
    and s.created_at < now() - interval '3 days'
    and s.created_at >= now() - interval '14 days'
  on conflict (user_id, dedupe_key) where dedupe_key is not null and deleted_at is null do nothing;

  -- Auto-confirm after 14 days. The payer's cash already moved; leaving the
  -- debt open indefinitely is the worse error.
  update pocketcare.settlements
     set status = 'confirmed',
         confirmed_at = now(),
         updated_at = now()
   where status = 'pending'
     and deleted_at is null
     and created_at < now() - interval '14 days';
end;
$$;

revoke all on function pocketcare.sweep_pending_settlements() from public;
grant execute on function pocketcare.sweep_pending_settlements() to service_role;
