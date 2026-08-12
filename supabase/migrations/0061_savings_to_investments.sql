-- 0061_savings_to_investments.sql
-- Savings leave Planned Cashflow and become Investments. Adds amount-based SIP
-- support to `holdings` (monthly amount + start date + monthly debit day) and
-- ports every `planned_cashflow` saving row into a holding.
--
-- Non-destructive + idempotent: originals stamped `migrated_at` (added in 0060),
-- and the port keys on `holdings.planned_id` so a re-run inserts nothing new.

set search_path = pocketcare, public;

-- Amount-based SIP fields on holdings.
alter table pocketcare.holdings add column if not exists sip_amount     integer;  -- monthly SIP amount (minor units)
alter table pocketcare.holdings add column if not exists sip_start_date text;     -- ISO date the SIP began
alter table pocketcare.holdings add column if not exists sip_day        integer;  -- day-of-month (1–28) the amount is debited to invest
alter table pocketcare.holdings add column if not exists total_invested integer;  -- running sum of contributions (minor units)

-- Port planned_cashflow savings → holdings (one holding per saving row).
-- Only savings that have an investment account are portable — holdings.account_id
-- is NOT NULL; accountless savings are left in place (nothing lost).
insert into pocketcare.holdings
  (user_id, account_id, symbol, source_account_id, name, currency, asset_class,
   sip_amount, sip_start_date, sip_day, current_value, annual_rate,
   quantity, avg_cost, off_list, planned_id, created_at, updated_at)
select p.user_id,
       p.account_id,                                                    -- investment account (uuid, not null)
       '',                                                              -- symbol (NOT NULL; blank for off-list SIP)
       p.account_id::text,                                              -- source_account_id (text column)
       p.name,
       coalesce(p.currency, ''),
       case p.bucket
         when 'sip'         then 'sip'
         when 'mutual_fund' then 'mf'
         when 'stocks'      then 'stock'
         when 'crypto'      then 'crypto'
         when 'fd'          then 'fd'
         else 'other'
       end,
       case when p.bucket = 'sip' then p.amount else null end,          -- sip_amount
       coalesce(to_char(p.created_at, 'YYYY-MM-DD'),
                to_char(p.next_due, 'YYYY-MM-DD')),                      -- sip_start_date
       extract(day from coalesce(p.next_due, p.created_at::date))::int, -- sip_day
       0,                                                               -- current_value (seed)
       case when p.expected_return is not null then p.expected_return / 100.0 else null end, -- annual_rate %
       0,                                                               -- quantity (amount SIP → no units)
       0,                                                               -- avg_cost
       1,                                                               -- off_list (unpriced by our catalog)
       p.id::text,                                                      -- planned_id (text column; idempotency key)
       now(), now()
from pocketcare.planned_cashflow p
where p.deleted_at is null
  and p.direction = 'saving'
  and p.account_id is not null
  and not exists (select 1 from pocketcare.holdings h
                  where h.planned_id = p.id::text and h.deleted_at is null);

-- Stamp the ported savings so the (future) UI removal doesn't double-count them.
update pocketcare.planned_cashflow p set migrated_at = now()
where p.migrated_at is null and p.deleted_at is null and p.direction = 'saving'
  and exists (select 1 from pocketcare.holdings h where h.planned_id = p.id::text and h.deleted_at is null);
