-- Fix RLS policy on split_groups so that the group creator can upsert it.
-- PowerSync uses UPSERT for insertions. The UPSERT evaluates the UPDATE policy.
-- For a brand new group, the user is not yet in split_group_members (that insert happens next).
-- Thus, is_group_member() returns false, and the UPSERT fails.
-- We must explicitly allow the created_by user to update the group.

set search_path = pocketcare, public;

drop policy if exists sg_update on pocketcare.split_groups;

create policy sg_update on pocketcare.split_groups for update 
  using (is_group_member(id, auth.uid()) or created_by = auth.uid()) 
  with check (is_group_member(id, auth.uid()) or created_by = auth.uid());
