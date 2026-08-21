-- 0063_drop_planned_cashflow.sql
--
-- Drops planned_cashflow. Everything it held now lives in recurring_items
-- (income/payment, migration 0060) and holdings (savings, 0061), with 0062
-- catching any row written after those ran.
--
-- ORDER MATTERS. Apply this only AFTER the build that removes the Planned
-- Cashflow UI is deployed. While that UI is live it keeps inserting rows, so
-- dropping first would delete data written between the drop and the deploy,
-- and would break the running client mid-session.
--
-- The guard below is the real safety net: this refuses to run while any
-- unmigrated row survives, so an accountless saving (which 0061 deliberately
-- will not port, because holdings.account_id is NOT NULL) can never be
-- silently destroyed by running these out of order.

set search_path = pocketcare, public;

do $$
declare
  stranded int;
begin
  select count(*) into stranded
  from pocketcare.planned_cashflow
  where deleted_at is null and migrated_at is null;

  if stranded > 0 then
    raise exception
      'Refusing to drop planned_cashflow: % row(s) were never migrated. Run 0062, then inspect any remainder with: select id, direction, bucket, amount, name from pocketcare.planned_cashflow where deleted_at is null and migrated_at is null;',
      stranded;
  end if;
end $$;

-- holdings.planned_id keeps the id of the saving row each holding came from.
-- It is a plain text column with no foreign key, so it survives the drop as a
-- historical breadcrumb — worth keeping to trace a holding back to its origin.
drop table if exists pocketcare.planned_cashflow;
