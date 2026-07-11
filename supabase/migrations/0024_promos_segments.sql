-- PocketCare — shared promo codes + audience segmentation.
-- Per-user reward coupons live in `coupons` (0022). This adds SHARED promo codes
-- (one code, many users, once each) for testing/campaigns, plus optional user
-- traits + named segments so campaigns/coupons can be targeted.
set search_path to pocketcare, public;

-- Shared promo codes (e.g. BETA_TESTER). Redeemed via the redeem-coupon fn.
create table if not exists promo_codes (
  code            text primary key,
  tier            text not null check (tier in ('lite', 'pro')),
  months          int not null default 1,           -- comp length granted from the apply date
  active          boolean not null default true,
  starts_at       timestamptz,
  ends_at         timestamptz,                       -- availability window (null = open)
  max_redemptions int,                               -- null = unlimited
  redeemed_count  int not null default 0,
  segment         text,                              -- optional: intended audience (informational)
  note            text,
  created_at      timestamptz not null default now()
);

-- One redemption per user per promo.
create table if not exists promo_redemptions (
  id            uuid primary key default gen_random_uuid(),
  code          text not null references promo_codes(code) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  applied_until timestamptz,
  redeemed_at   timestamptz not null default now(),
  unique (code, user_id)
);

-- Optional self-declared traits, used only for tailored offers/segments.
alter table profiles add column if not exists gender  text;
alter table profiles add column if not exists country text;

-- Named audience segments (admin-managed). `rule` is a small JSON of trait filters,
-- e.g. {"gender":"female","country":"IN"}.
create table if not exists segments (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text,
  rule        jsonb not null default '{}',
  created_at  timestamptz not null default now()
);

-- Seed the beta testing promo: 1 month of Pro from whenever it's applied.
insert into promo_codes (code, tier, months, active, note)
values ('BETA_TESTER', 'pro', 1, true, 'Beta tester — 1 month Pro from the date it is applied')
on conflict (code) do nothing;

-- RLS: promo_codes + segments are service-role only (no client policy).
-- promo_redemptions: owner can read their own.
alter table promo_codes enable row level security;
alter table segments enable row level security;
alter table promo_redemptions enable row level security;
create policy promo_redemptions_read on promo_redemptions for select using (user_id = auth.uid());
