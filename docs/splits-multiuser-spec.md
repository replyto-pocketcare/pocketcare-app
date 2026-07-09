# PocketCare — Multi-user Splits (Splitwise-style) — Design Spec

Status: **PROPOSED — for review. Nothing here is applied yet.**
Author: engineering
Supersedes: the Phase-1/2 contact-based split schema (`0008`/`0009`/`0010`).

## 0. Principles

1. **One shared ledger, no copies.** Each group/expense/settlement exists as a single canonical row, made visible to the right users via membership. No per-user duplication, no fan-out.
2. **Everyone is a registered user.** No local contacts / placeholders. A participant is always a real `auth.users` id. You must invite + they must join before you can split with them.
3. **Shared rows carry no private data.** Amount, who paid, who owes — yes. Your bank account / private category — never (those live only on your private `expense_postings` → `transactions`).
4. **Balances are derived, never stored.** Recomputed from the ledger, so offline merges can't corrupt them.
5. **Offline-first preserved.** Expense entry/edit is a normal PowerSync local write uploaded under RLS. Only *membership mutation* (joining a group) goes through an edge function.

Decision baked in for v1: **every split belongs to a group** (a 1:1 split auto-creates a 2-person group). This makes PowerSync bucketing purely group-based and avoids groupless-expense buckets. Groupless "direct" expenses can come later.

---

## 1. Schema (proposed DDL, `pocketcare` schema)

New tables. `expense_participants` merges the old shares+payers into one row per user. Note the **denormalized `group_id`** on `expenses`, `expense_participants`, and `settlements` — required so PowerSync can bucket child rows by group without joins.

```sql
set search_path to pocketcare, public;

-- Groups (a trip/household, or an auto-created 2-person container for a 1:1)
create table pocketcare.split_groups (
  id           uuid primary key default gen_random_uuid(),
  created_by   uuid not null references auth.users(id),
  name         text not null,
  kind         text not null default 'group',   -- 'group' | 'trip'
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
  role       text not null default 'member',     -- 'owner' | 'member'
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
  amount      int  not null,                     -- minor units, total
  currency    text not null,
  occurred_at timestamptz not null,
  split_mode  text not null default 'equal',     -- equal | exact | percent
  version     int  not null default 1,           -- LWW / audit
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table pocketcare.expense_participants (
  id           uuid primary key default gen_random_uuid(),
  expense_id   uuid not null references pocketcare.expenses(id) on delete cascade,
  group_id     uuid not null references pocketcare.split_groups(id) on delete cascade, -- denormalized for bucketing
  user_id      uuid not null references auth.users(id),
  paid_amount  int  not null default 0,          -- what this user put in
  share_amount int  not null default 0,          -- what this user consumed
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (expense_id, user_id)
);

create table pocketcare.settlements (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references pocketcare.split_groups(id) on delete cascade, -- denormalized
  from_user  uuid not null references auth.users(id),  -- payer
  to_user    uuid not null references auth.users(id),  -- receiver
  amount     int  not null,
  currency   text not null,
  method     text,                                     -- 'cash' | 'upi' | free text
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
  expense_id     uuid,                             -- references expenses.id (shared)
  settlement_id  uuid,                             -- references settlements.id (shared)
  transaction_id uuid not null,                    -- their private transactions row
  role           text not null,                    -- own_share | lend | borrow | settlement
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

-- Invitations (registered-user gate)
create table pocketcare.split_invitations (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references pocketcare.split_groups(id) on delete cascade,
  inviter       uuid not null references auth.users(id),
  invitee_email text not null,
  token         text not null unique,
  status        text not null default 'pending',   -- pending | accepted | revoked | expired
  accepted_by   uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  expires_at    timestamptz
);

create index expenses_group_idx        on pocketcare.expenses(group_id, occurred_at desc);
create index eparticipants_group_idx   on pocketcare.expense_participants(group_id);
create index eparticipants_user_idx    on pocketcare.expense_participants(user_id);
create index settlements_group_idx     on pocketcare.settlements(group_id);
create index members_user_idx          on pocketcare.split_group_members(user_id);
create index postings_user_idx         on pocketcare.expense_postings(user_id);
create index invitations_token_idx     on pocketcare.split_invitations(token);
```

---

## 2. Membership helpers (SECURITY DEFINER — avoids RLS recursion)

RLS policies must not re-trigger RLS on `split_group_members` (infinite recursion). Wrap the check in a `security definer` function that bypasses RLS internally:

```sql
create or replace function pocketcare.is_group_member(g uuid, u uuid)
returns boolean language sql stable security definer
set search_path = pocketcare, public as $$
  select exists (
    select 1 from pocketcare.split_group_members m
    where m.group_id = g and m.user_id = u and m.deleted_at is null
  );
$$;
revoke all on function pocketcare.is_group_member(uuid, uuid) from public;
grant execute on function pocketcare.is_group_member(uuid, uuid) to authenticated, anon, service_role;
```

---

## 3. RLS policies (membership-based)

Reads are gated by group membership; writes by membership + self-ownership where appropriate. Membership *mutation* is service-role only (edge function).

```sql
-- split_groups
alter table pocketcare.split_groups enable row level security;
create policy sg_select on pocketcare.split_groups for select
  using (is_group_member(id, auth.uid()) or created_by = auth.uid());
create policy sg_insert on pocketcare.split_groups for insert
  with check (created_by = auth.uid());
create policy sg_update on pocketcare.split_groups for update
  using (is_group_member(id, auth.uid())) with check (is_group_member(id, auth.uid()));

-- split_group_members: members can SEE co-members; INSERT/DELETE only via edge fn (service role)
alter table pocketcare.split_group_members enable row level security;
create policy sgm_select on pocketcare.split_group_members for select
  using (is_group_member(group_id, auth.uid()));
-- (no client insert/update/delete policy → only service_role can mutate membership)

-- expenses: visible to group members; writable by group members
alter table pocketcare.expenses enable row level security;
create policy ex_select on pocketcare.expenses for select
  using (is_group_member(group_id, auth.uid()));
create policy ex_write on pocketcare.expenses for all
  using (is_group_member(group_id, auth.uid()))
  with check (is_group_member(group_id, auth.uid()));

-- expense_participants: gated by the (denormalized) group_id
alter table pocketcare.expense_participants enable row level security;
create policy ep_select on pocketcare.expense_participants for select
  using (is_group_member(group_id, auth.uid()));
create policy ep_write on pocketcare.expense_participants for all
  using (is_group_member(group_id, auth.uid()))
  with check (is_group_member(group_id, auth.uid()));

-- settlements: visible to members; writable by members (usually from_user/to_user)
alter table pocketcare.settlements enable row level security;
create policy st_select on pocketcare.settlements for select
  using (is_group_member(group_id, auth.uid()));
create policy st_write on pocketcare.settlements for all
  using (is_group_member(group_id, auth.uid()))
  with check (is_group_member(group_id, auth.uid()));

-- expense_postings: PRIVATE to owner
alter table pocketcare.expense_postings enable row level security;
create policy epost_owner on pocketcare.expense_postings for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- invitations: inviter manages; accept via edge fn (service role)
alter table pocketcare.split_invitations enable row level security;
create policy inv_select on pocketcare.split_invitations for select
  using (inviter = auth.uid() or is_group_member(group_id, auth.uid()));
create policy inv_insert on pocketcare.split_invitations for insert
  with check (inviter = auth.uid() and is_group_member(group_id, auth.uid()));

grant all on table
  pocketcare.split_groups, pocketcare.split_group_members, pocketcare.expenses,
  pocketcare.expense_participants, pocketcare.settlements, pocketcare.expense_postings,
  pocketcare.split_invitations
  to anon, authenticated, service_role;
```

Notes:
- **Write authority / LWW:** any member can edit an expense; `version` + `updated_at` drive last-write-wins, and balances are recomputed from the ledger so a bad merge self-heals on the next edit. A follow-up can restrict edits to `created_by` if desired.
- **Membership is service-role-only** to prevent a user adding themselves to arbitrary groups. Joining happens through `split-invite-accept`.

---

## 4. PowerSync sync rules (membership buckets)

The shared tables move to a **parameterized bucket per group**; private tables stay per-user. Expressed as classic `bucket_definitions` (parameter queries are first-class there). We'll adapt to the edition-3 `streams` file during implementation.

```yaml
bucket_definitions:
  # One bucket per group the user belongs to.
  group_data:
    parameters: SELECT group_id AS group_id FROM pocketcare.split_group_members
                WHERE user_id = request.user_id() AND deleted_at IS NULL
    data:
      - SELECT * FROM pocketcare.split_groups        WHERE id = bucket.group_id
      - SELECT * FROM pocketcare.split_group_members WHERE group_id = bucket.group_id
      - SELECT * FROM pocketcare.expenses            WHERE group_id = bucket.group_id
      - SELECT * FROM pocketcare.expense_participants WHERE group_id = bucket.group_id
      - SELECT * FROM pocketcare.settlements         WHERE group_id = bucket.group_id

  # Per-user private data (existing pattern) + projections + invites you sent.
  user_private:
    parameters: SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM pocketcare.expense_postings   WHERE user_id = bucket.user_id
      - SELECT * FROM pocketcare.split_invitations  WHERE inviter = bucket.user_id
      # … plus all existing per-user tables (accounts, transactions, budgets, …)
```

Why `group_id` is denormalized on children: PowerSync `data:` queries filter by a bucket parameter with a **direct column**, not joins/subqueries — so `expense_participants` and `settlements` each carry `group_id`.

**Revocation:** when a user is removed from `split_group_members` (or leaves), the `group_data` parameter set shrinks and PowerSync drops that bucket from the device on next sync. Verify this behavior in testing.

---

## 5. Edge functions (Deno, service role)

Only membership mutation and identity resolution need the server. Expense/settlement writes go through PowerSync's normal upload under RLS.

### `split-invite` — create an invite link
- **Auth:** caller (JWT) must be a member of `group_id`.
- **Input:** `{ group_id, invitee_email }`.
- **Logic:** insert `split_invitations` (random `token`, `expires_at = now()+14d`); return `{ token, link: "<APP_URL>/join?token=…" }`.
- **Email:** out of scope for v1 (link-only). Later: send via provider if `RESEND_API_KEY` set.

### `split-invite-accept` — join a group
- **Auth:** the accepting user (JWT).
- **Input:** `{ token }`.
- **Logic (service role, transactional):**
  1. Load invitation by token; validate `status='pending'` and not expired.
  2. (Optional) check the invitee's email matches the accepting user's email — or allow any logged-in user with the link (decision below).
  3. `insert into split_group_members(group_id, user_id=accepter, role='member') on conflict do nothing`.
  4. `update split_invitations set status='accepted', accepted_by=accepter`.
  5. Return `{ group_id }`.
- **Result:** the new member's `group_data` bucket now includes the group → syncs down automatically.

### (No `split-write` function.)
Expense/participant/settlement creation and edits are ordinary local writes uploaded by PowerSync and enforced by RLS — preserving offline-first.

---

## 6. Balances (derived, client-side)

For the user's synced groups, load `expense_participants` (+ `settlements`) and compute the pairwise net with the existing pro-rata edge formula, now keyed by `user_id`:

```
edge(you, other) on an expense = (other.share·you.paid − you.share·other.paid) / total_paid
```
rounded to sum exactly to your net; then subtract settlements between the two of you. Aggregate across groups for the global Friends view, keep per-group for the group view. Cache later if needed.

---

## 7. Personal projection into your budget (private)

Unchanged in spirit from what we built — each user reflects **their own** share into their private ledger, driven by their `expense_participants` row:
- `paid ≥ share` → expense(share) on your account + transfer(paid−share) to Receivable.
- `paid < share` → expense(paid) on your account + expense(share−paid) on Payable.
- purely owing (paid 0) → expense(share) on Payable.

Linked via private `expense_postings(user_id, expense_id, transaction_id, role)`.

**Cross-user nuance:** when *you* created the expense you already chose your account, so your projection is automatic. If **someone else** marked *you* as a payer, your app knows the amount but not which account — so it shows a lightweight "attach the ₹X you paid to an account" prompt (or leaves it on a generic cash bucket until you do). Owing amounts always auto-project to Payable (no account needed).

---

## 8. Cutover plan

Split is brand-new with little real data, so a clean replace is simplest.

1. **Migration `0011_splits_multiuser.sql`:** `drop table` the current split tables (`contacts`, `split_groups`, `split_group_members`, `shared_expenses`, `shared_expense_shares`, `shared_expense_payers`, `settlements`, `expense_postings`) and `create` the schema in §1 + helpers §2 + RLS §3. (Also drop `accounts.kind`? No — keep it; Receivable/Payable virtual accounts stay.)
2. **PowerSync:** replace the per-user split streams with the buckets in §4; **redeploy sync rules**; ensure the new tables are in the `powersync` publication.
3. **Client rewrite (`apps/web/src/splits/*`, Friends/Groups pages, add-transaction editor):** key everything on `user_id`; replace the contact picker with a **member/friend picker** (users you share a group with); add invite UI (create link) and a `/join?token=` page; wire projections from `expense_participants`.
4. **Deploy edge functions** `split-invite`, `split-invite-accept`.

Order matters: apply migration → publication → deploy sync rules → deploy edge functions → ship client.

---

## 9. Risks & test plan

- **RLS recursion / leakage** — the single most dangerous area. Use the `security definer` helper; write explicit tests: as user A, attempt to `select` a group/expense you're not a member of (must return 0 rows) at the SQL level *and* via the API.
- **PowerSync bucket correctness & revocation** — verify a member added via accept receives the group's history; verify a removed member stops receiving updates on next sync.
- **Two-account manual test matrix:** create group → invite (link) → accept on account B → A adds expense → B sees it & correct balance → B settles → A sees settlement & zeroed balance → each side's personal budget shows only their share.
- **Offline:** A creates an expense offline → reconnect → uploads under RLS → B receives.
- **Authority/merge:** simultaneous edits to one expense resolve LWW without corrupting derived balances.

---

## 10. Open decisions (please confirm)

1. **Invite acceptance strictness:** must the accepting user's email equal `invitee_email` (stricter, needs they signed up with that email), or can anyone with the link join (simpler, link is the secret)? *Recommend: link-is-the-secret for v1, with expiry.*
2. **Edit authority:** any member can edit an expense (simplest, LWW) vs only `created_by`. *Recommend: any member for v1.*
3. **1:1 splits:** auto-create a hidden 2-person group (recommended, keeps bucketing uniform) vs support true groupless expenses now (extra bucket).
4. **Friends list source:** derive from shared-group membership only (v1) vs add an explicit `connections` table now.
5. **Migration:** confirm it's OK to **drop existing split data** (contacts/groups/expenses created during Phase 1–2 testing) as part of the cutover.

Once these are settled I'll implement in order: migration + helpers + RLS → publication + sync rules → edge functions → client rewrite, with a two-account test pass at each step.
