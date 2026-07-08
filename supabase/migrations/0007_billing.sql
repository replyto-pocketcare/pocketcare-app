-- PocketCare — billing: 3 tiers (free/lite/pro), Razorpay subscription state,
-- and a payments audit table. Runs on top of 0001–0006. All in `pocketcare`.
set search_path to pocketcare, public;

-- 3-tier model. Keep the legacy 'premium' row for back-compat.
insert into tiers (id, label, sort) values ('lite', 'Lite', 3), ('pro', 'Pro', 4)
  on conflict (id) do nothing;

-- Razorpay / subscription state on the (already-synced) entitlements row.
alter table entitlements
  add column if not exists plan_id                  text,
  add column if not exists billing_cycle            text,   -- monthly | yearly
  add column if not exists subscription_status      text,   -- created | active | halted | cancelled | none
  add column if not exists razorpay_subscription_id text,
  add column if not exists razorpay_customer_id     text,
  add column if not exists current_period_end       timestamptz;

-- Payments/credits audit. Written by the webhook (service role); readable by owner.
create table if not exists payments (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references auth.users(id) on delete cascade,
  kind                      text not null,                 -- 'subscription' | 'credits'
  razorpay_order_id         text,
  razorpay_payment_id       text unique,                   -- idempotency key
  razorpay_subscription_id  text,
  amount                    int,                           -- paise
  currency                  text not null default 'INR',
  status                    text,
  credits_added             int not null default 0,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);
create index if not exists payments_user_idx on payments(user_id, created_at desc);

alter table payments enable row level security;
create policy payments_owner on payments using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on table payments to anon, authenticated, service_role;

-- Seed the 14-day trial WITH an AI quota (Pro-level) so trial users can actually
-- use Ask PocketCare. After the trial, gating blocks it unless they subscribe.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = pocketcare, public as $$
begin
  insert into profiles (id) values (new.id) on conflict (id) do nothing;
  insert into entitlements (user_id, tier, premium_trial_start_date, monthly_quota_total, monthly_quota_used, purchased_quota_remaining, quota_reset_date)
  values (new.id, 'free', now(), 200, 0, 0, now() + interval '14 days')
  on conflict (user_id) do update set premium_trial_start_date = coalesce(entitlements.premium_trial_start_date, now());
  if coalesce(new.is_anonymous, false) then
    insert into guest_sessions (user_id) values (new.id) on conflict (user_id) do nothing;
  end if;
  perform seed_default_categories(new.id);
  return new;
end;
$$;
