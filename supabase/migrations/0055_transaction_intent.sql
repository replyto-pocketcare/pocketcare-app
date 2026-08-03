-- 0055_transaction_intent.sql
-- Adds the `intent` column to transactions for Need vs Greed tagging.

set search_path = pocketcare, public;

alter table pocketcare.transactions
  add column if not exists intent text check (intent in ('need', 'greed'));
