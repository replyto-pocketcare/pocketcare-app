-- 0056_price_offers.sql
-- Promotional pricing offers.

set search_path = pocketcare, public;

create table if not exists pocketcare.price_offers (
  id          uuid primary key default gen_random_uuid(),
  tier        text not null check (tier in ('lite', 'pro')),
  cycle       text not null check (cycle in ('monthly', 'yearly')),
  price       int not null, -- discounted price in minor units
  label       text not null, -- "Founder's offer"
  starts_at   timestamptz not null default now(),
  ends_at     timestamptz,
  segment_id  uuid references pocketcare.audience_groups(id), -- null = everyone
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table pocketcare.price_offers enable row level security;

-- Client read policy: only active offers that are either global or where user is in the segment
drop policy if exists price_offers_read on pocketcare.price_offers;
create policy price_offers_read on pocketcare.price_offers for select using (
  active = true
  and (
    segment_id is null
    or exists (
      select 1 from pocketcare.audience_group_members agm
      where agm.group_id = segment_id and agm.user_id = auth.uid()
    )
  )
);

-- Admin full access via service_role is granted implicitly, but we can be explicit
grant all on table pocketcare.price_offers to anon, authenticated, service_role;
