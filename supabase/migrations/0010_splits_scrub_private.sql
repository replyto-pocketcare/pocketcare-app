-- PocketCare — keep the SHARED split-fact tables free of any private data, so
-- they can be shared with group members without leaking personal details.
--   * shared_expense_payers.account_id — which bank account YOU paid from is
--     private; it already lives on your own transactions row (linked via the
--     private expense_postings table). The shared payer row only needs
--     who paid + how much.
--   * shared_expenses.category_id — a reference to YOUR private category
--     taxonomy; the category lives on your private posting instead.
set search_path to pocketcare, public;

alter table pocketcare.shared_expense_payers drop column if exists account_id;
alter table pocketcare.shared_expenses      drop column if exists category_id;
