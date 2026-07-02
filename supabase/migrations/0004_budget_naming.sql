-- PocketCare — named/tagged budgets with an optional custom timeframe.
-- A budget can now have a friendly name (e.g. "Japan Trip"), be scoped to a
-- category or label (scope/scope_ref already exist), and use either a recurring
-- period OR a fixed start/end date range.

alter table budgets add column name text;
alter table budgets add column start_date date;
alter table budgets add column end_date date;
