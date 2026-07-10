-- PocketCare — beta bug reports + reward coupons.
-- Testers file low-effort reports; hitting 5 reports auto-grants a 1-month Lite
-- coupon, 25 grants Pro. Coupons are strictly per-user and time-bound.
set search_path to pocketcare, public;
create extension if not exists pgcrypto with schema extensions;

create table if not exists bug_reports (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  severity     text not null check (severity in ('fatal','high','medium','low')),
  area         text,                         -- feature / page the report is about
  title        text,
  description  text not null,
  -- auto-captured context (keeps the tester's effort minimal)
  app_version  text,
  route        text,
  platform     text,
  user_agent   text,
  viewport     text,
  online       boolean,
  status       text not null default 'open',
  created_at   timestamptz not null default now()
);
create index bug_reports_user_idx on bug_reports(user_id, created_at);

create table if not exists coupons (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  user_id       uuid not null references auth.users(id) on delete cascade,
  tier          text not null check (tier in ('lite','pro')),
  months        int not null default 1,
  reason        text,                        -- e.g. beta_5_lite / beta_25_pro
  expires_at    timestamptz not null,        -- redeem-by deadline (time-bound)
  redeemed_at   timestamptz,
  applied_until timestamptz,                 -- comp end once redeemed
  created_at    timestamptz not null default now()
);
create index coupons_user_idx on coupons(user_id);
-- One coupon per milestone reason per user.
create unique index coupons_user_reason_uq on coupons(user_id, reason) where reason is not null;

-- Time-bound complimentary plan (from a redeemed coupon), kept separate from a
-- real paid subscription so it can't collide with billing.
alter table entitlements add column if not exists comp_tier  text;
alter table entitlements add column if not exists comp_until  timestamptz;

-- Auto-award coupons as bug-report milestones are reached.
create or replace function pocketcare.award_beta_coupons() returns trigger
language plpgsql security definer set search_path = pocketcare, public, extensions as $$
declare cnt int;
begin
  select count(*) into cnt from pocketcare.bug_reports where user_id = NEW.user_id;
  if cnt >= 5 and not exists (select 1 from pocketcare.coupons where user_id = NEW.user_id and reason = 'beta_5_lite') then
    insert into pocketcare.coupons (code, user_id, tier, months, reason, expires_at)
    values ('BETA-' || upper(substr(md5(random()::text || NEW.user_id::text), 1, 8)), NEW.user_id, 'lite', 1, 'beta_5_lite', now() + interval '60 days');
  end if;
  if cnt >= 25 and not exists (select 1 from pocketcare.coupons where user_id = NEW.user_id and reason = 'beta_25_pro') then
    insert into pocketcare.coupons (code, user_id, tier, months, reason, expires_at)
    values ('BETA-' || upper(substr(md5(random()::text || NEW.user_id::text), 1, 8)), NEW.user_id, 'pro', 1, 'beta_25_pro', now() + interval '60 days');
  end if;
  return NEW;
end $$;

drop trigger if exists award_beta_coupons_tr on bug_reports;
create trigger award_beta_coupons_tr after insert on bug_reports
  for each row execute function pocketcare.award_beta_coupons();

-- RLS: bug_reports owner insert+select; coupons owner read-only (issued by the
-- trigger / redeemed by the service-role edge function).
alter table bug_reports enable row level security;
create policy bug_reports_owner on bug_reports using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table coupons enable row level security;
create policy coupons_read on coupons for select using (user_id = auth.uid());
