-- PocketCare — loans EMI schedule, demat investments, credit-card cycle.
-- Adds columns (all synced via user_data / reference_data streams; no new tables).
set search_path to pocketcare, public;

-- Loans: track how many EMIs are already paid (to derive next EMI + remaining).
alter table loans
  add column if not exists emis_paid int not null default 0;

-- Holdings: mutual-fund units reuse `quantity`; new columns distinguish
-- instrument type and off-catalog (untracked) holdings.
alter table holdings
  add column if not exists instrument_type text,          -- 'stock' | 'mf'
  add column if not exists off_list int not null default 0, -- 1 = not in our fetched catalog
  add column if not exists name text;                      -- display name for off-list holdings

-- Credit cards: store the current statement's owed amount and when it's due,
-- so a card created after the statement day shows 0 due this cycle and rolls
-- the amount to the next due date.
alter table credit_card_details
  add column if not exists pending_due int,
  add column if not exists due_on date;

-- New 'demat' account type: a single account holding an invested amount that is
-- deployed across stocks and mutual funds (holdings) in the Investments section.
insert into account_types (id, label, sort) values ('demat','Demat',7)
  on conflict (id) do nothing;
