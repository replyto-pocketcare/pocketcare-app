-- 0026_admin_view.sql
-- PostgREST won't expose the pocketcare_admin schema on this project, so we
-- surface the admins table through the already-exposed `pocketcare` schema via
-- a security_invoker view. The base table stays in pocketcare_admin; RLS on the
-- base table (users read only their own row) still applies because the view
-- runs with the caller's privileges.
set search_path to pocketcare, public;

create or replace view pocketcare.admins
  with (security_invoker = true) as
  select id, user_id, email, created_at
  from pocketcare_admin.admins;

-- Callers query the view; RLS is enforced on the underlying table.
grant select on pocketcare.admins to authenticated;
