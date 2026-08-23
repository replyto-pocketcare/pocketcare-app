-- 0067 — remove recurring groups.
--
-- Groups were the buckets behind the old /recurring sections (0046). The
-- redesigned screen organises recurring items by DIRECTION and CATEGORY, so
-- the extra taxonomy has no reader left: nothing in the app queries
-- recurring_groups, and nothing writes recurring_items.group_id.
--
-- Losing the grouping loses no money data. A group carried a name, an icon and
-- a sort order — presentation only. Every recurring item keeps its amount,
-- schedule, account and category, which is everything the posting engine uses.
--
-- Unlike 0063/0065 there is no guard block here, deliberately: there is nothing
-- to migrate first. A guard would only be theatre.

begin;

-- 1) The audit function from 0046 reads transaction_templates, which 0065
--    dropped, and recurring_groups, which this migration drops. It has been
--    dead since 0065; remove it rather than leave a function that errors when
--    called.
drop function if exists pocketcare.audit_ungrouped_recurring();

-- 2) The pointer, before the target — so nothing is briefly dangling.
alter table if exists pocketcare.recurring_items
  drop column if exists group_id;

-- 3) The table.
drop table if exists pocketcare.recurring_groups;

commit;

-- After deploying, remove the recurring_groups line from
-- packages/db/sync-streams.yaml and re-upload the sync rules — the client
-- schema no longer declares that table, and a sync rule for a dropped table
-- will error on the connector.
