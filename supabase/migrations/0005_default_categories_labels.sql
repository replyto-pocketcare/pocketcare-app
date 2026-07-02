-- PocketCare — rich default categories (+ sub-categories) and starter labels.
-- Factored into seed_default_categories(uid) so both the new-user trigger and a
-- one-time backfill for existing users share the same logic. Idempotent: guarded
-- by NOT EXISTS / ON CONFLICT so re-running won't create duplicates.

create or replace function seed_default_categories(uid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  -- Top-level categories (parents + standalone).
  insert into categories (user_id, name, kind, is_system)
  select uid, v.name, v.kind::category_kind, true
  from (values
    -- expense
    ('Food & Dining','expense'),('Groceries','expense'),('Transport','expense'),
    ('Housing','expense'),('Utilities','expense'),('Health','expense'),
    ('Shopping','expense'),('Entertainment','expense'),('Education','expense'),
    ('Travel','expense'),('Personal Care','expense'),('Gifts & Donations','expense'),
    ('Fees & Charges','expense'),('Insurance','expense'),('Kids','expense'),
    ('Pets','expense'),('Subscriptions','expense'),('Taxes','expense'),
    ('Miscellaneous','expense'),
    -- income
    ('Salary','income'),('Business','income'),('Freelance','income'),
    ('Bonus','income'),('Interest','income'),('Dividends','income'),
    ('Rental Income','income'),('Refunds','income'),('Gifts Received','income'),
    ('Other Income','income')
  ) as v(name, kind)
  where not exists (
    select 1 from categories c where c.user_id = uid and c.name = v.name and c.parent_id is null
  );

  -- Sub-categories (child, parent, kind).
  insert into categories (user_id, name, kind, is_system, parent_id)
  select uid, ch.name, ch.kind::category_kind, true, p.id
  from (values
    ('Restaurants','Food & Dining','expense'),('Coffee & Snacks','Food & Dining','expense'),
    ('Takeout & Delivery','Food & Dining','expense'),
    ('Fuel','Transport','expense'),('Public Transit','Transport','expense'),
    ('Taxi & Rideshare','Transport','expense'),('Parking','Transport','expense'),
    ('Rent','Housing','expense'),('Mortgage','Housing','expense'),('Maintenance','Housing','expense'),
    ('Electricity','Utilities','expense'),('Water','Utilities','expense'),
    ('Gas','Utilities','expense'),('Internet','Utilities','expense'),('Mobile','Utilities','expense'),
    ('Doctor','Health','expense'),('Pharmacy','Health','expense'),('Fitness','Health','expense'),
    ('Clothing','Shopping','expense'),('Electronics','Shopping','expense'),('Home','Shopping','expense'),
    ('Streaming','Entertainment','expense'),('Movies','Entertainment','expense'),
    ('Games','Entertainment','expense'),('Events','Entertainment','expense'),
    ('Courses','Education','expense'),('Books','Education','expense'),('Tuition','Education','expense'),
    ('Flights','Travel','expense'),('Hotels','Travel','expense'),('Activities','Travel','expense'),
    ('Bank Fees','Fees & Charges','expense'),('Interest Charges','Fees & Charges','expense')
  ) as ch(name, parent, kind)
  join categories p on p.user_id = uid and p.name = ch.parent and p.parent_id is null
  where not exists (
    select 1 from categories c where c.user_id = uid and c.name = ch.name and c.parent_id = p.id
  );

  -- Starter labels with earthy colours.
  insert into labels (user_id, name, color)
  select uid, v.name, v.color
  from (values
    ('Essential','#5f7a52'),('Wants','#c08a3e'),('Work','#3e4a38'),
    ('Family','#b06a4f'),('Trip','#9cae8e'),('Emergency','#a8503a'),
    ('Recurring','#5f6647'),('One-off','#c98a72')
  ) as v(name, color)
  on conflict (user_id, name) do nothing;
end;
$$;

-- New-user trigger now uses the shared seeder.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id) values (new.id) on conflict (id) do nothing;
  insert into entitlements (user_id, tier) values (new.id, 'free') on conflict (user_id) do nothing;
  if coalesce(new.is_anonymous, false) then
    insert into guest_sessions (user_id) values (new.id) on conflict (user_id) do nothing;
  end if;
  perform seed_default_categories(new.id);
  return new;
end;
$$;

-- Backfill every existing user (idempotent).
do $$
declare u record;
begin
  for u in select id from auth.users loop
    perform seed_default_categories(u.id);
  end loop;
end $$;
