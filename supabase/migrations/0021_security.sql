-- PocketCare — Hybrid zero-trust encryption support tables.
-- The server stores ONLY wrapped keys + ciphertext; it can never derive a user's
-- key. Support access is user-consented, time-boxed, and hash-chain audited.
set search_path to pocketcare, public;
create extension if not exists pgcrypto with schema extensions;

-- Per-user wrapped keys. The DEK (which encrypts fields) is wrapped by a
-- passphrase-derived key AND by a recovery-code-derived key; only wrapped forms
-- and the salt live here — never the DEK or the passphrase.
create table if not exists user_keys (
  user_id                 uuid primary key references auth.users(id) on delete cascade,
  salt                    text not null,                 -- base64 PBKDF2 salt
  wrapped_dek_passphrase  text not null,                 -- AES-GCM(KEK_passphrase, DEK)
  wrapped_dek_recovery    text,                          -- AES-GCM(KEK_recovery, DEK)
  signing_public_jwk      jsonb,                         -- user's ECDSA public key (verifies consent grants)
  wrapped_signing_private text,                          -- ECDSA private JWK, encrypted under the DEK
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

-- User-consented, time-boxed support grants. Holds the DEK re-wrapped for the
-- SUPPORT public key + the user's signature over the grant payload.
create table if not exists support_grants (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references auth.users(id) on delete cascade,
  scope                   text not null default 'content' check (scope in ('content', 'structural')),
  wrapped_dek_for_support text,                          -- null for structural-only grants
  signature               text not null,                 -- base64 ECDSA over {userId,grantId,exp,scope}
  expires_at              timestamptz not null,
  revoked_at              timestamptz,
  created_at              timestamptz not null default now()
);
create index support_grants_active_idx on support_grants(user_id, expires_at) where revoked_at is null;

-- Append-only, hash-chained security audit. Every grant issue/expire and every
-- support drift-fix / decrypt is recorded; each row chains to the previous row's
-- hash so tampering (edits/deletes) is detectable.
create table if not exists security_audit (
  id           uuid primary key default gen_random_uuid(),
  actor        text not null,                            -- 'user:<uid>' | 'support:<officer>' | 'system'
  action       text not null,                            -- e.g. grant_issued, grant_revoked, drift_fixed, content_decrypted
  subject_user uuid,
  grant_id     uuid,
  detail       text,
  prev_hash    text,
  row_hash     text not null default '',
  created_at   timestamptz not null default now()
);
create index security_audit_created_idx on security_audit(created_at, id);

-- Chain each audit row: prev_hash = last row_hash; row_hash = sha256(prev || fields).
create or replace function pocketcare.security_audit_chain() returns trigger
language plpgsql security definer set search_path = pocketcare, public, extensions as $$
declare last_hash text;
begin
  select row_hash into last_hash from pocketcare.security_audit order by created_at desc, id desc limit 1;
  new.prev_hash := coalesce(last_hash, '');
  new.row_hash := encode(
    extensions.digest(
      new.prev_hash || coalesce(new.actor,'') || coalesce(new.action,'') ||
      coalesce(new.subject_user::text,'') || coalesce(new.grant_id::text,'') ||
      coalesce(new.detail,'') || new.id::text || new.created_at::text,
      'sha256'
    ), 'hex');
  return new;
end $$;

drop trigger if exists security_audit_chain_tr on security_audit;
create trigger security_audit_chain_tr before insert on security_audit
  for each row execute function pocketcare.security_audit_chain();

-- ---- RLS: owner-only; audit is insert+select only (no update/delete policy) ----
alter table user_keys enable row level security;
create policy user_keys_owner on user_keys using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table support_grants enable row level security;
create policy support_grants_owner on support_grants using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table security_audit enable row level security;
create policy security_audit_insert on security_audit for insert with check (
  subject_user = auth.uid() or actor = 'user:' || auth.uid()::text
);
create policy security_audit_read on security_audit for select using (subject_user = auth.uid());
