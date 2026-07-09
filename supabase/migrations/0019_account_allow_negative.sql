-- PocketCare — per-account overdraft policy. When false, a transaction that
-- would take the account below zero is blocked. Credit cards are liabilities
-- that carry a negative (owed) balance by design, so they default to allowed.
set search_path to pocketcare, public;

alter table pocketcare.accounts add column if not exists allow_negative boolean not null default false;
update pocketcare.accounts set allow_negative = true where type = 'credit_card';
