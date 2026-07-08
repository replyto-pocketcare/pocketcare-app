-- Automatically start 14-day premium trial for new users
set search_path to pocketcare, public;

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = pocketcare, public as $$
begin
  insert into profiles (id) values (new.id) on conflict (id) do nothing;
  -- Set premium_trial_start_date to now()
  insert into entitlements (user_id, tier, premium_trial_start_date) 
  values (new.id, 'free', now()) 
  on conflict (user_id) do update set premium_trial_start_date = now() where entitlements.premium_trial_start_date is null;
  
  if coalesce(new.is_anonymous, false) then
    insert into guest_sessions (user_id) values (new.id) on conflict (user_id) do nothing;
  end if;
  
  perform seed_default_categories(new.id);
  return new;
end;
$$;
