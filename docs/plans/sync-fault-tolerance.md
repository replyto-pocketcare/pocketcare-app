# Plan — Sync fault tolerance: never lose a user's write

**Status:** awaiting approval · **Created:** 2026-07-28

## What went wrong, precisely

PowerSync's upload queue is **strictly ordered, retried forever, with no dead-letter path**. That is correct for *transient* failures (offline, 5xx, timeout) and catastrophic for *permanent* ones (RLS denial, FK violation, check constraint):

1. A permanently-failing op **can never succeed**, so it retries indefinitely.
2. The queue is **head-of-line blocked** — every write behind it is frozen, including unrelated ones.
3. The only escape is to **delete the op**, which destroys the user's data with no record of what it was.

That third point is the real failure. We shipped a "Discard" button that did exactly this, and a user lost expenses they cannot now identify. **A repair tool that destroys data silently is worse than no repair tool.**

### The underlying cause of the orphans
A single logical action writes **N independent queue ops** that upload in **N separate transactions**:

```
createGroup()  →  INSERT split_groups        (request 1)
                  INSERT split_group_members (request 2)   ← RLS needs request 1 to have landed
createSplitExpenseItemized()
               →  INSERT expenses            (request 1)
                  INSERT expense_items ×N    (request 2)   ← FK needs request 1
                  INSERT expense_item_shares (request 3)
                  INSERT expense_participants(request 4)
```

There is **no atomicity across that boundary**. Any subset can land. If request 1 fails or is lost, requests 2–4 are permanently unsyncable — and they block everything behind them. This is the same category as the `0040` sum-trigger mistake: *assuming the client's single local transaction survives to Postgres.* It doesn't.

---

## Layer 0 — Recover what's already lost (do first)

**The rows are probably still on the device.** `insertRow` writes to local SQLite; PowerSync records the upload instruction separately in `ps_crud`. Discarding removed the *instruction*, not the row.

Build a **Repair** action that finds local rows with no server counterpart and re-queues them:

- For each synced table, find local rows whose `id` is absent from the last-synced server set.
- Show them as a list — "12 transactions, 3 expenses were never uploaded" — with amounts and dates so the user recognises them.
- **Re-queue** (preferred) or **Export to JSON/CSV** so nothing depends on our being right.

⚠️ **Tell affected users not to clear site data or reinstall** until this ships — a full re-sync may reconcile local-only rows away.

---

## Layer 1 — Don't create unsyncable writes (prevention)

Move aggregate writes to **server-side RPCs that take the whole aggregate and write it in one transaction**:

| RPC | Replaces |
|---|---|
| `create_split_group(name, kind, currency, member_ids[])` | `createGroup`'s 1 + N inserts |
| `create_split_expense(expense, participants[], items[], shares[])` | `createSplitExpenseItemized`'s 4 request groups |
| `record_settlement(...)` | `settleUp`'s settlement + postings |

One request, one transaction: it all lands or none of it does. This **eliminates the entire orphan class**, and incidentally removes the "RLS policy depends on a sibling row having arrived" fragility that produced the `split_group_members` error.

Offline behaviour is preserved: the *call* is queued like any other write. What changes is that the unit of queuing becomes the whole logical action rather than a row.

**Cost:** this is the biggest piece of work here, and it changes how splits are written. It's also the only change that makes the failure impossible rather than merely recoverable.

---

## Layer 2 — Classify failures (triage)

In `connector.ts`, distinguish transient from permanent:

| Class | Signals | Behaviour |
|---|---|---|
| **Transient** | offline, 5xx, 408, 429, network error | Retry forever. Current behaviour, and correct. |
| **Permanent** | 400/401/403/409/422; PG `23503` FK, `23505` unique, `23514` check, `42501` RLS | Retry a few times, then quarantine. |

Track an attempt count per op. A permanent failure that has been retried 3 times will never succeed; continuing is just a way to stay broken quietly.

---

## Layer 3 — Dead-letter, never delete (preservation)

On quarantine, **move the op out of `ps_crud` into a `failed_writes` table** — full payload, table, operation, error code and message, first/last attempt, attempt count.

Two consequences, both essential:

- **The queue unblocks.** Everything behind the poison op syncs. One bad row stops freezing a user's whole account.
- **Nothing is destroyed.** The write still exists, in a form that can be inspected, retried, exported, or re-created.

`failed_writes` is local-first and **synced to the server** so it survives losing the device — but the payload is the user's own data, so it goes in their own owner-scoped table, not into diagnostics.

---

## Layer 4 — Recovery UX (user agency)

A **"Problems syncing"** entry in Settings, with a banner when non-empty:

> **3 changes couldn't be saved**
> A grocery expense from 12 Jun · "Fresh Mart" · ₹1,122.50
> *The group it belonged to no longer exists.*
> **[Retry]  [Re-create]  [Export]  [Discard]**

Rules:
- Every item is described in **user language**, never `23503`.
- **Discard always offers an export first** and is never the default.
- **Re-create** opens the original form prefilled, so the user can save it properly.
- Errors here are already auto-reported to `/admin/errors`, so you see them without the user reporting.

---

## Layer 5 — Preflight (cheap, do early)

Validate before queuing what we already know how to validate:

- Reject an aggregate whose invariants fail *before* it enters the queue (the receipts reconcile gate already does this — extend the pattern).
- Never write a child row whose parent isn't itself already synced **or** in the same queued aggregate.
- Where possible, prefer server-generated ordering guarantees over client assumptions.

---

## Sequencing

| Order | Layer | Why here |
|---|---|---|
| 1 | **Layer 0 — Repair/recover** | Users have unsynced data on devices right now. Time-sensitive. |
| 2 | **Layer 2 + 3 — Classify + dead-letter** | Stops head-of-line blocking and stops data destruction. Biggest safety win per unit of work. |
| 3 | **Layer 4 — Recovery UX** | Makes the dead-letter queue usable by a human. |
| 4 | **Layer 1 — Aggregate RPCs** | Removes the root cause. Largest change; safe to do after the net exists. |
| 5 | **Layer 5 — Preflight** | Incremental hardening. |

Layers 2+3 without 4 is a bad half-measure: data would be quarantined where nobody can see it. Do them together.

## Testing this properly

The bugs in this area have all been ones reasoning didn't catch. Needs:
- **Fault injection** — a dev toggle that makes a chosen table's uploads fail with a chosen PG code, so the whole path can be exercised on demand.
- Tests that a poison op quarantines, the queue drains past it, and the payload survives round-tripping.
- An explicit test that **discard exports before deleting**.

## Non-goals
- Not rewriting away from PowerSync. The offline-first model is right; it just needs a dead-letter path.
- Not automatic conflict resolution. Different problem.
