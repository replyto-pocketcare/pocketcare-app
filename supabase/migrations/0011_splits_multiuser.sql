-- PocketCare — Multi-user splits (Splitwise-style shared ledger).
-- Replaces the Phase-1/2 contact-based split schema. Everyone is a registered
-- user; one shared copy of each row, visible via group membership (RLS + sync
-- buckets). See docs/splits-multiuser-spec.md.
-- NOTE: drops existing split data (agreed — Phase 1/2 was test data).
set search_path to pocketcare, public;

-- ---- Drop the old contact-based split tables ----
drop table if exists pocketcare.expense_postings       cascade;
drop table if exists pocketcare.settlements            cascade;
drop table if exists pocketcare.shared_expense_payers  cascade;
drop table if exists pocketcare.shared_expense_shares  cascade;
drop table if exists pocketcare.shared_expenses        cascade;
drop table if exists pocketcare.split_group_members    cascade;
drop table if exists pocketcare.split_groups           cascade;
drop table if exists pocketcare.contacts               cascade;

-- ---- Identity: expose a display name + email for showing co-members ----
alter table pocketcare.profiles add column if not exists display_name text;
alter table pocketcare.profiles add column if not exists email        text;

-- ---- New shared-ledger schema ----
create table pocketcare.split_groups (
  id           uuid primary key default gen_random_uuid(),
  created_by   uuid not null references auth.users(id),
  name         text not null,
  kind         text not null default 'group',    -- 'group' | 'trip'
  is_direct    int  not null default 0,           -- 1 = auto-created 2-person 1:1 container
  start_date   date,
  end_date     date,
  auto_split   int  not null default 0,
  default_mode text not null default 'equal',
  currency     text not null default 'INR',
  archived     int  not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

create table pocketcare.split_group_members (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references pocketcare.split_groups(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null default 'member',      -- 'owner' | 'member'
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (group_id, user_id)
);

create table pocketcare.expenses (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references pocketcare.split_groups(id) on delete cascade,
  created_by  uuid not null references auth.users(id),
  description text,
  amount      int  not null,                      -- minor units, total
  currency    text not null,
  occurred_at timestamptz not null,
  split_mode  text not null default 'equal',
  version     int  not null default 1,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table pocketcare.expense_participants (
  id           uuid primary key default gen_random_uuid(),
  expense_id   uuid not null references pocketcare.expenses(id) on delete cascade,
  group_id     uuid not null references pocketcare.split_groups(id) on delete cascade, -- denormalized for bucketing
  user_id      uuid not null references auth.users(id),
  paid_amount  int  not null default 0,
  share_amount int  not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (expense_id, user_id)
);

create table pocketcare.settlements (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references pocketcare.split_groups(id) on delete cascade, -- denormalized
  from_user  uuid not null references auth.users(id),
  to_user    uuid not null references auth.users(id),
  amount     int  not null,
  currency   text not null,
  method     text,
  note       text,
  settled_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- PRIVATE per-user projection into personal budget (never shared)
create table pocketcare.expense_postings (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  expense_id     uuid,
  settlement_id  uuid,
  transaction_id uuid not null,
  role           text not null,                   -- own_share | lend | borrow | settlement
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

create table pocketcare.split_invitations (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references pocketcare.split_groups(id) on delete cascade,
  inviter       uuid not null references auth.users(id),
  invitee_email text,
  token         text not null unique,
  status        text not null default 'pending',  -- pending | accepted | revoked | expired
  accepted_by   uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  expires_at    timestamptz
);

create table pocketcare.connections (
  id         uuid primary key default gen_random_uuid(),
  user_a     uuid not null references auth.users(id) on delete cascade,
  user_b     uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (user_a < user_b),
  unique (user_a, user_b)
);

create index expenses_group_idx      on pocketcare.expenses(group_id, occurred_at desc);
create index eparticipants_group_idx on pocketcare.expense_participants(group_id);
create index eparticipants_user_idx  on pocketcare.expense_participants(user_id);
create index settlements_group_idx   on pocketcare.settlements(group_id);
create index members_user_idx        on pocketcare.split_group_members(user_id);
create index members_group_idx       on pocketcare.split_group_members(group_id);
create index postings_user_idx       on pocketcare.expense_postings(user_id);
create index invitations_token_idx   on pocketcare.split_invitations(token);
create index connections_a_idx       on pocketcare.connections(user_a);
create index connections_b_idx       on pocketcare.connections(user_b);

-- ---- Membership helpers (SECURITY DEFINER → no RLS recursion) ----
create or replace function pocketcare.is_group_member(g uuid, u uuid)
returns boolean language sql stable security definer
set search_path = pocketcare, public as $$
  select exists (select 1 from pocketcare.split_group_members m
                 where m.group_id = g and m.user_id = u and m.deleted_at is null);
$$;

create or replace function pocketcare.can_see_user(target uuid, me uuid)
returns boolean language sql stable security definer
set search_path = pocketcare, public as $$
  select target = me
      or exists (select 1 from pocketcare.split_group_members m1
                   join pocketcare.split_group_members m2 on m1.group_id = m2.group_id
                  where m1.user_id = target and m2.user_id = me
                    and m1.deleted_at is null and m2.deleted_at is null)
      or exists (select 1 from pocketcare.connections c
                  where c.deleted_at is null
                    and ((c.user_a = target and c.user_b = me) or (c.user_a = me and c.user_b = target)));
$$;

create or replace function pocketcare.is_group_creator(g uuid, u uuid)
returns boolean language sql stable security definer
set search_path = pocketcare, public as $$
  select exists (select 1 from pocketcare.split_groups gr
                 where gr.id = g and gr.created_by = u and gr.deleted_at is null);
$$;

create or replace function pocketcare.is_connected(a uuid, b uuid)
returns boolean language sql stable security definer
set search_path = pocketcare, public as $$
  select exists (select 1 from pocketcare.connections c
                  where c.deleted_at is null
                    and ((c.user_a = a and c.user_b = b) or (c.user_a = b and c.user_b = a)));
$$;

revoke all on function pocketcare.is_group_member(uuid, uuid) from public;
revoke all on function pocketcare.can_see_user(uuid, uuid) from public;
revoke all on function pocketcare.is_group_creator(uuid, uuid) from public;
revoke all on function pocketcare.is_connected(uuid, uuid) from public;
grant execute on function pocketcare.is_group_member(uuid, uuid)  to authenticated, anon, service_role;
grant execute on function pocketcare.can_see_user(uuid, uuid)     to authenticated, anon, service_role;
grant execute on function pocketcare.is_group_creator(uuid, uuid) to authenticated, anon, service_role;
grant execute on function pocketcare.is_connected(uuid, uuid)     to authenticated, anon, service_role;

-- ---- Profiles: let co-members read display_name/email ----
drop policy if exists profiles_visible on pocketcare.profiles;
create policy profiles_visible on pocketcare.profiles for select
  using (pocketcare.can_see_user(id, auth.uid()));

-- ---- RLS ----
alter table pocketcare.split_groups enable row level security;
create policy sg_select on pocketcare.split_groups for select using (is_group_member(id, auth.uid()) or created_by = auth.uid());
create policy sg_insert on pocketcare.split_groups for insert with check (created_by = auth.uid());
create policy sg_update on pocketcare.split_groups for update using (is_group_member(id, auth.uid())) with check (is_group_member(id, auth.uid()));

alter table pocketcare.split_group_members enable row level security;
create policy sgm_select on pocketcare.split_group_members for select using (is_group_member(group_id, auth.uid()));
-- The group creator may add themselves and their existing connections directly;
-- non-connections join only via the invite-accept edge function (service role).
create policy sgm_add on pocketcare.split_group_members for insert
  with check (is_group_creator(group_id, auth.uid()) and (user_id = auth.uid() or is_connected(auth.uid(), user_id)));
-- A member may leave (soft-delete their own row).
create policy sgm_leave on pocketcare.split_group_members for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table pocketcare.expenses enable row level security;
create policy ex_all on pocketcare.expenses for all using (is_group_member(group_id, auth.uid())) with check (is_group_member(group_id, auth.uid()));

alter table pocketcare.expense_participants enable row level security;
create policy ep_all on pocketcare.expense_participants for all using (is_group_member(group_id, auth.uid())) with check (is_group_member(group_id, auth.uid()));

alter table pocketcare.settlements enable row level security;
create policy st_all on pocketcare.settlements for all using (is_group_member(group_id, auth.uid())) with check (is_group_member(group_id, auth.uid()));

alter table pocketcare.expense_postings enable row level security;
create policy epost_owner on pocketcare.expense_postings for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table pocketcare.split_invitations enable row level security;
create policy inv_select on pocketcare.split_invitations for select using (inviter = auth.uid() or is_group_member(group_id, auth.uid()));
create policy inv_insert on pocketcare.split_invitations for insert with check (inviter = auth.uid() and is_group_member(group_id, auth.uid()));

alter table pocketcare.connections enable row level security;
create policy conn_select on pocketcare.connections for select using (user_a = auth.uid() or user_b = auth.uid());

grant all on table pocketcare.split_groups, pocketcare.split_group_members, pocketcare.expenses,
  pocketcare.expense_participants, pocketcare.settlements, pocketcare.expense_postings,
  pocketcare.split_invitations, pocketcare.connections to anon, authenticated, service_role;

-- ---- Seed identity for existing users + on signup ----
update pocketcare.profiles p set email = u.email,
  display_name = coalesce(p.display_name, u.raw_user_meta_data->>'username', split_part(u.email, '@', 1))
  from auth.users u where u.id = p.id and p.email is null;

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = pocketcare, public as $$
begin
  insert into profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)))
  on conflict (id) do update set email = excluded.email,
    display_name = coalesce(profiles.display_name, excluded.display_name);
  insert into entitlements (user_id, tier, premium_trial_start_date, monthly_quota_total, monthly_quota_used, purchased_quota_remaining, quota_reset_date)
  values (new.id, 'free', now(), 200, 0, 0, now() + interval '14 days')
  on conflict (user_id) do update set premium_trial_start_date = coalesce(entitlements.premium_trial_start_date, now());
  if coalesce(new.is_anonymous, false) then
    insert into guest_sessions (user_id) values (new.id) on conflict (user_id) do nothing;
  end if;
  perform seed_default_categories(new.id);
  return new;
end;
$$;
