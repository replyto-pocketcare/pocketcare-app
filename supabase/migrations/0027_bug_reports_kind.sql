-- 0027_bug_reports_kind.sql
-- The feedback modal sends `kind` ('bug' | 'suggestion') and, for suggestions,
-- a null severity. The bug_reports table had no `kind` column and severity was
-- NOT NULL, so suggestion reports failed to sync and the admin Feedback page had
-- no kind to filter on. Add the column and relax severity.
set search_path to pocketcare, public;

alter table bug_reports
  add column if not exists kind text not null default 'bug';

-- Constrain to the two supported values (idempotent).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'bug_reports_kind_chk'
  ) then
    alter table bug_reports
      add constraint bug_reports_kind_chk check (kind in ('bug','suggestion'));
  end if;
end $$;

-- Suggestions have no severity.
alter table bug_reports alter column severity drop not null;
