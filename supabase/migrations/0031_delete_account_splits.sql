-- PocketCare — account deletion, part 2: clean up the multi-user splits ledger.
--
-- 0030 deleted owner-scoped tables + auth.users, but the shared-ledger tables
-- from 0011 reference auth.users WITHOUT `on delete cascade`:
--   split_groups.created_by, expenses.created_by, expense_participants.user_id,
--   settlements.(from_user|to_user|created_by), split_invitations.inviter
-- so `delete from auth.users` fails with e.g.
--   "violates foreign key constraint expense_participants_user_id_fkey".
--
-- This replaces the function to remove every row that references the leaving
-- user across the splits tables (in FK-safe order) before deleting the identity.
-- Self-contained: applying just this migration yields the correct final function
-- whether or not 0030 has run. `create or replace` preserves existing grants; we
-- re-grant defensively.
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

  -- `orphan_records` kept for compatibility but ignored: deleting a personal
  -- finance account always removes the account's data.

  -- ---- Multi-user splits ledger (FKs to auth.users without ON DELETE CASCADE) ----
  -- Delete leaf/reference rows first, then the user's groups (which cascade to
  -- their members/expenses/participants/settlements/invitations via group_id).
  delete from pocketcare.settlements          where from_user = uid or to_user = uid or created_by = uid;
  delete from pocketcare.expense_participants  where user_id = uid;
  delete from pocketcare.expenses              where created_by = uid;  -- cascades its participants
  delete from pocketcare.split_invitations     where inviter = uid;
  delete from pocketcare.split_group_members   where user_id = uid;     -- (also cascades from auth.users)
  delete from pocketcare.split_groups          where created_by = uid;  -- cascades members/expenses/etc.
  delete from pocketcare.expense_postings      where user_id = uid;     -- (also cascades from auth.users)
  delete from pocketcare.connections           where user_a = uid or user_b = uid;

  -- ---- Owner-scoped personal tables (belt-and-suspenders; most also cascade) ----
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

  -- Finally remove the identity itself. Everything left references
  -- auth.users(id) ON DELETE CASCADE, so this frees the email and sweeps the rest.
  delete from auth.users where id = uid;
end;
$$;

revoke all on function pocketcare.delete_user_account(boolean) from public;
grant execute on function pocketcare.delete_user_account(boolean) to authenticated, service_role;
