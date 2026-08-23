-- 0066_retire_orphaned_rules.sql
--
-- Retires recurring rules whose template no longer exists.
--
-- WHY THEY EXIST: the old Templates page deleted with
--   softDelete("transaction_templates", tpl.id)
-- and never touched the rule. (removeRecurring, on the Recurring page, always
-- deleted both.) So deleting a template that happened to have a recurring rule
-- attached left the rule behind, pointing at a deleted template.
--
-- WHY THEY ARE SAFE TO RETIRE: such a rule has never been able to post
-- anything. The old engine looked its template up with
--   SELECT * FROM transaction_templates WHERE id = ? AND deleted_at IS NULL
-- and did `if (!tpl) continue;`. It is a dead row that produces no
-- transactions, no reminders, and appears nowhere in the UI.
--
-- 0064 skips them (its backfill joins a live template), which is why 0065's
-- guard counted them and refused to drop. This clears that honestly — by
-- retiring rows that are already dead — rather than by loosening the guard,
-- which would also have waved through a rule that was genuinely missed.
--
-- SOFT delete, so it is reversible: to undo, set deleted_at back to null for
-- the ids listed by the inspection query below.
--
-- INSPECT FIRST if you want to see them:
--
--   select r.id, r.next_due, r.active, r.created_at,
--          t.id as template_id, t.name as template_name, t.deleted_at as template_deleted_at
--     from pocketcare.recurring_rules r
--     left join pocketcare.transaction_templates t on t.id = r.template_id
--    where r.deleted_at is null
--      and (t.id is null or t.deleted_at is not null);

set search_path = pocketcare, public;

update pocketcare.recurring_rules r
set deleted_at = now()
where r.deleted_at is null
  and not exists (
    select 1 from pocketcare.transaction_templates t
     where t.id = r.template_id and t.deleted_at is null
  );

-- Should now be 0, which is what 0065 checks:
--   select count(*) from pocketcare.recurring_rules r
--    where r.deleted_at is null
--      and not exists (select 1 from pocketcare.recurring_items i
--                      where i.source_table = 'recurring_rules'
--                        and i.source_id = r.id and i.deleted_at is null);
