-- PocketCare — segment feedback into bugs vs suggestions.
-- Only bugs count toward the reward-coupon milestones.
set search_path to pocketcare, public;

alter table bug_reports add column if not exists kind text not null default 'bug' check (kind in ('bug', 'suggestion'));
-- suggestions don't carry a severity
alter table bug_reports alter column severity drop not null;

-- Recount milestones on bug reports only.
create or replace function pocketcare.award_beta_coupons() returns trigger
language plpgsql security definer set search_path = pocketcare, public, extensions as $$
declare cnt int;
begin
  if NEW.kind <> 'bug' then return NEW; end if;
  select count(*) into cnt from pocketcare.bug_reports where user_id = NEW.user_id and kind = 'bug';
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
