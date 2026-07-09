set search_path = pocketcare, public;

-- 1. Fix split_group_members SELECT permissions
-- A newly inserted row is invisible to STABLE functions during the UPSERT's RETURNING clause.
-- We MUST allow the user to select their own row directly without relying on is_group_member.
drop policy if exists sgm_select on pocketcare.split_group_members;
create policy sgm_select on pocketcare.split_group_members for select 
  using (user_id = auth.uid() or is_group_member(group_id, auth.uid()));

-- 2. Fix split_group_members UPSERT permissions (UPSERT evaluates UPDATE policy)
drop policy if exists sgm_leave on pocketcare.split_group_members;
drop policy if exists sgm_update on pocketcare.split_group_members;
create policy sgm_update on pocketcare.split_group_members for update
  using (user_id = auth.uid() or is_group_creator(group_id, auth.uid()))
  with check (user_id = auth.uid() or is_group_creator(group_id, auth.uid()));

-- 3. Fix split_groups UPSERT permissions (for a brand new group)
drop policy if exists sg_update on pocketcare.split_groups;
create policy sg_update on pocketcare.split_groups for update 
  using (is_group_member(id, auth.uid()) or created_by = auth.uid()) 
  with check (is_group_member(id, auth.uid()) or created_by = auth.uid());

-- 4. Relax split_group_members INSERT permissions (bypasses strict connection check)
drop policy if exists sgm_add on pocketcare.split_group_members;
drop policy if exists sgm_insert on pocketcare.split_group_members;
create policy sgm_insert on pocketcare.split_group_members for insert
  with check (is_group_creator(group_id, auth.uid()) or user_id = auth.uid());
