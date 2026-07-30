-- Link a loan to the account its EMI is charged to — typically a credit card.
--
-- Why this belongs in the database and not localStorage: it now drives a MONEY
-- FIGURE. A due EMI is posted to the linked card and shows in the card's total
-- due, so a per-device link would mean the same card owing different amounts on
-- your phone and your laptop. A convenience can be local; an amount owed cannot.
--
-- Re-runnable: `if not exists` on the column and the index.

set search_path = pocketcare, public;

-- NULL = "not linked to any account" — the explicit choice offered when adding
-- a loan, for an EMI paid by standing instruction from a bank account the user
-- doesn't track here, or one they simply want to mark paid by hand.
--
-- No FOREIGN KEY, for the same reason as recurring_groups.group_id in 0046: a
-- loan row can reach the server before the account row it references when both
-- are created offline and uploaded as separate transactions. A 23503 there
-- would retry 3× and quarantine the loan — a head-of-line block of exactly the
-- kind 0040 caused and 0042 removed. A dangling id degrades gracefully instead:
-- the client treats an unknown account as "not linked".
alter table pocketcare.loans
  add column if not exists funding_account_id uuid;

create index if not exists loans_funding_account_idx
  on pocketcare.loans (user_id, funding_account_id);
