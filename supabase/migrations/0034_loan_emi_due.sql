-- PocketCare — EMI due-day + auto-mark-paid policy for loans.
-- `emi_due_day` (1–31) is the day of the month each EMI is due; combined with
-- `start_date` it derives every EMI's due date (see @pocketcare/finance
-- emiDueDate). `auto_mark_paid` (0/1): when on, EMIs whose due date has passed
-- are treated as paid automatically (derived at read time — no rows written).
set search_path to pocketcare, public;

alter table loans
  add column if not exists emi_due_day integer,
  add column if not exists auto_mark_paid integer not null default 0;

alter table loans
  drop constraint if exists loans_emi_due_day_range;
alter table loans
  add constraint loans_emi_due_day_range
  check (emi_due_day is null or (emi_due_day between 1 and 31));
