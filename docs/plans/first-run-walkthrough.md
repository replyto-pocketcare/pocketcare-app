# First-run walkthrough — implementation plan

**Status:** plan, not yet implemented · **Date:** 2026-07-29

## Why this exists

A real 60+ user signed up, landed on the dashboard, and didn't know what to do.
Worse, they believed "add an account" meant **linking their real bank account** —
which they did not want to do. They didn't proceed.

Two things failed there, and only one of them is an onboarding problem:

1. **Nobody told them what the app is.** They never learned that Sanvya is a
   manual money diary, so "account" was read with the only meaning they had for
   it — a bank login.
2. **The one thing that would have reassured them was never said.** Nowhere does
   the app state that it does not, and cannot, connect to a bank.

## Why the existing checklist didn't catch it

`src/onboarding/GettingStarted.tsx` already exists and already tries to explain
each step's *why*. It failed for four reasons worth naming, because the new
design has to avoid all of them:

- **It's a card among cards**, below the net-worth hero. Easy to scroll past.
- **It uses the exact word that caused the fear** — "Add your first account" —
  with no reassurance attached.
- **It links away.** The explanation stays on the dashboard while the user lands
  on `/accounts/new`, a form headed "New account" offering *Savings / Current /
  Credit card / Demat*. That page reads like bank onboarding, so the fear
  returns at precisely the moment the explanation is gone.
- **It's permanently dismissible** (and hidden for Pro), so one stray tap
  removes the only guidance in the product.

## Decisions taken

| Decision | Choice |
|---|---|
| Terminology | **Keep "Account".** Fix the explanation instead. |
| Interaction | **Inline** — the first account is created inside the dialog. |
| Escapability | **Skippable, but returns** until a first account exists. |
| Existing UI | **Replaces** the `GettingStarted` card. Pre-signup `/onboarding` slides stay. |

### The framing that does the real work

Manual entry is **not a limitation to apologise for — it's the product**, and
saying so converts the scariest fact into the strongest pitch:

> You'll type in your spends yourself. That's deliberate. The few seconds it
> takes is what makes you *notice* where your money goes — and noticing is the
> whole point.

Every step reuses that frame. Three claims appear early, in plain words:

1. Sanvya is **not connected to your bank** and never asks for a bank login,
   card number or OTP.
2. **Nothing is tracked automatically.** You write things down.
3. That's **on purpose**, to build the habit of being mindful with money.

A note on naming, since it was considered and rejected: "Wallet" and "Passbook"
are both *worse* than "Account" for this audience — in India a wallet is
Paytm/PhonePe (so it still implies linking) and a passbook is issued by a bank.
Keeping "Account" plus an explicit disclaimer is the sound call.

---

## The walkthrough

**Two parts, with a real exit between them.** This matters: the person who
prompted this work found the app overwhelming, so making onboarding longer for
*them* would be the wrong response to their feedback.

- **Part A — Set up (steps 1–4).** The essential path. Ends with a genuine
  **Finish**.
- **Part B — What else it does (steps 5–7).** Opt-in, reached by "See what else
  it does →" on step 4. Skippable at every point.

A progress indicator ("Step 2 of 4", then "1 of 3") so each part is visibly
finite — an open-ended dialog is its own source of anxiety.

### Step 1 — What this app is

> **Welcome to Sanvya**
>
> Sanvya is your private money diary. You write down what you spend and
> earn, and it shows you where your money is actually going.
>
> **It is not connected to your bank.** We never ask for your bank login, card
> number or OTP, and we can't see your bank at all.
>
> Nothing is tracked automatically — you'll type your spends in yourself. That's
> deliberate: the few seconds it takes is what makes you notice where your money
> goes, and noticing is the whole point.

Actions: **Show me how** · *I'll look around myself*

### Step 2 — Add your first account (inline)

> **Where do you keep your money?**
>
> An "account" here is just **your own note** of somewhere money sits — your
> bank, the cash in your purse, a credit card. It's a name and a number you
> type. Nothing is linked to the real bank.
>
> Start with the one you use most. You can add others later.

Fields — only two:

- **Give it a name** · placeholder `HDFC savings` / `Cash in purse`
- **Roughly how much is in it now?** · helper: *An approximate number is fine —
  you can correct it any time.*

Everything else on the real form (type, currency, colour, net-worth toggle,
overdraft, credit-card cycle) is defaulted: `type: savings`, the profile's base
currency, an assigned colour, included in net worth. All editable later at
`/accounts/<id>/edit`. **This is the crux of the fix** — the full form is what
reads as bank-linking, so a nervous first-timer never sees it.

Writes via the existing `repos.accounts.create` + `setOpeningBalance`, so there
is no second write path to keep correct.

Actions: **Save** · *Skip this for now*

### Step 3 — Record one spend (inline)

> **Now write down one thing you spent**
>
> Think of the last thing you paid for — tea, groceries, a bill.
>
> When you record a spend, Sanvya subtracts it from that account, so the
> number stays true to real life. **This is the one habit that matters** —
> everything else in the app is built from it.

Fields: **What was it for** · **How much** · (account preselected when there's
only one). Uses `repositories.transactions.create`.

Actions: **Save** · *Skip this for now*

### Step 4 — Where to look next

> **That's it — you're set up**

Three destinations, each one line, with its real nav icon so the mapping is
obvious:

- **Dashboard** — your money at a glance.
- **Transactions** — everything you've written down.
- **Budgets** — set a monthly limit and Sanvya tells you when to slow down.

Closing reassurance:

> Your data is yours. It stays on your device and in your private account —
> we don't share it, and nobody else can see it.

Actions: **Finish** · *See what else it does →*

---

## Part B — what else it does (opt-in)

### Step 5 — Insights

> **Sanvya reads your entries back to you**
>
> Once you've written a few things down, Sanvya starts pointing things out
> on its own: which category is eating the most, a month that's running hotter
> than the last, a subscription you may have forgotten.
>
> You don't have to build a single chart or spreadsheet. The more you write
> down, the more it has to tell you.

Icon: `insights`. One real screenshot-free example line, e.g. *"You've spent 32%
more on eating out this month than last."*

### Step 6 — Ask Sanvya

> **Or just ask, in your own words**
>
> Type or say things like *"how much did I spend on groceries last month?"* or
> *"can I afford ₹15,000 this week?"* — and it answers from your own entries.
>
> No menus to learn. If you'd rather ask a question than hunt for a screen,
> this is the shortcut.

Icon: `auto_awesome`. Worth saying plainly: it only ever reads **your** data, and
nothing is sent anywhere until you ask it something.

### Step 7 — Your free trial (and what comes after)

**This step must lead with the trial, not with a price.** There is already a
14-day trial with everything unlocked (`useEntitlement().isTrial`), so asking a
brand-new user for money at minute one would be both wrong and inaccurate.

For a **registered user on trial**:

> **Everything is already unlocked for 14 days**
>
> Insights, Ask Sanvya and Statements are on right now — no card, nothing to
> set up. Use them and see whether they're worth it to you.
>
> After 14 days the basics stay free forever: your accounts, transactions,
> budgets and search. If you want to keep the extras, plans start at ₹49/month.

Both plans, from `src/billing/plans.ts` so nothing is hard-coded:

| | Lite | Pro |
|---|---|---|
| Price | ₹49/mo · ₹499/yr | ₹99/mo · ₹999/yr |
| Ask Sanvya | 50 prompts/month | 200 prompts/month |
| Everything else | unlocked | unlocked |

Actions: **Done** (primary) · *See plans* → `/settings`

For a **guest**, the trial doesn't apply (`TrialNotice` excludes guests), so this
step says something different and more useful:

> **You're using Sanvya as a guest**
>
> Your entries live only on this device, and guest data is deleted after a few
> days. Create a free account to keep it — and you'll get 14 days with
> everything unlocked.

Actions: **Create a free account** → `/login` · *Later*

---

## ⚠️ Collision to resolve: the trial welcome modal

`src/ui/TrialNotice.tsx` **already shows a one-time modal** on first login —
"Your 14-day free trial is live" — keyed on
`localStorage["sanvya:trial-welcome:<email>"]`. Left alone, a new user gets
that dialog *and* the walkthrough, stacked, saying overlapping things. That is
worse than either alone.

Resolution: the walkthrough **absorbs** it. When the walkthrough runs, set that
same `seenKey` so the welcome modal never opens; step 7 is now the place the
trial is explained. The **persistent countdown banner stays** — it does a
different job (a running reminder), and it's the thing that converts.

This is also why step 7 exists in the shape it does rather than as a pricing
page: it's replacing a trial-welcome dialog, so it should read like good news,
not an invoice.

---

## Behaviour

**Show when** all of: signed in (`useAuthStatus()` is `user` or `guest`), the
first sync has completed (`useInitialSyncPending()` is false — otherwise a
returning user's accounts haven't arrived yet and they'd be told to start over),
zero real accounts, and not completed before.

**Skippable, returns.** "I'll look around myself" closes it for the session
(`sessionStorage`) and it reappears on the next dashboard visit while there are
still no accounts. Completing step 2 or finishing sets
`localStorage.walkthroughDone = "1"`, after which it never returns.

Deliberately **not** blocking: trapping someone who wants to look around first
is a good way to lose them. Deliberately **not** permanently dismissible: that's
the behaviour that failed this user.

**Race to avoid:** the existing `GettingStarted` had a documented flash bug —
counts start empty, so it rendered, then vanished. Same trap here. Gate on
`isLoading` *and* the sync flag, and read the done-flag synchronously in
`useState` initialiser so a returning user never sees a frame of it.

## Also fix the real add-account form

The walkthrough only covers the first account. Anyone adding a second one still
meets the scary form, so `/accounts/new` gets a permanent, quiet line under the
heading:

> Nothing here connects to your bank. You're just naming a place your money
> sits and typing in the amount yourself.

Cheap, and it removes the fear at the point it actually occurs.

## Accessibility — this is for a 60+ reader

Not decoration; it's the requirement that prompted the work.

- **Type size**: body copy at 15–16px in this dialog, not the app's 12.5–13px
  muted default. No `--text-2` grey for anything load-bearing — contrast at
  least 4.5:1.
- **Tap targets** ≥ 44px, buttons full-width and stacked on mobile.
- **One idea per paragraph**, short sentences, no jargon ("net worth",
  "ledger", "minor units" never appear).
- **The primary action is always the obvious one**; skip links are plain text,
  not competing buttons.
- **`src/ui/Modal.tsx` gaps to close first**: it has no `role="dialog"`, no
  `aria-modal`, no Escape handler and no focus trap. A keyboard or screen-reader
  user can currently tab out of any dialog in the app behind the scrim. Fixing
  it in the shared component benefits every dialog — flagging it because it
  touches more than this feature.
- Honours `prefers-reduced-motion` (the shared `Modal` animates via
  framer-motion).

## Files

- `src/onboarding/Walkthrough.tsx` — **new**, the dialog + steps.
- `src/onboarding/useWalkthrough.ts` — **new**, trigger/dismiss/complete state,
  and setting `TrialNotice`'s `seenKey` so the welcome modal can't double up.
- `app/page.tsx` — mount it; remove the `<GettingStarted />` mount.
- `src/onboarding/GettingStarted.tsx` — **delete** (superseded).
- `src/ui/TrialNotice.tsx` — keep the banner; export the `seenKey` helper so the
  walkthrough can suppress the welcome modal instead of duplicating its logic.
- `app/accounts/new/page.tsx` — the reassurance line.
- `src/billing/plans.ts` — **read**, never duplicated. Step 7 renders `PLANS`
  and `price()` so onboarding copy can't drift from Settings.
- `packages/core/i18n/src/locales/onboarding/{en,hi,nl}.json` — extend the
  existing namespace; keys must stay identical across all three.

**No migration. No new dependency.** Nothing here touches the schema, so
`pnpm-lock.yaml` is untouched and CI stays green.

## i18n

Extend the existing `onboarding` namespace. The copy above is the `en` source of
truth. **hi/nl need a native-speaker review before release** — more than usual
here: this copy exists to defuse a *specific cultural fear*, and a
machine-flavoured translation of "we are not connected to your bank" is exactly
the sentence you cannot afford to get slightly wrong.

## Verification

1. `cd apps/web && ../../node_modules/.bin/tsc --noEmit`
2. `node --test --experimental-strip-types packages/core/*/src/*.test.ts`
3. i18n key-identity check across en/hi/nl (scripted).
4. Manual:
   - fresh signup → dialog appears; complete all four steps → account and
     transaction exist, dialog never returns;
   - skip at step 1 → gone for the session, back on the next visit;
   - **returning user with accounts sees nothing, and no flash** — reload
     repeatedly on a slow connection and watch for a single frame of it;
   - guest account: steps 1–6 identical, step 7 shows the create-an-account
     variant rather than the trial (guests get no trial);
   - **the trial welcome modal does NOT also appear** — this is the regression
     most likely to slip through, since it's keyed per-email in localStorage and
     won't reproduce on an account you've already logged into once;
   - a paid user who somehow has no accounts sees step 7 reflect their real
     plan, not a pitch;
   - keyboard-only: tab through, Escape closes, focus doesn't escape the scrim;
   - 200% browser zoom and a 320px-wide viewport, since the audience zooms.
5. Read the whole thing aloud. If a sentence needs re-reading, rewrite it.

## Docs

- `docs/features/onboarding-and-identity.md` — the new flow, why the checklist
  was replaced, and the three claims the copy must always make.
- `PROJECT_REFERENCE.md` — dated change-log entry.

## Deliberate non-goals

- **No product tour overlay** (spotlight/coach marks on real UI). It fights
  every layout change, and this user needed *what the app is*, not *where the
  buttons are*.
- **No video or animation.** Text they can re-read at their own pace is better
  for this reader.
- **No renaming of "Account"** — decided against; see above.
- **No hard paywall or pricing page.** Part B is opt-in and step 7 leads with
  the trial. The user who prompted this work bounced from *confusion*, and a
  payment ask at minute one addresses neither confusion nor distrust.
- **Not gating the rest of the app.** The dashboard stays usable underneath.
