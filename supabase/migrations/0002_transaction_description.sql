-- PocketCare — add a free-text description to transactions.
-- Idempotent so it's safe on both a fresh DB (after 0001) and an existing one.

alter table transactions add column if not exists description text;

-- Extend the full-text search index to include the description.
drop index if exists transactions_search_idx;
create index transactions_search_idx on transactions
  using gin (to_tsvector('simple', coalesce(label,'') || ' ' || coalesce(note,'') || ' ' || coalesce(description,'')));
