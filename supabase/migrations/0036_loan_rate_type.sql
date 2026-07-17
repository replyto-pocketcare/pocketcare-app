-- PocketCare — fixed vs variable interest loans.
-- `rate_type` = 'fixed' (we compute the EMI + amortization from principal/rate/
-- tenure) or 'variable' (rate changes over time — untrackable, so the user
-- enters each month's actual EMI). `emi_amounts` is a JSON map { emiNo: amountMinor }
-- of those per-month EMIs for variable loans.
set search_path to pocketcare, public;

alter table loans
  add column if not exists rate_type text not null default 'fixed',
  add column if not exists emi_amounts text;

alter table loans
  drop constraint if exists loans_rate_type_check;
alter table loans
  add constraint loans_rate_type_check check (rate_type in ('fixed', 'variable'));
