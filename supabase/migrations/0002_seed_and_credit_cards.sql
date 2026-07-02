-- PocketCare — Phase 2 migration
-- 1) Give credit_card_details a surrogate text/uuid id (PowerSync needs an `id`
--    column on every synced table); keep account_id as a unique FK.
-- 2) Seed defaults for every new user (guest or registered) via an auth trigger:
--    profile, free entitlement, default categories, and a 3-day guest session
--    for anonymous users. Because streams sync these down, the client gets its
--    starter categories automatically and offline.

-- ---------- 1. credit_card_details surrogate id ----------
alter table credit_card_details drop constraint credit_card_details_pkey;
alter table credit_card_details add column id uuid primary key default gen_random_uuid();
alter table credit_card_details add constraint credit_card_details_account_unique unique (account_id);

-- ---------- 2. New-user bootstrap ----------
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  is_anon boolean := coalesce(new.is_anonymous, false);
begin
  insert into profiles (id) values (new.id) on conflict (id) do nothing;
  insert into entitlements (user_id, tier) values (new.id, 'free') on conflict (user_id) do nothing;

  if is_anon then
    insert into guest_sessions (user_id) values (new.id) on conflict (user_id) do nothing;
  end if;

  -- Default expense categories
  insert into categories (user_id, name, kind, is_system)
  select new.id, name, 'expense', true from (values
    ('Food & Dining'),('Groceries'),('Transport'),('Housing'),('Utilities'),
    ('Health'),('Shopping'),('Entertainment'),('Education'),('Travel'),
    ('Personal Care'),('Gifts & Donations'),('Fees & Charges'),('Other')
  ) as v(name);

  -- Default income categories
  insert into categories (user_id, name, kind, is_system)
  select new.id, name, 'income', true from (values
    ('Salary'),('Business'),('Interest'),('Dividends'),('Refunds'),('Other')
  ) as v(name);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
