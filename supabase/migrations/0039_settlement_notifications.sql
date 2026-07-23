-- 0039_settlement_notifications.sql
-- When one party records a settlement, notify the OTHER party with a deep link
-- that pre-fills a transaction so they can record their side of the cash move —
-- an income if they received the money, an expense if they paid it.

set search_path = pocketcare, public;

create or replace function pocketcare.tg_notify_settlement()
returns trigger
language plpgsql
security definer
set search_path = pocketcare, public
as $$
declare
  recip       uuid;
  is_receiver boolean;
  oname       text;
  amt_major   text;
  typ         text;
begin
  -- Notify whichever party did NOT create the settlement (they've yet to record it).
  recip := case when NEW.created_by = NEW.from_user then NEW.to_user else NEW.from_user end;
  if recip is null or recip = NEW.created_by then
    return NEW;
  end if;

  -- from_user pays → to_user receives. So the recipient records income if they
  -- are the receiver (to_user), otherwise an expense (they paid).
  is_receiver := (recip = NEW.to_user);
  typ := case when is_receiver then 'income' else 'expense' end;
  amt_major := trim(to_char(NEW.amount / 100.0, 'FM999999990.00'));
  select coalesce(nullif(display_name, ''), email, 'Someone') into oname
    from pocketcare.profiles where id = NEW.created_by;

  if coalesce((select group_expense from pocketcare.notification_prefs
               where user_id = recip and deleted_at is null limit 1), true) then
    insert into pocketcare.notifications (user_id, kind, title, body, severity, href, dedupe_key)
    values (
      recip, 'settlement',
      case when is_receiver then 'Payment received' else 'Settlement recorded' end,
      case when is_receiver then oname || ' paid you ' else 'You paid ' || oname || ' ' end
        || NEW.currency || ' ' || amt_major || ' · tap to record it',
      'info',
      '/transactions/new?type=' || typ || '&amount=' || amt_major
        || '&desc=' || replace('Settlement with ' || oname, ' ', '%20'),
      'settle:' || NEW.id
    )
    on conflict (user_id, dedupe_key) where dedupe_key is not null and deleted_at is null do nothing;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_notify_settlement on pocketcare.settlements;
create trigger trg_notify_settlement
  after insert on pocketcare.settlements
  for each row execute function pocketcare.tg_notify_settlement();
