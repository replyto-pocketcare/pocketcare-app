-- 0064_recurring_items_selfsufficient.sql
--
-- Finishes what 0060 started: makes recurring_items able to stand on its own,
-- so recurring commitments stop being stored as a transaction_templates +
-- recurring_rules pair.
--
-- 0060 created recurring_items and backfilled it, but the app kept READING and
-- WRITING the old pair — so recurring_items has been frozen at its 0060
-- snapshot, and every commitment created since exists only as a template+rule.
-- Two things are therefore needed before the app can switch over:
--
--   1. The columns the posting engine actually uses. recurring_items was
--      designed for tracking (name/amount/frequency/next_due) and is missing
--      everything materializeTemplate reads to post a transaction: the transfer
--      destination, description/note, payment method, labels, and the split
--      group. Without them, switching over would silently drop those fields
--      from every auto-posted transaction.
--   2. A re-run of the backfill, so items created after 0060 are present.
--
-- Non-destructive and idempotent, like its predecessors: columns are added
-- IF NOT EXISTS, the insert keeps 0060's uniqueness guard, and the field
-- backfill only fills columns that are still null, so it can never overwrite a
-- value the app has since written.

set search_path = pocketcare, public;

-- ---------------------------------------------------------------------------
-- 1. Fields the posting engine needs (mirrors transaction_templates).
-- ---------------------------------------------------------------------------
alter table pocketcare.recurring_items add column if not exists to_account_id  uuid;
alter table pocketcare.recurring_items add column if not exists description    text;
alter table pocketcare.recurring_items add column if not exists note           text;
alter table pocketcare.recurring_items add column if not exists payment_method text;
alter table pocketcare.recurring_items add column if not exists labels         text;
alter table pocketcare.recurring_items add column if not exists split_group_id uuid;
alter table pocketcare.recurring_items add column if not exists split_mode     text;
-- DATE, not text: recurring_rules.last_generated is a date, and the sibling
-- next_due on this very table is already date. Declaring it text made the
-- backfill's coalesce(text, date) unmatchable. (The client schema still maps it
-- to a string — that is how next_due already works.)
alter table pocketcare.recurring_items add column if not exists last_generated date;

-- An earlier run of this migration added the column as text before the type was
-- corrected, and `add column if not exists` will not fix that. Normalise it.
do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'pocketcare' and table_name = 'recurring_items'
       and column_name = 'last_generated' and data_type = 'text'
  ) then
    alter table pocketcare.recurring_items
      alter column last_generated type date using nullif(last_generated, '')::date;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1b. Allow the 'saving' direction.
--
-- 0060 narrowed direction to income|expense on the assumption that savings had
-- all moved to Investments. That is true of the planned_cashflow saving ROWS
-- (0061 ported them to holdings), but NOT of SIPs: a SIP still needs a monthly
-- transfer to actually post (debit account -> investment account), and that
-- lived as a transfer-typed template + rule, which 0060 skipped entirely.
--
-- So transfer-typed recurring rules have been orphaned from recurring_items
-- since 0060. They need a home here, or removing transaction_templates would
-- stop every SIP from posting.
-- ---------------------------------------------------------------------------
alter table pocketcare.recurring_items
  drop constraint if exists recurring_items_direction_check;
alter table pocketcare.recurring_items
  add constraint recurring_items_direction_check
  check (direction in ('income', 'expense', 'saving'));

-- ---------------------------------------------------------------------------
-- 2. Catch up anything created since 0060 (same guard, so re-running is a
--    no-op for rows already present).
-- ---------------------------------------------------------------------------
insert into pocketcare.recurring_items
  (user_id, direction, group_id, name, amount, currency, frequency, interval_count,
   next_due, account_id, category_id, auto_post, active, alert_time_utc,
   to_account_id, description, note, payment_method, labels, split_group_id, split_mode,
   last_generated, source_table, source_id)
select t.user_id,
       case when t.type = 'income' then 'income'
            when t.type = 'transfer' then 'saving'
            else 'expense' end,
       t.group_id, t.name, coalesce(t.amount, 0), t.currency, r.frequency, r.interval_count,
       r.next_due, t.account_id, t.category_id, r.auto_post, r.active, r.alert_time_utc,
       t.to_account_id, t.description, t.note, t.payment_method, t.labels, t.split_group_id, t.split_mode,
       r.last_generated, 'recurring_rules', r.id
from pocketcare.recurring_rules r
join pocketcare.transaction_templates t on t.id = r.template_id
where r.deleted_at is null and t.deleted_at is null
on conflict (user_id, source_table, source_id)
  where source_id is not null and deleted_at is null do nothing;

-- ---------------------------------------------------------------------------
-- 3. Fill the new columns on rows 0060 already created (it could not populate
--    columns that did not exist yet). Only touches values still null, so a
--    later edit made in the app is never clobbered.
-- ---------------------------------------------------------------------------
update pocketcare.recurring_items i
set to_account_id  = coalesce(i.to_account_id,  t.to_account_id),
    description    = coalesce(i.description,    t.description),
    note           = coalesce(i.note,           t.note),
    payment_method = coalesce(i.payment_method, t.payment_method),
    labels         = coalesce(i.labels,         t.labels),
    split_group_id = coalesce(i.split_group_id, t.split_group_id),
    split_mode     = coalesce(i.split_mode,     t.split_mode),
    last_generated = coalesce(i.last_generated, r.last_generated)
from pocketcare.recurring_rules r
join pocketcare.transaction_templates t on t.id = r.template_id
where i.source_table = 'recurring_rules'
  and i.source_id = r.id
  and i.deleted_at is null;

update pocketcare.recurring_rules r set migrated_at = now()
where r.migrated_at is null and r.deleted_at is null
  and exists (select 1 from pocketcare.recurring_items i
              where i.source_table = 'recurring_rules' and i.source_id = r.id and i.deleted_at is null);

-- Verify before dropping anything (0065):
--   select count(*) from pocketcare.recurring_rules r
--    where r.deleted_at is null and r.migrated_at is null;   -- expect 0
