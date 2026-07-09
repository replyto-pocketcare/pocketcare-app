-- Fix RLS policy on split_group_members so that the group creator can upsert/update members.
-- This is necessary because PowerSync uses UPSERT for insertions, which requires UPDATE privileges
-- on the rows being inserted if a conflict occurs, and PostgREST evaluates this policy.

set search_path = pocketcare, public;

drop policy if exists sgm_leave on pocketcare.split_group_members;

-- Allow a user to update their own row (to leave the group) 
-- OR allow the group creator to update any member's row (to add them via UPSERT, or kick them).
create policy sgm_update on pocketcare.split_group_members for update
  using (user_id = auth.uid() or is_group_creator(group_id, auth.uid()))
  with check (user_id = auth.uid() or is_group_creator(group_id, auth.uid()));
