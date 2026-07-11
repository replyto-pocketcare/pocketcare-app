-- 0028_bug_reports_updated_at.sql
-- The client write helper (insertRow/updateRow) always sets updated_at, and the
-- client AppSchema now carries it, so bug_reports needs the column server-side
-- too or uploads fail. Every other synced table already has updated_at.
set search_path to pocketcare, public;

alter table bug_reports
  add column if not exists updated_at timestamptz not null default now();
