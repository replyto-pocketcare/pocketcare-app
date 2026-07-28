# Implementation plan — Pay friends via UPI (settle-up)

**Status:** awaiting approval · **Created:** 2026-07-28 · **Owner:** —

Let a user settle a split balance by paying the other person over UPI, straight from PocketCare. **No money touches PocketCare's accounts** — we never become a party to the transfer.

## Decisions (locked)

| # | Decision | Choice |
|---|----------|--------|
| D1 | Rails | **UPI Intent deep link + QR. No payment provider.** Not Razorpay — see below. |
| D2 | Confirmation | **Two-sided.** Payer marks paid → `pending`; payee confirms → `confirmed`. |
| D3 | Handle storage | `payment_handles` table, **encrypted at rest, server-only, never synced** — disclosed just-in-time via an edge function. See the correction in §2. |
| D4 | Scope | Settle-up only, INR/UPI. Hidden for other currencies. |

---

## 1. Why not Razorpay

Razorpay is a **Payment Aggregator**: funds land in its escrow and settle to a *merchant's* bank account. Routing a settle-up between two PocketCare users through it makes PocketCare the merchant of record for money that isn't ours — the opposite of "nothing hits our accounts". RBI's PA framework restricts escrow credits/debits to permitted merchant-transaction purposes; P2P transfers aren't among them. RazorpayX Payouts is worse for this goal: it requires us to actually hold and disburse funds.

**UPI Intent needs no provider at all.** We build a `upi://pay?...` link; the payer's own UPI app moves the money bank-to-bank. Zero MDR, no escrow, no PA licence, no reconciliation, no settlement risk.

> ⚠️ **Verify before building:** UPI **Collect** (pulling money by entering someone's VPA) was sunset **28 Feb 2026**; Intent is now the mandated flow. We only ever *push* via Intent, which is the surviving path — but confirm the exact position for a non-merchant P2P intent link with a lawyer or PSP. I am not a lawyer and this is a recent rule change.

---

## 2. Correction to D3 — "encrypted + shared" is not possible client-side

The existing zero-trust scheme (`user_keys`, `@pocketcare/crypto`) wraps a DEK with a **passphrase-derived KEK owned by one user**. A co-member has no way to decrypt another user's field. So "encrypt the VPA with our existing envelope and sync it to group members" is self-contradictory — the payer could never read it.

**Resolution: server-mediated disclosure.** `payment_handles` is a **server-only table, in no sync stream** (same pattern as `push_subscriptions` from 0037). The VPA is encrypted at rest with a server-held key and released by an edge function only to a caller who shares a group with the owner *and* has a live balance with them.

What this buys over a plaintext synced column:
- The VPA is **not** copied into every co-member's local SQLite forever.
- Disclosure is **access-controlled, auditable and revocable**.
- A stolen DB dump alone doesn't yield VPAs.

**Be honest about the tier:** this is *not* zero-trust. The server can read these values, unlike passphrase-protected personal fields. It fundamentally must be able to, in order to share them. Say so in the settings copy and in `04-security-and-privacy.md`.

---

## 3. Architecture

```
Settle sheet (/friends, /groups/[id])
   │  balance: you owe Priya ₹430
   ▼
[Pay ₹430 via UPI]
   │
   ├─ GET counterparty handle ──► payment-handle edge fn
   │                               (auth + shares-a-group + has-a-balance)
   │                               decrypts, returns VPA + name, logs disclosure
   ▼
build upi://pay?pa=<vpa>&pn=<name>&am=430.00&cu=INR&tn=<note>&tr=<ref>
   │
   ├─ mobile  → window.location = intent link → UPI app takes over
   └─ desktop → render the same string as a QR for the payer to scan
   │
   ▼  (user returns; no callback exists)
"Did that go through?"  → settleUp({ status: "pending" })
   │                        payer's ledger leg posts NOW (cash really moved)
   ▼
notification → payee: "Akhilesh says he paid you ₹430" [Confirm] [Didn't arrive]
   │
   ├─ Confirm       → status = confirmed, payee's ledger leg posts
   └─ Didn't arrive → status = disputed, compensating entry on the payer's side
```

---

## 4. Data model

### `payment_handles` — server-only, NOT synced

| column | type | notes |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid → `profiles(id)` **cascade** | |
| `kind` | text | `upi` today; `bank`/`iban` later |
| `handle_enc` | text | encrypted VPA (never plaintext at rest) |
| `handle_hint` | text | masked, e.g. `ak••••@okhdfc` — safe to show the owner without decrypting |
| `display_name` | text | name to prefill as `pn=` |
| `is_primary` | boolean | one per `(user_id, kind)` |
| `verified_at` | timestamptz | reserved; we do **not** verify in v1 (§8) |
| `created_at` / `updated_at` / `deleted_at` | | |

RLS: owner-only. **Deliberately absent from `sync-streams.yaml`** — add a comment saying so, because the deploy checklist otherwise trains you to add every new table.

### `payment_handle_disclosures` — audit

`id`, `owner_user_id`, `viewer_user_id`, `group_id`, `created_at`. One row per release. Lets a user see who has fetched their UPI ID, and is the evidence trail if a handle is abused.

### `settlements` — new columns

| column | notes |
|---|---|
| `status` | `confirmed` \| `pending` \| `disputed`. **Default `confirmed`** so every existing row and the current in-app "mark settled" flow keep their exact meaning. |
| `confirmed_at`, `confirmed_by` | who closed it |
| `upi_ref` | our `tr=` reference; optional user-entered UTR |
| `method` | already exists — add `upi_intent` |

Migration `0041_payment_handles.sql`.

---

## 5. The pending-settlement problem (read this before estimating)

Money genuinely left the payer's bank the moment they completed the UPI transaction. But we can't *know* it arrived. These two facts have to be modelled separately, and it's the only subtle part of the feature.

**Proposal:**
- **Payer's ledger leg posts immediately.** Their cash moved; that's a fact independent of confirmation. Not posting it would misstate their balance.
- **Balance netting counts `pending` optimistically**, badged "awaiting confirmation" in the UI. The alternative — excluding pending — shows the payer as *still owing* money they've already sent, which reads as a bug and drives duplicate payments.
- **Only `disputed` is excluded**, and disputing writes a **compensating entry** rather than deleting anything (golden rules #2 and #5: the ledger is append-only, corrections are compensating entries).

**Concrete blast radius** — `settlements` is queried in five places in `src/splits/hooks.ts` (lines ~132, 159, 193, 259, 305) plus `@pocketcare/reconcile`. Each needs `AND status <> 'disputed'`. Missing one causes a *silently wrong balance*, so this gets its own task and its own tests.

---

## 6. Tasks

### Phase A — Foundations

**A1. `@pocketcare/upi` (new core package, tested)**
- `buildIntentUrl({ vpa, name, amount, currency, note, ref })` → `upi://pay?...` with correct percent-encoding.
- `isValidVpa(s)` — `name@handle`, charset and length per NPCI's linking spec.
- `maskVpa(s)` → `ak••••@okhdfc`.
- `formatAmount(minor)` → UPI wants `430.00`, always two decimals, never grouped.
- **Tests:** encoding of `&`/spaces/unicode in `tn`, amount formatting from minor units, VPA accept/reject table, refusal to build a link for a non-INR currency or a zero/negative amount.
- Why a package: it's pure, and a malformed intent URL fails silently inside a third-party app where we can never see it.

**A2. Migration `0041_payment_handles.sql`**
- Both tables + RLS + grants; `settlements` columns with `status` defaulting to `confirmed`.
- Encryption at rest: `pgcrypto` `pgp_sym_encrypt` keyed from a Supabase secret, so `handle_enc` is only readable inside the edge function.
- Validate with pglast.

**A3. Schema + sync**
- `settlements` gains the new columns in `AppSchema`. **`payment_handles` is deliberately NOT added** to `AppSchema` or `sync-streams.yaml` — comment both places.
- Requires `supabase db push` + PowerSync sync-rule redeploy (settlements columns).

### Phase B — Server

**B1. `payment-handle` edge function**
- `POST /set` — upsert your own handle. Validates VPA, encrypts, stores hint.
- `POST /get` — `{ counterpartyId }` → `{ vpa, displayName }`. Authorisation, all three required:
  1. caller and owner share a non-deleted group,
  2. a **non-zero balance** exists between them,
  3. rate limit (e.g. 20/hour/caller).
  Writes a `payment_handle_disclosures` row. Never returns a handle for someone you have no financial relationship with — otherwise this is a directory-harvesting endpoint.
- `POST /forget` — soft-delete your handle.
- Reuses the `assistant`/`receipt-scan` shape: CORS, `json()`, `verify_jwt`, service-role client on `pocketcare`.

**B2. Settlement-confirmation notification**
- Extend `0039`'s settlement trigger: on a `pending` insert, notify the payee with a deep link to confirm. Reuses `notifications` + `notification_prefs` + `notify-dispatch` — add a `settlement_confirm` pref.

### Phase C — Client

**C1. Settings: your UPI ID** (`/settings`)
- Add/replace/remove, showing `handle_hint` rather than the raw value once saved.
- Copy stating plainly: shared only with people you share a group *and* a balance with; the server can read it (not passphrase-protected); here's who has fetched it.
- "Who's seen this" list from `payment_handle_disclosures`.

**C2. `usePaymentHandle` + `src/payments/upi.ts`**
- Just-in-time fetch on tapping Pay (online-only — you need a connection to pay anyway). Never cached to disk.
- Friendly states: counterparty hasn't added a UPI ID → offer "Ask them to add one" via the existing notification path.

**C3. Pay button on the settle sheet** (`app/friends/page.tsx` ~line 303, and group detail)
- Only when: `base === "INR"`, you're the one who owes, amount > 0, counterparty has a handle.
- Mobile → navigate to the intent URL. Desktop → QR of the same string in a modal, plus the masked VPA and a copy button.
- QR: small dependency (`qrcode`) or a canvas renderer. Prefer the library — hand-rolled QR is a bug farm.
- On return: "Did that go through?" → `settleUp({ status: "pending", method: "upi_intent", upi_ref })`.

**C4. Confirmation flow**
- Payee's notification → settle sheet shows *"Akhilesh says he paid you ₹430"* with **Confirm** / **Didn't arrive**.
- Confirm → `status = confirmed`, post the payee's ledger leg.
- Didn't arrive → `status = disputed` + compensating entry on the payer's side, and tell the payer.
- Pending settlements badged wherever balances appear.

**C5. `settleUp()` rework**
- Take `status`; post only the acting party's leg; keep the existing immediate-confirm path (manual "mark settled") working unchanged by defaulting to `confirmed`.
- Add `confirmSettlement()` and `disputeSettlement()`.

**C6. Status filters** — the five `settlements` queries in `hooks.ts` + `@pocketcare/reconcile`. Own task by design (§5).

### Phase D — Cross-cutting

**D1. i18n** — new `payments` namespace (en/hi/nl). UPI is India-specific, so hi matters more than usual here.

**D2. Docs** — `docs/features/upi-settle-up.md`; update `splits.md`, the ER diagram in `02-data-model.md`, the edge-function table in `03-sync-and-offline.md`, and a **new section in `04-security-and-privacy.md`** covering the not-zero-trust tier, the disclosure gate and the audit trail. Dated `PROJECT_REFERENCE.md` entry.

**D3. Verification**
- `pnpm --filter @pocketcare/web typecheck`, `pnpm test:core` (new `@pocketcare/upi` suite).
- Unit tests for balance netting across `confirmed` / `pending` / `disputed`.
- Playwright: settle → pending → confirm → balance clears; and → dispute → balance restored.
- Manual: real UPI app handoff on Android and iOS, desktop QR scan, counterparty with no handle, non-INR user (button absent).

---

## 7. Sequencing & effort

| Order | Tasks | Ships |
|---|---|---|
| 1 | A1, A2, A3 | Schema + URL builder + tests. Nothing visible. |
| 2 | B1, C1, C2 | Users can save a UPI ID and we can fetch one. |
| 3 | C3 | **Milestone 1: pay button works** (optimistic, no confirmation). |
| 4 | C5, C6, B2, C4 | **Milestone 2: two-sided confirmation.** |
| 5 | D1–D3 | i18n, docs, verification. |

**Estimate: 6–9 working days.** Roughly double my earlier 3–5 day figure — that was for the optimistic version. D2 (two-sided confirmation) is most of the difference, and §5/§6 are where it goes.

Milestone 1 is shippable alone if you want the pay button in users' hands sooner, with `status` defaulting to `confirmed` until Milestone 2 lands.

---

## 8. Risks & deliberate non-goals

- **No payment confirmation exists. This is structural, not a gap to close later.** UPI Intent returns no reliable result to a web app, especially a PWA. Anyone claiming otherwise is describing a PSP integration. Design around it; don't promise auto-reconciliation.
- **We do not verify VPA ownership.** Doing so requires a ₹1 penny-drop through a PSP — which is exactly the regulated path we're avoiding. Consequence: a user can enter someone else's VPA. Mitigated by showing the payer the resolved name from their own UPI app before they confirm (their app does the real verification), and by the disclosure audit trail. `verified_at` is reserved for if this ever changes.
- **Wrong-amount / wrong-person payments are unrecoverable by us.** We never hold the funds. Support copy must say this plainly.
- **VPA is a financial identifier.** The disclosure gate (shared group + live balance + rate limit + audit) is what stops this becoming a UPI-ID directory. Don't loosen it for convenience.
- **iOS deep-link handling is fussier than Android.** Budget real device time; a silently-failing `upi://` on iOS is a plausible outcome and may need per-app universal links or a QR fallback on mobile Safari too.
- **Non-goals for v1:** requesting money, non-UPI/international methods, partial settlements, recurring payments, in-app payment history beyond what `settlements` already gives.

## 9. Open questions

1. Should a **guest** account be able to save a UPI handle, or is this registered-users-only? (Leaning: registered only — it's a financial identifier tied to an identity.)
2. Should `pending` settlements **expire** (auto-confirm or auto-dispute after N days) so they don't sit forever if the payee never opens the app? (Leaning: nudge at 3 days, auto-confirm at 14, both configurable.)
3. Do we surface the UPI **`tr=` reference** in the settlement detail so users can match it against their bank statement? Cheap to add, genuinely useful when something goes wrong.
