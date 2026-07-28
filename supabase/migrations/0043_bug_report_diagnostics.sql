-- 0043_bug_report_diagnostics.sql
--
-- Attach a redacted device log to bug reports.
--
-- On a laptop you can ask someone to open the console. On a phone you can't, so
-- a failure that prints a perfectly clear PostgREST error is invisible to
-- everyone — the user reports "syncing isn't working" and that is all anyone
-- knows. This column carries the on-device support log along with the report,
-- so the diagnosis arrives without the user having to do anything.
--
-- PRIVACY: the log is scrubbed on the client before it is ever stored
-- (packages/core/diagnostics — amounts, descriptions, merchants, emails and
-- payment handles are removed; table names, operations, error codes and row ids
-- are kept). Nothing unredacted reaches this column.

set search_path = pocketcare, public;

alter table pocketcare.bug_reports
  add column if not exists diagnostics text;

comment on column pocketcare.bug_reports.diagnostics is
  'Redacted on-device support log captured at report time. Never contains amounts, descriptions or contact details.';
