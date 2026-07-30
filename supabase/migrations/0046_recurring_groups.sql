-- Recurring groups: user-defined buckets for recurring income / payments /
-- savings, so the Recurring page can be read as "Subscriptions ₹1,240 · 4 items"
-- instead of one flat list. Plan: docs/plans/ui-redesign-2026-07.md §3.
--
-- Re-runnable: `if not exists` on the table/column/index, `drop policy if
-- exists` before each `create policy` (policies do NOT support `if not exists`).

set search_path = pocketcare, public;

create table if not exists pocketcare.recurring_groups (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  -- Which section the group belongs to. Mirrors the template `type` mapping in
  -- apps/web/src/cashflow/recurring.ts: income → income, transfer → saving,
  -- everything else → payment.
  direction  text not null check (direction in ('income', 'payment', 'saving')),
  icon       text,
  color      text,
  sort       int  not null default 0,
  -- Seeded defaults. Distinguished so seeding can be idempotent ("has this user
  -- ever been seeded?") without preventing the user from renaming or deleting
  -- them afterwards.
  is_system  boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists recurring_groups_user_idx
  on pocketcare.recurring_groups (user_id, direction);

-- One group name per direction per user. Partial, so a deleted name is reusable.
create unique index if not exists recurring_groups_user_name_uidx
  on pocketcare.recurring_groups (user_id, direction, lower(name))
  where deleted_at is null;

alter table pocketcare.recurring_groups enable row level security;
drop policy if exists recurring_groups_owner on pocketcare.recurring_groups;
create policy recurring_groups_owner on pocketcare.recurring_groups
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

grant all on table pocketcare.recurring_groups to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- The link from a recurring item to its group.
-- ---------------------------------------------------------------------------
-- NULLABLE, and deliberately WITHOUT a foreign key. Both are load-bearing:
--
--   * NULL is required because existing recurring items predate this column and
--     there is no correct group to invent for them. The client triages them
--     ("N recurring items need a group") instead of silently bucketing them.
--
--   * NO FK because creating an item in a brand-new group writes TWO rows, and
--     PowerSync uploads them in two SEPARATE HTTP transactions. A template row
--     landing before its group row would raise 23503, retry 3×, then quarantine
--     — the exact head-of-line block that migration 0040 caused and 0042 had to
--     remove. The connector does preserve order, so it would *usually* work;
--     "usually" is not a property to want on a write path.
--
-- The invariant (every recurring item has a group) is enforced on the client,
-- where the whole set is known at once, and made observable here by
-- audit_ungrouped_recurring() below.
alter table pocketcare.transaction_templates
  add column if not exists group_id uuid;

create index if not exists transaction_templates_group_idx
  on pocketcare.transaction_templates (user_id, group_id);

-- ---------------------------------------------------------------------------
-- Observability, not enforcement (see the CLAUDE.md rule about cross-row
-- constraints on synced tables). Follows the audit_expense_item_sums precedent.
-- ---------------------------------------------------------------------------
-- Reports recurring items belonging to the caller that have no group, and items
-- pointing at a group that no longer exists. Both are states the UI is supposed
-- to make impossible; if this returns rows, the client-side guard has a hole.
create or replace function pocketcare.audit_ungrouped_recurring()
returns table (issue text, template_id uuid, template_name text)
language sql stable security invoker
set search_path = pocketcare, public as $$
  select 'no_group', t.id, t.name
    from pocketcare.transaction_templates t
    join pocketcare.recurring_rules r on r.template_id = t.id and r.deleted_at is null
   where t.deleted_at is null
     and t.user_id = auth.uid()
     and t.group_id is null
  union all
  select 'missing_group', t.id, t.name
    from pocketcare.transaction_templates t
    join pocketcare.recurring_rules r on r.template_id = t.id and r.deleted_at is null
   where t.deleted_at is null
     and t.user_id = auth.uid()
     and t.group_id is not null
     and not exists (
       select 1 from pocketcare.recurring_groups g
        where g.id = t.group_id and g.deleted_at is null
     );
$$;

revoke all on function pocketcare.audit_ungrouped_recurring() from public;
grant execute on function pocketcare.audit_ungrouped_recurring() to authenticated, anon, service_role;
