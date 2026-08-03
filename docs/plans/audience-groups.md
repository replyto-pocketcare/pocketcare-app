# Centralised audience groups

**Status:** plan, not yet implemented · **Date:** 2026-07-29

Yes — and it's the right instinct, because there are currently **three**
overlapping ways to describe "a set of users", only one of which works.

> Schema is `pocketcare` (the npm scope is `@sanvya/*`, the DB schema is not —
> `8b4cb28` / `2cd6ed3` reverted that rename deliberately).

---

## What exists today

| | Table | Membership | Consumers | Admin UI |
|---|---|---|---|---|
| **Notification groups** (0049/0050) | `notification_groups` + `notification_group_members` | explicit rows, plus a trigger syncing from `notification_prefs` | broadcast push | yes — `/admin/notifications` |
| **Segments** (0024) | `segments` | none — a `rule` JSONB of trait equality | **none** | none |
| **Loyalty segments** | — | — | proposed in `mindfulness-and-offers.md` §4 | — |

`notification_groups` is already a generic cohort system in everything but its
name. It has a stable `sys_key` for system-managed groups, explicit membership,
and a working trigger that keeps opt-in groups in sync. `segments` is a design
that never got a consumer.

**So: promote notification groups to first-class audience groups, retire
`segments`, and drop the separate loyalty-segment design from the other plan.**
One concept, many consumers.

---

## ⚠️ Two security problems to fix as part of this

Both are tolerable while groups only pick who gets a push. Both become serious
the moment a group decides a **price** — which is exactly what
`mindfulness-and-offers.md` §3 proposes.

### 1. Any user can add themselves to any group

```sql
create policy group_members_insert on pocketcare.notification_group_members
  for insert with check (user_id = auth.uid());
```

The check constrains *which user* a row is for, but **not which group**. Any
authenticated user can insert `(group_id = <any group>, user_id = self)`.

Today that means self-subscribing to a broadcast. Once a group grants a
discounted price, it's a self-serve discount: read the group list (see below),
insert yourself, get the offer.

**Fix:** membership becomes **service-role only**, except for genuine
self-service opt-ins, which are identified by `sys_key LIKE 'opt-in:%'`:

```sql
create policy group_members_self_optin on pocketcare.notification_group_members
  for insert with check (
    user_id = auth.uid()
    and exists (select 1 from pocketcare.notification_groups g
                 where g.id = group_id and g.sys_key like 'opt-in:%')
  );
```

Same shape for delete. Everything else is written by the trigger or by an admin
running as service role.

### 2. Every user can read every group

```sql
create policy groups_read on pocketcare.notification_groups for select using (true);
```

With names like "Alerts: Budget limits" that's harmless. With names like
"Churn risk", "High spenders", "Loyal — 6 months" it hands your entire
segmentation to anyone who opens the network tab.

**Fix:** clients may read only the groups they belong to, and only the fields
they need (`id`, `name`, `sys_key`). Admin reads run as service role.

---

## The model

Rename, don't rebuild — the tables are right, the names are too narrow.

```
pocketcare.audience_groups            (was notification_groups)
  id · name · description · sys_key
  kind          text  -- 'optin' | 'manual' | 'derived'
  rule          jsonb -- for kind='derived', evaluated server-side
  active        boolean
  created_at

pocketcare.audience_group_members     (was notification_group_members)
  group_id · user_id · joined_at
  source        text  -- 'optin' | 'admin' | 'derived'  (why they're in it)
```

Two additions worth their weight:

- **`kind`** distinguishes the three things that already coexist without being
  named: opt-in groups synced from prefs, hand-picked lists, and rule-evaluated
  cohorts. Deleting a member from a derived group is meaningless — `kind` is
  what lets the UI say so instead of silently re-adding them on the next run.
- **`source`** on membership makes the trigger's rows distinguishable from an
  admin's. Without it, a resync can't tell "the admin put them here" from "the
  rule used to match", and will happily delete a manual addition.

`segments.rule` migrates into `audience_groups.rule` with `kind='derived'`, then
`segments` is dropped. It has no consumers, so nothing breaks.

### Renaming safely

`ALTER TABLE ... RENAME` plus **views under the old names** for one release, so
the existing edge functions and admin actions keep working while they're
migrated. Drop the views in a follow-up migration once nothing references them.
PowerSync note: the local table name comes from the unqualified source name, so
`AppSchema` and `sync-streams.yaml` both change in the same release.

---

## Derived groups (this replaces §4 of the other plan)

Rules evaluated **server-side only**, in a scheduled job:

```json
{ "tenure_days": {"gte": 180}, "active_days": {"gte": 60} }
```

Facts come from a server-owned `user_metrics` table (tenure, active days,
transaction count, streak, last active) — all derived from rows the user already
gave you, needing no new tracking. The session-time question from
`mindfulness-and-offers.md` §4 is unchanged and still open; if it ships, it's one
more metric here, and nothing about this design depends on it.

Client never evaluates rules. It only ever learns *"you are in group X"* — never
the rule, never the other groups.

---

## Consumers

The point of the exercise. All of these target `audience_groups`:

| Consumer | Status |
|---|---|
| Broadcast push | exists — repoint at renamed tables |
| Notification opt-ins | exists — the `sys_key`/trigger machinery is unchanged |
| **Promotional pricing** (`price_offers.segment_id` → `group_id`) | the other plan's §3 |
| Feature flags / staged rollout | future, free once this lands |
| Beta cohorts | future — replaces ad-hoc `promo_codes.segment` text |

`promo_codes.segment` is currently a free-text informational field. It becomes a
real `group_id` reference.

---

## Admin: one screen, not per-feature

New `/admin/audiences`:

- list groups with live member counts and `kind`
- create manual groups; add/remove by email (the existing
  `addUsersToGroupByEmail` action, repointed)
- view members (the `12521dc` feature, kept)
- edit a derived group's rule, with **"preview matches" before saving** — a rule
  that silently captures 40 000 users is how an offer becomes expensive
- **never** show a delete-member button on a derived group; explain instead

`/admin/notifications` keeps sending, but picks an audience rather than owning
the concept.

---

## Migrations

- **`0052_audience_groups.sql`** — rename both tables, add `kind`/`rule`/`active`
  and `source`, backfill (`kind='optin'` where `sys_key like 'opt-in:%'`, else
  `'manual'`; `source='optin'` for trigger-made rows), compatibility views under
  the old names, and **fix both RLS policies**.
- **`0053_user_metrics.sql`** — server-owned derived facts + the refresh
  function.
- **`0054_drop_segments.sql`** — migrate any `segments` rows to derived groups,
  drop `segments`, drop the compatibility views. Separate migration on purpose:
  if the rename causes trouble, this is the one you don't run yet.

All re-runnable, schema-qualified, `drop policy if exists` before every
`create policy`, no cross-row constraints on synced tables, `pglast`-validated.

---

## Order

1. `0052` rename + **RLS fixes** — the security fixes shouldn't wait behind the
   feature work.
2. Repoint edge functions and admin actions; verify broadcast still sends.
3. `/admin/audiences`.
4. `0053` metrics + derived groups.
5. `0054` drop `segments` + views, once (2) is confirmed.

## Verification

- `pglast` on each migration; typecheck; core tests.
- **Security, explicitly:** as a normal signed-in user, attempt to insert
  yourself into a non-opt-in group (must fail) and to select a group you don't
  belong to (must return nothing). These are the two bugs above; they deserve a
  test each, not a manual glance.
- Toggling a notification pref still moves you in and out of the right opt-in
  group (the 0050 trigger).
- Broadcast push still reaches the right people after the rename.
- A derived-group preview count matches what the job actually writes.

## Naming note

The word "group" is now doing four jobs in this codebase: `split_groups`
(expense sharing), `recurring_groups` (recurring buckets), notification groups,
and segments. **"Audience"** is deliberately a different word — a user-facing
"Groups & trips" and an admin-facing "Audiences" should never be confused in a
query, a doc, or a conversation.
