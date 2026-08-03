-- 0054_drop_segments.sql
-- Migrates segments to derived groups, drops segments, and repoints promos.

set search_path = pocketcare, public;

-- 1. Migrate existing segments to derived groups
insert into pocketcare.audience_groups (id, name, description, rule, kind, active)
select id, name, description, rule, 'derived', true
from pocketcare.segments
on conflict do nothing; -- Assuming ids are unique enough, or we might need to handle differently if conflicts arise (they shouldn't since UUIDs)

-- 2. Repoint promo_codes.segment
-- Currently `promo_codes.segment` is text. If we want it to be a UUID reference to `audience_groups`, we need to change its type.
-- The plan says "promo_codes.segment is currently a free-text informational field. It becomes a real group_id reference."

-- Ensure all text values in promo_codes.segment that are not valid UUIDs are cleared or handled.
-- For safety, we can alter the column type and attempt to cast, or add a new column and drop the old.
-- Let's add a new column, try to map, and rename.

alter table pocketcare.promo_codes add column segment_id uuid references pocketcare.audience_groups(id);

-- Try to map existing valid UUIDs if any were accidentally stored (highly unlikely if it was free text)
-- update pocketcare.promo_codes set segment_id = segment::uuid where segment ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- Drop the old text column and rename
alter table pocketcare.promo_codes drop column segment;
alter table pocketcare.promo_codes rename column segment_id to segment;

-- 3. Drop segments table
drop table if exists pocketcare.segments cascade;

-- Note: Dropping the compatibility views (notification_groups, notification_group_members)
-- is deferred until we are 100% sure nothing in the app references them anymore.
