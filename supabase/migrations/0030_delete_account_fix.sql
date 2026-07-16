-- PocketCare — fix self-serve account deletion.
--
-- Problems with 0006_delete_account_rpc.sql that this migration corrects:
--   1. The function lives in the `pocketcare` schema, and the web client calls it
--      via `supabase.schema('pocketcare').rpc(...)`. Ensure it's here + executable
--      by the `authenticated` role (incl. anonymous guests), or PostgREST 404s.
--   2. The old `orphan_records = true` branch did nothing useful and then deleted
--      auth.users anyway (which cascades everything) — so "keep data" was a lie.
--      Account deletion should mean the account AND its data are gone and the
--      email is freed. We now always fully delete.
--   3. Make the delete resilient: remove the auth.users row (every pocketcare
--      table FKs it ON DELETE CASCADE, so all rows go with it) and defensively
--      clear the owner rows first so the function succeeds even if some future
--      table lacks a cascade.
set search_path to pocketcare, public;

create or replace function pocketcare.delete_user_account(orphan_records boolean default false)
returns void
language plpgsql
security definer
set search_path = pocketcare, public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- `orphan_records` is accepted for backwards compatibility but ignored:
  -- deleting a personal-finance account always removes the account's data.

  -- Belt-and-suspenders explicit cleanup of owner-scoped tables (safe even
  -- where an ON DELETE CASCADE FK would already handle it).
  delete from pocketcare.planned_cashflow      where user_id = uid;
  delete from pocketcare.recurring_commitments where user_id = uid;
  delete from pocketcare.subscriptions         where user_id = uid;
  delete from pocketcare.loans                 where user_id = uid;
  delete from pocketcare.holdings              where user_id = uid;
  delete from pocketcare.recurring_rules       where user_id = uid;
  delete from pocketcare.transaction_templates where user_id = uid;
  delete from pocketcare.budgets               where user_id = uid;
  delete from pocketcare.goals                 where user_id = uid;
  delete from pocketcare.transactions          where user_id = uid;
  delete from pocketcare.accounts              where user_id = uid;
  delete from pocketcare.categories            where user_id = uid;
  delete from pocketcare.labels                where user_id = uid;
  delete from pocketcare.entitlements          where user_id = uid;
  delete from pocketcare.profiles              where id = uid;

  -- Finally remove the identity itself. Every remaining pocketcare table
  -- references auth.users(id) ON DELETE CASCADE, so this frees the email and
  -- sweeps up anything not explicitly deleted above.
  delete from auth.users where id = uid;
end;
$$;

-- PostgREST only exposes functions the caller's role may execute. Guests use the
-- `authenticated` role with an anonymous claim, so grant to authenticated.
revoke all on function pocketcare.delete_user_account(boolean) from public;
grant execute on function pocketcare.delete_user_account(boolean) to authenticated, service_role;
