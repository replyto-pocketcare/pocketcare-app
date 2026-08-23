# Screen spec — Recurring

> **Source:** `apps/web/app/recurring/page.tsx` (218 lines), `apps/web/app/recurring/[direction]/page.tsx`
> (157 lines), `apps/web/src/recurring/engine.ts` (251 lines), `apps/web/src/recurring/summary.ts`
> (83 lines), `apps/web/src/cashflow/recurring.ts` (75 lines, read-model wrapper around the
> engine), `apps/web/src/cashflow/RecurringModal.tsx` (153 lines), `apps/web/app/subscriptions/page.tsx`
> (8 lines, redirect only). `apps/web/app/globals.css` (`.card`, `.chip`, `.btn`, `.eyebrow`,
> `.muted`, `.floating`), `tools/parity/tokens.spec.mjs`.
> Derived 2026-08-23 by source translation, not from screenshots.
>
> **Redesign context:** this whole area was rebuilt 2026-08-12 (`git log`: `3fe9181` "redesign
> around net cashflow and direction detail pages", `bddcdad` "savings move to Investments, groups
> removed"). The old **Planned Cashflow** page (`/cashflow`) and **recurring groups** are gone. Any
> earlier description of this feature — including `docs/plans/friends-tiles-and-cashflow-removal.md`,
> which is a *plan*, not as-built — is stale where it disagrees with this document; see §8.
>
> **Native targets:** `apps/android/app/src/main/java/com/sanvya/app/ui/recurring/` and
> `apps/ios/App/Recurring/`. Neither exists today — this is the first spec for this area on
> either platform.

## 1. Two routes, one feature

| Route | File | Purpose |
|---|---|---|
| `/recurring` | `app/recurring/page.tsx` | Net cashflow hub: net monthly number, income-vs-expense bar, two direction tiles, "due now" queue. |
| `/recurring/income`, `/recurring/expense` | `app/recurring/[direction]/page.tsx` | One direction's items: per-month total, category donut, item list. |

`/subscriptions` (`app/subscriptions/page.tsx`) is a bare `redirect("/recurring")` — a compatibility
shim for old links (dashboard tiles, insights CTAs, bookmarks) that predates this redesign and used
to point at Planned Cashflow. **Do not port a Subscriptions screen** — there isn't one; port the
redirect target only if native has an equivalent old deep link to retarget, otherwise skip it
entirely.

There is no `/recurring/saving` route and no `saving` tab. Recurring savings are SIPs — a transfer
into an investment account — created and stopped in Investments next to the holding they fund
(`src/investments/write.ts`), not here. The engine still posts `saving`-direction items (§4), and
one can surface in the "due now" queue on `/recurring`, but there is nothing to browse for it under
this feature. **Do not build a Savings tab or a third `DirectionCard`.**

## 2. `/recurring` — component tree, render order

```
<div class="fade-up">                                    gap 20 (raw literal, no token)
├── h1                                                     "Recurring payments & income" — h1/h1Compact (SanvyaType)
├── section.card                                           padding 18, gap 14 (raw literals)
│   ├── eyebrow "Net monthly cashflow"                     .eyebrow → SanvyaType.eyebrow / SanvyaColors.text3
│   ├── net value                                          clamp(28px,7vw,38px)/750, tabular-nums — SEE §3, no token
│   │     colour: --positive / --negative                  → SanvyaColors.positive / .negative
│   ├── CashflowBar                                        conditional: only when income+expense > 0
│   │     height 34, radius 10 (SanvyaRadius.row), border 1px --border
│   │     two flex segments, width = share of (expense+income)
│   │     fills: color-mix(--negative 18%) / color-mix(--positive 18%) — NO TOKEN, raw color-mix
│   │     divider: 2px solid --negative between the two segments
│   └── div (gap 10)
│       ├── DirectionCard → /recurring/income   ("Income",  sign "+", --positive)
│       └── DirectionCard → /recurring/expense  ("Expense", sign "−", --negative)
├── section.card  "Due now"                                conditional: due.length > 0
│   │   padding 16, gap 10, border-color --accent-soft, background --accent-ghost
│   └── one row per due item
│       ├── name + "due {date}" [+ formatted amount]        .muted, 12px
│       └── [Skip chip] [Record btn]                        .chip (skipOnce) / .btn small (postOnce)
└── RecurringModal                                          conditional: modal state set (add/edit)
```

`useRegisterAddAction` registers a **menu** "+" action for this page — two items, *Payment*
(`t("payment")`) and *Income* (`t("income")`), both opening `RecurringModal` directly (not the
shell's generic transaction/receipt default). This overrides `AppShell`'s default add action while
`/recurring` is mounted (see `docs/mobile/screen-specs/app-shell.md` §5) — port via the same
`useRegisterAddAction`-equivalent mechanism, whatever native calls it.

Deep links open the modal from query params, once, then `router.replace("/recurring")` to strip
them: `?add=income|payment[&name=&amount=<minor>&freq=][&convertFrom=]` or `?edit=<id>`. Native has
no query-string surface to replicate 1:1 — port the **intent**, not the URL shape: whatever mobile
uses to hand off a prefilled add (e.g. a suggestion chip, a notification tap) should open the same
modal pre-filled the same way, and an edit deep link should locate the item by id and open it in
edit mode. `edit` explicitly excludes `direction === "saving"` items (`items.find((i) => i.ruleId
=== editId && i.direction !== "saving")`) — a saving item is never edited from here even by deep
link.

### `DirectionCard`

`Link` (native: navigation, not a raw button) styled `.card press`, padding `14px 16px` (raw
literals), background `--surface-2` (`SanvyaColors.surface2`). Left: label 13.5px/650 + count line
(`"Nothing yet"` when 0, else `"{n} item{s} · per month"`) in `.muted`. Right: signed amount
19px/750 in the direction colour + a `›` chevron in `--text-3`.

### `CashflowBar`

Purely comparative — the two bars are drawn to scale **against each other** (share of the combined
total), not against a fixed maximum; the code comment is explicit about this being the point. Not
rendered at all when both income and expense are zero (`total <= 0`). Every dimension here (height
34, radius 10, border widths, font 12/700, padding "0 6px") is a literal in the `.tsx`'s inline
`style` object — only the two colours resolve to tokens.

## 3. `/recurring/[direction]` — component tree, render order

Slug resolution (`SLUGS`, `direction.ts` inline, not a separate file): URL segment `income` → stored
direction `income`; URL segment `expense` → stored direction `payment`. **This mapping exists
because the UI word ("Expense") and the DB word ("payment", tied to the check constraint from
migration 0060) disagree on purpose** — port the two-word mapping exactly, in one place, the way web
does; do not let the UI word leak into a query or the DB word leak into a route/label. An unknown
segment 404s (`notFound()`) — native should route-guard the same way (only `income`/`expense` valid,
no `saving`).

```
<div class="fade-up">                                     gap 18
├── header row                                              h1 "Income"/"Expense"  +  [+ Add] btn
├── section.card                                             padding 18, flex, gap 18, wrap
│   ├── eyebrow "Per month" + signed monthly total           clamp(26px,6.5vw,34px)/750, direction colour
│   └── PieChart (Recharts donut)                            132×132, conditional: categories.length > 1
│         innerRadius 38 / outerRadius 62, paddingAngle 2, strokeWidth 0
│         slice fill: colorForId(category.id) — deterministic hash, NOT a design token (§6)
│         Tooltip: --surface bg, 1px --border, radius 10, 12px
├── category legend chips                                    conditional: categories.length > 1
│     one .chip per category: 9px dot (colorForId) + name + share%
├── EITHER
│   ├── empty copy (muted, 13.5px, line-height 1.6)          summary.items.length === 0
│   OR
│   └── item list (gap 10)                                   one .card row per item
│         ├── name (ellipsised) + "{freq} · {category} · due {date}"
│         └── signed amount (direction colour) + KebabMenu
│               kebab items: Edit / Record now (postOnce) / Remove (danger, confirm dialog)
└── RecurringModal                                            conditional: modal state set
```

`useRegisterAddAction` registers a **button** action here (`Add {Income|Expense}`), distinct from
the hub's menu action — each direction page adds directly in its own direction, no picker.

Every list item's `KebabMenu` "Remove" goes through `useConfirm()` first
(`title: t("removeItemTitle","Remove this?")`, `message: it.name`) — a real confirmation dialog,
not a swipe-to-delete. Native must gate the destructive action behind an equivalent confirm
surface, not a bare tap.

The donut and legend are gated on `categories.length > 1` — **a single-category donut is
deliberately suppressed** ("a donut of a single category is decoration, not information", verbatim
from the source comment). Port the gate, not just the chart.

## 4. The recurring engine (`src/recurring/engine.ts`) — what the screens must not re-implement

`recurring_items` is one self-contained synced table (`packages/db/src/index.ts`, table
`recurring_items`) that replaced a `transaction_templates` + `recurring_rules` pair (migration
0060/0064) specifically so deleting a template could no longer delete a commitment. Every field the
posting engine needs — amount, account, category, description, note, payment method, labels,
transfer destination, split group — lives on this one row. **Native must model it as one entity,
not reconstruct a template/rule join.**

Columns read by the app (`RECURRING_COLUMNS`): `id, direction, name, amount, currency, frequency,
interval_count, next_due, account_id, to_account_id, category_id, auto_post, active,
alert_time_utc, description, note, payment_method, labels, split_group_id`. `amount` is **integer
minor units**, nullable (a due-item row with a null amount renders with no amount suffix on the
hub's "due now" line — see `page.tsx` line ~130). `direction` stores `income | expense | saving`
(the DB's word for what the UI calls "payment"/"expense" — §3). `frequency` is
`daily|weekly|monthly|yearly`; `interval_count` (default 1, nullable → treated as 1) multiplies it.

### `advance(dateStr, freq, n)`

Pure date arithmetic, no I/O: adds `n` periods to a `YYYY-MM-DD` string using native `Date`
month/day/year arithmetic (not calendar-aware beyond what `Date.setMonth`/`setFullYear` already do
— e.g. advancing "Jan 31" by one month yields whatever JS's own month-rollover gives). Port this
function's exact semantics, including its rollover behaviour, since `next_due` values must match
between the engine (which advances them) and any native calculation that predicts a future
occurrence for display.

### `materialize(item, occurredAtIso)`

Turns one due occurrence into a **real transaction**. Order of operations:

1. **Split path** — if `item.split_group_id` and `item.account_id` are both set, look up the split
   group's current members. If ≥2 members remain, post via `createSplitExpense` (equal split, the
   current user pays the full amount from `item.account_id`) and return — this is the *only* branch
   taken; it does not also post a plain transaction. If the group has fewer than 2 members (everyone
   else left), it silently falls through to the non-split branches below instead of erroring.
2. **Transfer path** — `typeForDirection(direction) === "transfer"` (i.e. `direction === "saving"`)
   **and** both `to_account_id` and `account_id` are set → post a `transfer` transaction.
3. **Income/expense path** — otherwise, if `item.account_id` is set → post an `income` or `expense`
   transaction carrying category, description, note, payment method and parsed `labels` (comma-split,
   trimmed, empty entries dropped).
4. **No-op** — if none of the above conditions hold (e.g. a transfer item missing `to_account_id`,
   or any item with no `account_id`), `materialize` returns having posted **nothing**, without
   throwing. The UI's own creation form always requires an account (`canSave` needs `accountId`), so
   this path is not reachable through normal use — but the engine does not defend against it, and a
   caller that skips the form (a future automation, a bug in a migration) can hit it silently. Flag
   this if native adds any other creation path for `recurring_items`; do not assume the engine will
   catch a malformed row.

### `runRecurring()` — the one call the shell makes at launch

Selects every `active=1, auto_post=1, deleted_at IS NULL` row whose `next_due <= today`, and for
each one **loops, materialising and advancing until caught up** (guarded at 24 iterations per item,
so a badly stale daily item cannot loop forever). On a `materialize` failure (its `try` swallows any
thrown error — e.g. an overdraft-blocked auto-post) it `break`s out of that item's loop and leaves
`next_due` where it is, so the item still shows as due next run, and **moves on to the next item**
rather than stalling the whole batch. This is the exact call `AppShell.tsx` makes 2.5s after auth,
once per launch, immediately before `runLoanAutoPost()` (see `app-shell.md` §8) — **native must call
it at the same point in the same order**, not from inside either recurring screen. The screens never
call `runRecurring()` themselves.

### `postOnce(id)` / `skipOnce(id)` — user-driven single occurrence

`postOnce` materialises the item's current `next_due` occurrence immediately and advances
`next_due`+`last_generated` by one period — this is what "Record" (hub) and "Record now" (direction
page kebab) call, for **both** auto-post and confirm-only items. `skipOnce` **only** advances
`next_due`; nothing is posted. Both are one occurrence at a time — neither catches up multiple
missed periods the way `runRecurring` does. **The screens must call these, not reimplement the
advance-and-post pairing** — the ordering (materialize, then advance) matters for correctness if a
write fails partway.

### `useDueItems()` — the hub's "Due now" queue

Items that are `active=1, auto_post=0, next_due <= today` — i.e. exactly the ones that do **not**
post themselves and are waiting for a human tap. This deliberately includes `saving`-direction items
(SIPs with auto-post off) even though they have no home under `/recurring/income|expense` — see the
page-level doc comment quoted in §1. Native's due-item query must not filter direction here even
though the two list screens do.

### Writes: `createRecurring` / `updateRecurring` / `removeRecurring`

`toRow()` converts the UI's **major-unit** amount to **minor units** with a bare `Math.round(amount
* 100)` — it does **not** call `minorUnits(currency)` from `@sanvya/money` the way the money
formatter does elsewhere in the app. This is correct only for 2-decimal currencies; for a
zero-decimal currency (JPY) or a 3-decimal one (BHD) it silently produces the wrong minor-unit value.
**This is a latent bug in web, not a pattern to imitate.** Match it for parity if native must byte-
for-byte agree with web's stored values today, but flag it — the correct fix (using
`minorUnits(currency)`) belongs in `@sanvya/money`-adjacent shared code, applied to both platforms
at once, not invented independently on one native app.

`removeRecurring` is a soft delete (`deleted_at`), never a hard delete — standard for this codebase.

## 5. Money and currency

Every amount on both screens is integer minor units end to end: `RecurringRow.amount`,
`RecurringItem.amount`, `DueItem.amount`, `monthlyEquivalent()`'s input and output. `monthlyEquivalent`
(`packages/core/finance/src/index.ts`) is `Math.round(amount * PERIODS_PER_YEAR[period] / 12)` with
`PERIODS_PER_YEAR = { daily: 365, weekly: 52, monthly: 12, yearly: 1 }` — **the single normalisation
point that makes a weekly bill and a yearly subscription comparable**; nothing on these screens sums
raw amounts across different frequencies, and native must route every "per month" figure through the
equivalent of this function, not hand-roll `/12` or `*52/12` inline. `summary.ts`'s own doc comment
says this outright. Currency: each item carries its own `currency`; display falls back to
`base` (the account's base currency, `useBaseCurrency()`) only when an item's `currency` is empty.
`useMoneyFmt()` also enforces the sitewide "hide amounts" privacy toggle — every rendered amount on
both screens must stay masked when that's on; there is no screen-local override.

## 6. Colour

- `colorForId(categoryId)` (`src/colors.ts`) — a **deterministic hash into an 18-colour fixed
  palette**, used for the donut slices and legend dots. This is not a design token; it's a
  content-driven palette independent of light/dark theme (same 18 hex values either way). Port the
  palette and the hash (`h = (h*31 + charCode) >>> 0`, then `palette[h % 18]`) verbatim so a given
  category id produces the same colour on every platform.
- Everything else colour-related on these two screens resolves to a `SanvyaColors` token:
  `--positive`, `--negative`, `--accent-soft`, `--accent-ghost`, `--surface-2`, `--text-2`,
  `--text-3`, `--border`, `--surface`.
- `CashflowBar`'s segment fills use `color-mix(in srgb, var(--negative) 18%, transparent)` (and the
  positive equivalent) — a runtime colour blend, **no equivalent generated token exists**. Compute
  the same 18%-opacity tint from `SanvyaColors.negative`/`.positive` directly (e.g.
  `color.copy(alpha = 0.18f)` on Android, `.opacity(0.18)` on iOS) rather than inventing a new named
  token for one bar.

## 7. Type and spacing — token vs. literal, called out explicitly

Per the task brief: **most values on these two screens are raw literals in the `.tsx`, not
tokens.** Unlike the shell (`app-shell.md`), which is built entirely from CSS classes the token
generator asserts against, `/recurring` and `/recurring/[direction]` are written almost entirely with
inline `style={{ }}` objects. Only what maps to a CSS class or a `--custom-property` is a token,
listed here; everything else is a bare number, listed so it is not mistaken for one.

**Resolves to a token:**
| Web | Token |
|---|---|
| `h1` | `SanvyaType.h1` / `.h1Compact` (`26`/`22`, weight 700, tracking `-0.02em`) |
| `.eyebrow` | `SanvyaType.eyebrow` (`11`/600, tracking `0.09em`, uppercase) + `SanvyaColors.text3` |
| `.card` | `SanvyaCard` (surface, 1px border, `SanvyaRadius.radiusLg` = 24, `shadow`) |
| `.chip` | `SanvyaChip` (pill, `SanvyaType.chip` = 14/400) |
| `.btn` (small "Record") | `SanvyaButton` (pill, `SanvyaType.button` = 15/600) |
| `.muted` | `SanvyaColors.text2` |
| `CashflowBar` / legend-dot radius (10px) | `SanvyaRadius.row` |
| `.tabular-nums` | tabular figure variant (font-feature on both platforms) |
| `press`/press-scale on `.card`-as-link | `SanvyaMotion.liftPress` (0.985 / 80ms) per `app-shell.md`'s `a.card` note |
| `fade-up` page transition | `SanvyaMotion.fadeUp` (400ms, translateY 8) |

**Raw literal, no token — hand these numbers to native exactly as written:**
- Page gap `20` (hub) / `18` (direction page); card `padding: 18`; card inner `gap: 14`.
- Net-cashflow value: `clamp(28px, 7vw, 38px)`, weight `750`, `letterSpacing: -0.02em`. Per-direction
  monthly value: `clamp(26px, 6.5vw, 34px)`, weight `750`. Neither is `SanvyaType.h1` — bespoke
  clamp-based sizing with no fixed-px equivalent; pick a fixed size appropriate to the device class
  (native has no viewport-relative unit here) rather than inventing a new shared type style for one
  number.
- `DirectionCard`: padding `14px 16px`, label `13.5px/650`, count line `12px`, amount `19px/750`.
- "Due now" section: `padding: 16`, `gap: 10`, row text `14px`/`12px`.
- `CashflowBar`: height `34`, radius `10` (→ `SanvyaRadius.row`, see table above), border `1px`,
  divider `2px`, value text `12px/700`, padding `"0 6px"`.
- Direction page: header row `gap: 12`; stat card `padding: 18`, `gap: 18`; donut `132×132`,
  `innerRadius 38`/`outerRadius 62`, `paddingAngle 2`; legend chip dot `9×9`; item row `padding:
  "12px 14px"`, name `14px/650`, meta `12px`, amount `15px/700`; empty-state copy `13.5px`, line-height
  `1.6`.
- `KebabMenu`: trigger `.chip` at `padding: 8`, icon `18`; portalled menu `168px` wide, item padding
  `"11px 14px"`, `14px` text, `1px --border` row divider, `10px` radius, `--shadow-lg`.

## 8. What web does that this feature deliberately does NOT do (and why)

- **No groups.** `recurring_groups` and every `groupId`/group-card affordance from the pre-redesign
  UI (and from the *plan* doc, which proposed keeping groups) are gone from the shipped code —
  `recurring_items` has no `group_id` column at all. Items are organised by direction and category
  only. Do not port a group concept; there is nothing to port it from.
- **No Savings tab/direction.** See §1 — SIPs live in Investments.
- **Subscriptions were *not* folded into `recurring_items`, despite the plan.** The plan document
  (`docs/plans/friends-tiles-and-cashflow-removal.md`) proposed "Subscriptions are just
  `recurring_items` in the Subscription group." As shipped, `subscriptions` remains its **own,
  unrelated synced table**, still read by the dashboard's Subscriptions tile
  (`src/dashboard/tiles.tsx`), Insights (`src/insights/useInsightStack.ts`), and the assistant
  (`src/assistant/summary.ts`, `src/assistant/tools.ts`) — none of which query `recurring_items`.
  `RecurringModal`'s preset chips include the *word* "Subscription" as a payment-name suggestion
  (`PRESETS.payment`), which is cosmetic only and creates an ordinary `recurring_items` expense row,
  not a `subscriptions` row. **Do not build one native model that conflates these two tables** — a
  native Subscriptions surface (if ported at all) is a separate, smaller task reading the
  `subscriptions` table, out of scope for this spec.
- **`⌘K`/keyboard shortcuts, hover states, desktop drag** — none of these screens have any; nothing
  to explicitly exclude here beyond the general shell guidance in `app-shell.md` §9.
- **The engine's per-item try/catch swallow in `runRecurring`** (§4) is deliberate resilience, not a
  bug to "fix" into a hard failure on native — one item's overdraft block must not stop every other
  item's auto-post that same launch.

## 9. Data access — hooks/queries and native repository status

| Web read/write | Query / call | Native repository today |
|---|---|---|
| List active items | `useRecurringItems()` → `SELECT … FROM recurring_items WHERE deleted_at IS NULL AND active=1 ORDER BY next_due` | **None.** No `RecurringRepository` exists on either platform (`apps/android/data/.../repository/`, `apps/ios/Data/Sources/Data/` — full listing checked, nothing recurring-related). |
| Due-now queue | `useDueItems()` → same table, `auto_post=0 AND next_due <= today` | None. |
| Category names (for the donut/legend) | `useCategoryNames()` → `SELECT id, name FROM categories WHERE deleted_at IS NULL` | Category reads exist elsewhere (Budgets, Transactions repositories) — reuse an existing categories query, don't add a new one. |
| Accounts / categories for the modal | two `useQuery`s in `RecurringModal` (`accounts` filtered to non-investment real accounts; `categories` filtered to expense-kind for payments) | Account/category list reads exist elsewhere (`LedgerRepository` equivalents) — reuse, don't duplicate. |
| Create / update / soft-delete | `createRecurring`/`updateRecurring`/`removeRecurring` → `insertRow`/`updateRow`/`softDelete("recurring_items", …)` | None. |
| Post one occurrence | `postOnce(id)` → `materialize()` + `updateRow` | None — and `materialize()`'s own transaction-posting step *can* reuse `LedgerRepository.createTransaction` (Android: `apps/android/data/.../LedgerRepository.kt:562`; iOS mirrors it), which already exists and already validates overdraft/transfer preconditions the same way `materialize` expects. |
| Split-group posting inside `materialize` | `createSplitExpense(...)` | Exists on both platforms (`SplitsRepository.createSplitExpense`) — reusable as-is. |
| Skip one occurrence | `skipOnce(id)` → `updateRow` (next_due only) | None. |
| Batch catch-up at launch | `runRecurring()` | None — this is the biggest gap: the whole engine (`advance`, `materialize`, `runRecurring`, `postOnce`, `skipOnce`) needs a native port, most naturally as a `RecurringRepository` + a small engine module, called once at launch the same way `AppShell.tsx` calls it (see `app-shell.md` §8's "Recurring materialisation" row, which already documents the launch-timing contract this repository must satisfy). |

**Net: this is a data-layer task before it is a UI task.** Both screens are unbuildable natively
until `recurring_items` has CRUD + due-item queries + the engine functions on both platforms. The
`recurring_items` table itself is already in `AppSchema` (`packages/db/src/index.ts`) and synced
(`packages/db/sync-streams.yaml`, `user_data` stream) — the schema exists on-device already; only
the repository/engine code is missing.

## 10. i18n

Split across **two namespaces**, which native should be aware of even though it need not reproduce
the split:

- **`recurring`** (`packages/core/i18n/src/locales/recurring/{en,hi,nl}.json`) — used by both
  `page.tsx` and `[direction]/page.tsx` via `useTranslation("recurring")`.
- **`cashflow`** (`packages/core/i18n/src/locales/cashflow/{en,hi,nl}.json`) — used by
  `RecurringModal.tsx` via `useTranslation("cashflow")`. This is the **old Planned Cashflow
  namespace**, kept alive only because the modal's field labels (`dirLabel`, `depositInto`,
  `payFrom`, `selectAccount`, `categoryOptional`, `firstDue`, `postAuto`, `modalAdd`/`modalEdit`,
  etc.) happened to still fit after the redesign — a pragmatic reuse, not a design decision to
  imitate. Its `title`/`intro`/`subtitleLink` keys ("Planned Cashflow", "Quick add · templates", …)
  are **dead** — no longer rendered anywhere — since the page that used them was deleted.

**The `recurring` namespace itself is stale and incomplete relative to the current `.tsx`.** It
still carries copy from the old Planned-Cashflow-flavoured, group-based UI (`subtitleLink: "Planned
Cashflow"`, `groupDelete*`, `itemCount_one/other`, `emptyIncome`/`emptyPayment`/`emptySaving` split
by direction rather than the current single `emptyDirection`). Keys the *current* code actually
calls but that **do not exist** in `recurring/en.json` (react-i18next silently falls back to the
hardcoded default string passed as the second `t()` argument, so English still renders correctly,
but hi/nl users get the English fallback with no translation at all):

- `netMonthly` — falls back to `"Net monthly cashflow"`.
- `emptyDirection` — falls back to `"Nothing recurring here yet. Add one and it'll post itself on schedule."`.
- `removeItemTitle` — falls back to `"Remove this?"`.
- `perMonth` — this one **does** exist, but as `"/mo"`; the direction page's fallback string
  `"Per month"` is therefore never shown in English either — the actual rendered label is `"/mo"`.

Android's `S.kt`/`R.string.recurring_*` and iOS's generated string catalog already mirror the
**stale** JSON (confirmed: `S.kt` has `recurring_group_delete`, `recurring_empty_income`, etc., but
no `recurring_net_monthly`/`recurring_empty_direction`/`recurring_remove_item_title` keys). **Fix
the source JSON first** (add the missing keys with real translations, retire the group/per-direction-
empty keys the current UI no longer calls), then regenerate the native string catalogs — don't
hand-author native-only strings that would drift from web's own (eventually-corrected) copy.

## 11. States

| State | Hub (`/recurring`) | Direction page |
|---|---|---|
| **Loading** | No explicit skeleton in the source — `useQuery` returns `data = []` synchronously until PowerSync resolves, so the page renders with `summary.net = 0`, no bar, empty direction cards ("Nothing yet") for one frame. Native's equivalent local-first read behaves the same way once wired — do not add a spinner that doesn't exist on web. | Same — `summary.items = []`, no chart, falls into the empty-copy branch until the query resolves. |
| **Empty** | Both `DirectionCard`s show "Nothing yet"; `CashflowBar` doesn't render (`total <= 0`); "Due now" section doesn't render (`due.length === 0`). | `summary.categories.length <= 1` hides chart+legend; `summary.items.length === 0` shows the muted empty copy (`emptyDirection`). |
| **Error** | None handled explicitly — no error boundary, no toast, on either screen. A failed `postOnce`/`skipOnce`/`createRecurring` write surfaces however the app's generic write-error path does (shell-level, not screen-level — see `app-shell.md`'s `SyncProblemsBanner`/failed-writes handling for the mechanism these ultimately feed). Do not invent a screen-local error state that doesn't exist on web. | Same. |
| **Populated** | Net value + bar + two direction cards + optional due-now queue, as specified above. | Stat + optional donut/legend + item list. |
| **Premium gating** | **None on these two screens.** No `useEntitlement` call anywhere in `page.tsx`, `[direction]/page.tsx`, `RecurringModal.tsx`, or `engine.ts`. Recurring income/expense tracking is not gated by plan tier — unlike, e.g., the shell's default "+" menu locking receipt scanning (`app-shell.md` §5). Do not add a lock badge here; there is nothing in the source to hang one off. |

## 12. Done-when

- [ ] Native `RecurringRepository` (or equivalent) exists on both platforms with: list active items,
      due-items query, create/update/soft-delete, `postOnce`, `skipOnce`, and a `runRecurring()`
      batch catch-up — ported from `engine.ts` line-for-line for `advance()`'s date rollover and
      `runRecurring()`'s 24-iteration-per-item guard and per-item swallow-and-continue.
- [ ] `runRecurring()` is called once per launch, 2.5s after auth, immediately before the loan
      auto-post call — from the shell, not from either recurring screen (matches `app-shell.md` §8).
- [ ] Hub renders net monthly cashflow, the to-scale income/expense bar (hidden when both are zero),
      and the two direction tiles with correct counts and per-month totals via `monthlyEquivalent`.
- [ ] "Due now" queue includes `saving`-direction items with auto-post off, even though they have no
      browsable list under either direction page.
- [ ] Direction pages resolve `income → income` / `expense → payment` and reject any other segment;
      donut+legend are suppressed at ≤1 category; empty-direction copy matches (once the i18n key
      exists).
- [ ] `createRecurring`'s amount conversion either matches web's `×100` behaviour for parity, or is
      fixed on both web and native together via `minorUnits(currency)` — not fixed on native alone.
- [ ] No Savings tab, no group concept, no Subscriptions screen sourced from `recurring_items`.
- [ ] `recurring`/`cashflow` locale JSON gets the three missing keys (`netMonthly`,
      `emptyDirection`, `removeItemTitle`) before native string catalogs are regenerated from them.
- [ ] Every colour on these screens is a `SanvyaColors` token or the `colorForId` hash palette;
      every literal pixel value in §7's second table is hand-copied, not guessed from a token that
      doesn't exist for it.
- [ ] Remove confirmation is a real confirm dialog on both platforms, gated the same as web's
      `useConfirm()`.
- [ ] CI green on both platforms.
