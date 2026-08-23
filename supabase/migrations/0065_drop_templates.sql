-- 0065_drop_templates.sql
--
-- Drops transaction_templates and recurring_rules. Recurring commitments now
-- live entirely in recurring_items (0060 created it, 0064 gave it the posting
-- fields and caught up every row), and the Templates feature is removed.
--
-- ORDER MATTERS, exactly as with 0063: apply this only AFTER the build that
-- removes the Templates UI and moves recurring onto recurring_items is
-- deployed. Until then the running client still writes template+rule pairs,
-- and dropping first would delete commitments created in between.
--
-- The guard refuses to run while any live recurring rule has no counterpart in
-- recurring_items, so a commitment can never be destroyed by running these out
-- of order.

set search_path = pocketcare, public;

do $$
declare
  stranded int;
begin
  select count(*) into stranded
  from pocketcare.recurring_rules r
  where r.deleted_at is null
    and not exists (
      select 1 from pocketcare.recurring_items i
      where i.source_table = 'recurring_rules' and i.source_id = r.id and i.deleted_at is null
    );

  if stranded > 0 then
    raise exception
      'Refusing to drop: % recurring rule(s) have no recurring_items counterpart. Run 0064 first, then re-check.',
      stranded;
  end if;
end $$;

-- recurring_rules first: it references templates.
drop table if exists pocketcare.recurring_rules;
drop table if exists pocketcare.transaction_templates;
