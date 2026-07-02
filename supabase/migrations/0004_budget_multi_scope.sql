-- PocketCare — budgets can span multiple categories and/or labels.
-- Comma-joined lists; a transaction counts if it matches ANY selected category
-- OR ANY selected label. Empty both = overall. Idempotent.

alter table budgets add column if not exists category_ids text;
alter table budgets add column if not exists label_names text;
