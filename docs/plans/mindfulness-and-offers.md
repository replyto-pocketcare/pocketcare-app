# Need vs Greed, mindfulness insights, loyalty segments & promotional pricing

**Status:** plan, not yet implemented · **Date:** 2026-07-29

Four features. §1 and §2 are the product; §3 and §4 are the commercial side.
They're independent — §1 can ship alone, and should.

> **Naming note.** The npm scope is now `@sanvya/*`, but the Postgres schema is
> still `pocketcare` — deliberately (`8b4cb28`, `2cd6ed3` reverted an attempt to
> rename it). Every migration below uses `pocketcare.`.

---

## ⚠️ Two decisions I'd ask you to reconsider

Both are your call, and the plan implements what you chose. But neither risk is
obvious from the outside, so they belong at the top rather than in a footnote.

### 1. Session-time tracking contradicts a promise the app makes on screen

You chose to add session tracking to measure "active time". That conflicts with
copy **currently shipping** in the first-run walkthrough:

> "Nothing is tracked automatically — you'll type your spends in yourself."
>
> "Your data is yours. It stays on your device and in your private account — we
> don't share it, and nobody else can see it."

and with `docs/features/diagnostics.md`, which lists **"no automatic telemetry"**
as a deliberate non-goal, in a section written after a data-loss incident.

That copy exists because a 60+ user bounced over exactly this fear. Shipping
usage telemetry underneath it would make those sentences untrue.

**Three honest ways forward.** Pick one; the plan assumes (c) with (a) preferred:

- **(a) Don't track sessions.** Derive loyalty from tenure + distinct active days
  + transaction count, all already in the database. For "loyal customer" offers
  this is arguably a *better* signal — someone logging spends for eight months is
  more loyal than someone who left a tab open.
- **(b) Track, and change the promise.** Rewrite the walkthrough and privacy copy
  to say what is collected. Honest, but it weakens the pitch that won that user.
- **(c) Track, opt-in, disclosed.** Off by default, a plain-language toggle in
  Settings → Privacy, and the walkthrough gains one line. Keeps the promise true
  for anyone who doesn't opt in — but a mostly-off signal is a poor basis for
  segmentation, so expect low coverage.

Whichever you pick, **§4 below works without it** — the loyalty rules are written
against derived metrics, with session time as an optional extra input.

### 2. Storing Need/Greed as labels can be destroyed by the user

You chose to reuse labels. The mechanics that make that risky:

- `/settings/labels` lets anyone **rename** or **soft-delete** any label
  (`app/settings/labels/page.tsx`). Deleting "Greed" silently erases every
  verdict — there is no other record of them.
- Every insight query becomes a two-hop join through `transaction_labels`.
- The two labels appear in the user's own label list, in the label picker on the
  transaction form, and in "Spending by label" on the dashboard.

The mitigation is a `labels.is_system` flag so they can't be renamed or deleted
— **which is a migration anyway**, so the "no migration" saving disappears.

**My recommendation stands: `transactions.intent` (`need` | `greed` | NULL).**
One column, no joins, cannot be deleted by accident, and the mindfulness
aggregation becomes trivial. If you still prefer labels, §1 below has both
variants and only the storage layer differs.

---

## §1 — Need vs Greed

A dedicated page for judging past spending, one transaction at a time.

### Interaction

- **Touch:** swipe **left = Need**, **right = Greed** (as specified). Implemented
  with framer-motion drag, which the app already uses.
- **Pointer/keyboard:** two large buttons, plus ← / → arrow keys. Not a
  second-class fallback — most review sessions on desktop will use them.
- **Undo** on the last card, always. A mis-swipe is guaranteed and the whole
  feature depends on trusting your own data.
- **Skip** leaves it untagged for later.

### The card

Per your description:

- **Amount, large**, at the top — it's the thing being judged.
- **Title** (merchant/description) below it.
- **The account, coloured with its own colour** (`accounts.color`, the same
  colour used on the dashboard tiles), with its name.
- Date, and category if set.
- A progress line: "12 left to review".

Reuses `avatarColor`/`merchantTitle` from `src/ui/TransactionTile.tsx` so a
merchant looks the same here as everywhere else.

### Scope and ordering

- **Expenses only.** Income and transfers are not spending decisions; including
  them would make the queue mostly noise.
- **Untagged first**, newest first — recent spending is the spending you can
  still remember.
- Transfers between own accounts, opening balances and adjustments excluded.

### Storage

**Recommended:** migration `0048` adds `transactions.intent text` (nullable,
`check (intent in ('need','greed'))`) + AppSchema. Nullable and no backfill —
untagged is the normal starting state, not an error.

**If reusing labels instead:** two reserved labels created on first visit with
deterministic ids (same trick as `recurring_groups`), plus `labels.is_system` so
`/settings/labels` hides rename/delete for them. The rest of §1 is unchanged.

### Editing later

Tagged transactions stay editable: an `intent` control on the transaction detail
page, and a filter on `/transactions` for need / greed / untagged. The review
page shows untagged **by priority**, exactly as you asked, but a "Review tagged"
toggle lets someone revisit.

**Files:** `app/reflect/page.tsx` (new), `src/reflect/{IntentCard,useIntentQueue}.tsx`,
`app/transactions/[id]/edit/page.tsx`, migration `0048`, `packages/db/src/index.ts`,
nav entry.

---

## §2 — Mindfulness insights

Two tiers, so the section is never empty and tagging visibly earns better output.

### Tier 1 — no tagging required

Computable today from the ledger:

| Insight | Signal |
|---|---|
| No-spend days | days with zero expenses this month vs last |
| Small-purchase drift | count and total of sub-₹200 spends — the ones that vanish unnoticed |
| Late-night spending | share of spend logged 22:00–04:00, a well-known impulse window |
| Weekend vs weekday | ratio, and whether it's widening |
| Category creep | a category up >30% on its own 3-month average (the existing `catSpike` generator already computes this) |
| Restraint streak | consecutive days under the daily average |

### Tier 2 — unlocked by Need/Greed

| Insight | Signal |
|---|---|
| Greed ratio | greed spend ÷ total, this month vs last |
| Most-regretted category | category with the highest greed share |
| Greed by weekday / hour | when your resolve slips |
| Trend | greed ratio over 6 months — the headline "are you getting more mindful?" |

Appears once **≥ 20 tagged expenses** exist. Below that the sample is too small
to say anything true, and a confident wrong claim is worse than silence — same
threshold logic as `@sanvya/splits-insights`.

### Where it lives

- **Pure functions in a new `packages/core/mindfulness`**, unit-tested, following
  `splits-insights`: plain records in, ranked insights out. ⚠️ New workspace
  package ⇒ `pnpm install` locally before CI, as with `splits-insights`.
- **Rendered as insight cards** via the existing generators (`src/insights/`), so
  they join the `/insights` feed rather than becoming a fourth place to look.
- Tone matters: these are observations, **not scolding**. "You spent ₹4,200 on
  things you called Greed this month, down from ₹6,800" — never "you overspent".
  The product's whole thesis is that noticing is the point; judgement belongs to
  the user, who has literally already made it.

---

## §3 — Promotional pricing

### What exists, and why it isn't this

`promo_codes` / `promo_redemptions` (0024) grant **free months of a tier** when a
user redeems a code. That's a comp grant, not a discount, and it can't render a
struck-through price. `segments` exists but has **no UI and no consumer** — its
`rule` is trait-based (gender/country) only.

### New: `price_offers` (migration `0049`)

```
pocketcare.price_offers
  id uuid pk
  tier text check in ('lite','pro')
  cycle text check in ('monthly','yearly')
  price int             -- discounted price, MINOR UNITS (paise)
  label text            -- "Founder's offer", shown on the card
  starts_at / ends_at timestamptz   -- ends_at drives "offer ends in 3 days"
  segment_id uuid null  -- null = everyone
  active boolean
```

**Minor units, not rupees.** `PLANS` currently stores whole rupees (`monthly: 49`)
— fine for round numbers, wrong the moment an offer is ₹39.50. New money goes in
minor units per the golden rule; the plan includes a small adapter so the two
coexist rather than a risky rewrite of `plans.ts`.

**Read-only to clients**, like `promo_codes`: RLS grants select where the offer
is active and the user is in the segment. Prices must not be client-writable.

### Rendering (Settings → Billing)

- Original price **struck through**, discounted price beside it, `label` as a
  chip.
- **"Offer ends 12 Aug" — and a countdown only under 72 hours.** A permanent
  ticking clock is manipulative and, on a screen someone visits repeatedly,
  quickly becomes noise.
- **Server is authoritative.** The displayed price is a *quote*; checkout
  re-resolves the offer server-side. Otherwise a client with a tampered payload
  buys Pro for ₹1.
- If an offer expires between page load and checkout, the checkout fails with a
  plain message rather than silently charging full price.

### Admin

`/admin/offers` — list, create, deactivate. Mirrors `/admin/errors`'s shape.
Creating an offer needs no deploy, which is the point of a promotion.

---

## §4 — Loyalty segments

### Derived metrics (no new tracking)

Computed server-side, refreshed by a scheduled job (the `notify-dispatch` cron
already exists as a pattern):

- `tenure_days` — since `profiles.created_at`
- `active_days` — distinct days with a recorded transaction
- `transaction_count`, `longest_streak`
- `last_active_at` — max transaction date

Stored on a `user_metrics` table (migration `0050`), server-owned, never
client-writable. These are **derived from data the user already gave you**, which
is what makes them defensible.

### Segment rules

Extend `segments.rule` from flat trait equality to a small predicate set:

```json
{ "tenure_days": { "gte": 180 }, "active_days": { "gte": 60 } }
```

Evaluated **server-side only**. Evaluating segments on the client would leak the
entire targeting scheme to anyone who opens devtools.

### Session time — only if you take option (b) or (c) above

`session_seconds` becomes one more metric on `user_metrics`, fed by a heartbeat
while the tab is foregrounded. If it ships:

- **opt-in, with a real toggle** in Settings → Privacy;
- **one line added to the walkthrough**, because the current copy would otherwise
  be false;
- coarse buckets, not precise timings — segmentation needs "≥20 hours", never
  "you used the app at 03:12".

---

## Suggested order

1. **§1 Need/Greed** — self-contained, immediately useful, and generates the data
   §2 tier 2 needs.
2. **§2 tier 1** — insights that work for everyone today.
3. **§2 tier 2** — once tagging data exists.
4. **§4 derived metrics** → **§3 offers**. Offers without segments is a smaller,
   shippable first step (an offer for everyone).

## Verification

- `cd apps/web && ../../node_modules/.bin/tsc --noEmit`
- `node --test --experimental-strip-types packages/core/*/src/*.test.ts`
- `pglast` on 0048–0050; each re-runnable, schema-qualified, `drop policy if
  exists` before every `create policy`, **no cross-row constraints on synced
  tables**.
- i18n key-identity across en/hi/nl.
- Manual: swipe on a real touch device (drag gestures don't reproduce in
  DevTools — this has bitten twice already); keyboard-only review; an expired
  offer at checkout; a user in no segment sees list prices.

## Docs

`docs/features/reflect.md`, `docs/features/insights.md`, `docs/features/billing-and-entitlements.md`,
`docs/architecture/02-data-model.md` (three new tables + one column),
`docs/architecture/03-sync-and-offline.md`, and a dated `PROJECT_REFERENCE.md` entry.
