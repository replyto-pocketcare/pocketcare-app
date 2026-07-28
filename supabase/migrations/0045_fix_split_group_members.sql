-- Fix split_group_members: three defects that together break group creation and
-- invite acceptance. Reported as:
--   upload failed: pocketcare.split_group_members (PUT) — 42501,
--   "new row violates row-level security policy", rows: 2, on /groups
--
-- 1. SCHEMA DRIFT — `role` is written by the client (`createGroup` sends
--    role='owner'/'member') and by BOTH edge functions (split-invite,
--    split-invite-accept), and it is declared in the client AppSchema, but no
--    migration ever added it to Postgres. The table has `contact_id`/`weight`
--    instead. This is the mirror image of the CLAUDE.md rule about adding a
--    column to a synced table: here Postgres is the side that's missing it.
--
-- 2. MISSING UNIQUE CONSTRAINT — both edge functions upsert with
--    `onConflict: "group_id,user_id"`, but there has never been a unique index
--    on that pair, so those upserts raise 42P10. It also means a member could
--    be added to the same group twice.
--
-- 3. RLS TOO STRICT — `sgm_insert` (0014) only permits the group CREATOR to add
--    members. The group detail page lets any member invite people, so a
--    non-creator inviting someone is rejected with 42501. Worse, the sync
--    connector coalesces consecutive same-table inserts into ONE array upsert,
--    so the owner's own valid row is rejected alongside the invitee's — which
--    is why the reported failure covered 2 rows and left the group memberless.
--
-- Re-runnable: `if not exists` on the column/index, `drop policy if exists`
-- before each `create policy` (policies do NOT support `if not exists`).

set search_path = pocketcare, public;

-- ---------------------------------------------------------------------------
-- 1. role
-- ---------------------------------------------------------------------------
alter table pocketcare.split_group_members
  add column if not exists role text not null default 'member';

-- Backfill: whoever created the group is its owner. Safe to re-run.
update pocketcare.split_group_members m
   set role = 'owner'
  from pocketcare.split_groups g
 where g.id = m.group_id
   and g.created_by = m.user_id
   and m.role <> 'owner';

-- ---------------------------------------------------------------------------
-- 2. one membership row per (group, user)
-- ---------------------------------------------------------------------------
-- Deduplicate before adding the constraint, or index creation fails on any
-- account that already has duplicates. Keep the earliest row (it carries the
-- original created_at, and 0038's join-notification dedupes on the member id).
with ranked as (
  select id,
         row_number() over (
           partition by group_id, user_id
           order by created_at, id
         ) as rn
    from pocketcare.split_group_members
   where deleted_at is null
)
update pocketcare.split_group_members m
   set deleted_at = now()
  from ranked r
 where r.id = m.id
   and r.rn > 1;

-- Partial: a member who left (deleted_at set) can be re-added later.
create unique index if not exists split_members_group_user_uidx
  on pocketcare.split_group_members (group_id, user_id)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 3. insert policy
-- ---------------------------------------------------------------------------
-- Any of: adding yourself, being the group's creator, or already being a member
-- of that group. The last clause is what the UI has always allowed (the group
-- detail page shows Invite to every member) and what 0014 forgot.
--
-- Schema-qualified deliberately: 0011/0014 rely on the file-level `set
-- search_path` to resolve bare `is_group_creator(...)`, which CLAUDE.md calls
-- out as the thing that breaks when a policy shape is copied elsewhere.
drop policy if exists sgm_add on pocketcare.split_group_members;
drop policy if exists sgm_insert on pocketcare.split_group_members;
create policy sgm_insert on pocketcare.split_group_members for insert
  with check (
    user_id = auth.uid()
    or pocketcare.is_group_creator(group_id, auth.uid())
    or pocketcare.is_group_member(group_id, auth.uid())
  );

-- The connector sends an array upsert, so INSERT ... ON CONFLICT DO UPDATE also
-- evaluates the UPDATE policy. Re-assert 0012's shape, schema-qualified, and
-- allow an existing member to update rows in their own group (e.g. a re-add
-- flipping deleted_at back to null).
drop policy if exists sgm_leave on pocketcare.split_group_members;
drop policy if exists sgm_update on pocketcare.split_group_members;
create policy sgm_update on pocketcare.split_group_members for update
  using (
    user_id = auth.uid()
    or pocketcare.is_group_creator(group_id, auth.uid())
    or pocketcare.is_group_member(group_id, auth.uid())
  )
  with check (
    user_id = auth.uid()
    or pocketcare.is_group_creator(group_id, auth.uid())
    or pocketcare.is_group_member(group_id, auth.uid())
  );

-- ---------------------------------------------------------------------------
-- Diagnostic (observability, not enforcement — see the CLAUDE.md rule about
-- never putting cross-row constraints on a synced table).
-- ---------------------------------------------------------------------------
-- A 42501 on this table can also mean the PARENT group row never reached the
-- server (its upload was discarded or quarantined earlier), because
-- is_group_creator/is_group_member both read split_groups. This reports groups
-- the caller belongs to that have no members, and memberships whose group is
-- missing — the two shapes that produce a permanent RLS denial.
create or replace function pocketcare.audit_split_group_integrity()
returns table (issue text, group_id uuid, detail text)
language sql stable security invoker
set search_path = pocketcare, public as $$
  select 'group_without_members', g.id, coalesce(g.name, '(unnamed)')
    from pocketcare.split_groups g
   where g.deleted_at is null
     and g.created_by = auth.uid()
     and not exists (
       select 1 from pocketcare.split_group_members m
        where m.group_id = g.id and m.deleted_at is null
     )
  union all
  select 'membership_without_group', m.group_id, m.user_id::text
    from pocketcare.split_group_members m
   where m.deleted_at is null
     and m.user_id = auth.uid()
     and not exists (
       select 1 from pocketcare.split_groups g
        where g.id = m.group_id and g.deleted_at is null
     );
$$;

revoke all on function pocketcare.audit_split_group_integrity() from public;
grant execute on function pocketcare.audit_split_group_integrity() to authenticated, anon, service_role;
