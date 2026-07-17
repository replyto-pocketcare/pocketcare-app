-- PocketCare — broaden holdings into a general investments model.
-- Adds crypto / fixed-deposit / SIP / other schemes alongside stocks & MFs,
-- a manual current value for assets we can't price, FD rate/maturity, the
-- savings account that funded a NEW investment, and a link to the SIP's
-- planned_cashflow saving row.
set search_path to pocketcare, public;

alter table holdings
  add column if not exists asset_class text,          -- stock | mf | crypto | fd | sip | other
  add column if not exists current_value integer,     -- user-supplied current value (minor units) for unpriced assets
  add column if not exists annual_rate real,          -- FD / scheme interest rate % p.a.
  add column if not exists maturity_date text,        -- FD maturity date (ISO)
  add column if not exists source_account_id text,    -- savings/bank account that funded a NEW investment (null = tracking existing)
  add column if not exists planned_id text;           -- linked planned_cashflow saving row (for SIPs)

-- Backfill asset_class for existing rows from the older instrument_type.
update holdings
  set asset_class = coalesce(asset_class, instrument_type, 'stock')
  where asset_class is null;
