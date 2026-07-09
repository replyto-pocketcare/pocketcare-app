-- Relax the insert policy for split_group_members.
-- The previous policy required the inserted user to be explicitly connected to the creator.
-- If the connections table hasn't synced or the check fails, the insert fails.
-- We'll allow the group creator to add anyone to their group.

set search_path = pocketcare, public;

drop policy if exists sgm_add on pocketcare.split_group_members;

create policy sgm_insert on pocketcare.split_group_members for insert
  with check (
    is_group_creator(group_id, auth.uid()) 
    or 
    -- Alternatively, if they are just adding themselves
    user_id = auth.uid()
  );
