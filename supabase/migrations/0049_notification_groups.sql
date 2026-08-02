-- 0049_notification_groups.sql
-- Adds notification groups (for broadcasts) and rich notification fields.

set search_path = pocketcare, public;

-- 1. Extend notifications with rich fields
alter table pocketcare.notifications
  add column if not exists subtitle text,
  add column if not exists image_url text;

-- 2. Create notification_groups
create table if not exists pocketcare.notification_groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text,
  created_at  timestamptz not null default now()
);

alter table pocketcare.notification_groups enable row level security;
-- Only admins can manage groups, but anyone can read for now
create policy groups_read on pocketcare.notification_groups for select using (true);
grant all on table pocketcare.notification_groups to anon, authenticated, service_role;

-- 3. Create notification_group_members
create table if not exists pocketcare.notification_group_members (
  group_id    uuid not null references pocketcare.notification_groups(id) on delete cascade,
  user_id     uuid not null references pocketcare.profiles(id) on delete cascade,
  joined_at   timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists group_members_user_idx on pocketcare.notification_group_members(user_id);

alter table pocketcare.notification_group_members enable row level security;
create policy group_members_read on pocketcare.notification_group_members for select using (user_id = auth.uid());
create policy group_members_insert on pocketcare.notification_group_members for insert with check (user_id = auth.uid());
create policy group_members_delete on pocketcare.notification_group_members for delete using (user_id = auth.uid());
grant all on table pocketcare.notification_group_members to anon, authenticated, service_role;

-- Insert a default "All Users" group if it doesn't exist
insert into pocketcare.notification_groups (name, description) 
select 'All Users', 'General announcements for everyone'
where not exists (select 1 from pocketcare.notification_groups where name = 'All Users');
