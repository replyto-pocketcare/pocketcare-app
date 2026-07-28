# UI redesign — Insights, Recurring groups, templates, dividers, nav icons

**Status:** plan, not yet implemented · **Date:** 2026-07-28

Six independent workstreams. Only §3 touches the database; everything else is
presentational or client-side. Ship order below is dependency-ordered, but §1,
§4, §5 and §6 can each land alone.

---

## 1. `/insights` — full-page card feed, nothing else

**Today:** `app/insights/page.tsx` renders `h1` + a "Statements" link +
`DividendPanel` + `ProjectionPanel` + `<InsightFeed />`. The feed already sizes
itself with `useFillHeight()` (`100dvh − top`) and cancels the shell's bottom
FAB padding with `marginBottom: -88`.

**Change**

- Strip the header, the statements link, and both market panels. The page body
  becomes `<InsightFeed />` alone. The premium gate stays — it is the
  entitlement boundary, not chrome.
- Make it genuinely full-bleed. `.shell-main` pads `32px 40px` (desktop) /
  `16px 16px 96px` (mobile). Add to `globals.css`:

  ```css
  body[data-fullbleed="true"] .shell-main { padding: 0 !important; max-width: none; }
  ```

  and set `document.body.dataset.fullbleed` from an effect in the insights page,
  cleared on unmount. This mirrors the existing `data-dash-edit` /
  `data-dash-empty` body-dataset pattern already used to hide the FAB.
- With padding at 0, delete the `marginBottom: -88` hack in `InsightFeed.tsx` —
  it exists only to cancel that padding.
- Replace the empty-state `✦` glyph with a Material Symbol (see §6).

**Deliberately kept:** `OfflineBanner`, `SyncProblemsBanner` and the sync
message live in the shell above `children`. They are safety-critical — a silent
sync failure is the exact class of bug the fault-tolerance work exists to
surface. Say the word if you want them suppressed here too.

**Files:** `app/insights/page.tsx`, `app/globals.css`, `src/ui/feed/InsightFeed.tsx`

---

## 2. Dividends + Projections → insight cards

You chose "convert into insight cards". One honest consequence: **a card is a
static visual, and `ProjectionPanel` is interactive** (growth %, monthly
contribution, years, reinvest toggle). Converting it verbatim loses those
controls. So:

- **Card** = the summary/hero, computed from fixed default assumptions
  (7 % growth, current contributions, 15 y), CTA → `/investments`.
- **Interactive panel** moves to `/investments`, where holdings already live.

Nothing is lost, and `/insights` stays a pure feed.

**Change**

- `src/insights/types.ts` — extend `InsightType` with `dividend_income` and
  `portfolio_projection`.
- `src/insights/generators.ts` — extend `GenContext` with optional
  `dividends?: { trailing12; upcoming12; total; buckets: SeriesPoint[] }` and
  `projection?: { currentValue; endValue; contributed; years; growthPct; series: SeriesPoint[] }`.
  Add `genDividends` (→ `{ kind: "bars" }`) and `genProjection` (→ `{ kind: "area" }`).
  **Both return `[]` when there are no holdings** — otherwise every non-investor
  gets two empty cards in their stack.
- `src/insights/useInsightStack.ts` — add the `holdings` + `market_dividends`
  queries and reuse `computeDividendEvents` / `bucketize` / `dividendSummary`
  from `src/market/dividends.ts`. No new maths.
- `app/investments/page.tsx` — mount `DividendPanel` + `ProjectionPanel`.

`Charts2D.tsx` already renders `bars` and `area`, so no renderer work.

**Files:** `src/insights/{types,generators,useInsightStack}.ts`,
`app/investments/page.tsx`, `app/insights/page.tsx`

---

## 3. `/recurring` — grouped sections + group cards

The largest piece, and the only one with a migration.

### 3a. Data model

New synced table, plus a nullable FK on the existing template row.

**`supabase/migrations/0045_recurring_groups.sql`**

```
pocketcare.recurring_groups
  id uuid pk · user_id uuid → auth.users on delete cascade
  name text · direction text check in ('income','payment','saving')
  icon text · color text · sort int · is_system boolean default false
  created_at · updated_at · deleted_at
+ unique index on (user_id, direction, lower(name)) where deleted_at is null

alter table pocketcare.transaction_templates
  add column if not exists group_id uuid;   -- see "why nullable in Postgres"
```

Per `CLAUDE.md`: RLS owner policy each preceded by `drop policy if exists`,
grants, every function call schema-qualified, `if not exists` on table/index,
**no cross-row constraints** (they wedge the upload queue). Validate with
`pglast` before shipping.

**Every recurring item must belong to a group — enforced on the client, not by
`NOT NULL` + FK.** Two reasons, both learned the hard way in this repo:

- **Ordering.** Creating "Netflix" in a brand-new group writes two rows that
  PowerSync uploads as two separate HTTP transactions. A `NOT NULL` +
  `REFERENCES recurring_groups` template row that lands *before* its group row
  fails with `23503`, gets 3 attempts, then quarantines — the exact
  head-of-line block that `0040` caused and `0042` removed. The connector does
  preserve order, so it would usually work; "usually" is not a property you
  want on a write path.
- **Backfill.** A `NOT NULL` column needs a value for every existing recurring
  item, and there is no correct value to invent — picking one for the user is
  the "Ungrouped bucket with a nicer name" you just ruled out.

So the column stays nullable in Postgres, the **UI makes it impossible to
create or save an item without a group**, and (following the
`audit_expense_item_sums()` precedent) a `pocketcare.audit_ungrouped_recurring()`
function makes any violation *observable* server-side without being able to
wedge anything.

### 3b. The four required sync steps

1. `packages/db/src/index.ts` — add the `recurring_groups` Table **and** add
   `group_id: column.text` to the existing `transaction_templates` table. The
   second is the step that's easy to forget; without it the device throws
   `table transaction_templates has no column named group_id` on read *and* write.
2. Migration (above).
3. `packages/db/sync-streams.yaml` — add
   `SELECT * FROM pocketcare.recurring_groups WHERE user_id = auth.user_id()`
   to `user_data`. The templates query is already `SELECT *`, so the new column
   comes along automatically.
4. `supabase db push` **and** redeploy sync rules in the PowerSync dashboard.

### 3c. Seeded defaults

Seeded **client-side, idempotently** — not by a Postgres trigger. A trigger on
`auth.users` would miss every existing user, and server rows would have to exist
before the first sync. `ensureDefaultGroups()` runs on first visit to
`/recurring`, inserts only when the user has zero `is_system` groups, and works
offline through the normal write path.

**Multi-device safety:** ids are derived deterministically (`uuidv5(user_id, slug)`),
so two devices seeding at once produce the *same* rows. The connector uploads
inserts as an `upsert`, so the collision is a no-op rather than a permanent
PK-violation that would quarantine.

| Section | Default groups |
|---|---|
| Income | Salary · Freelance · Business · Dividends & interest · Rent received |
| Expenses | Subscriptions · Household & bills · Rent & EMI · Insurance · Transport |
| Savings | Mutual funds & SIPs · Recurring deposits · Emergency fund · Retirement |

All are editable and renameable.

**Deleting a group.** Since nothing may be left ungrouped, the delete dialog
adapts to the group's contents:

- **Empty group** → plain confirm, delete.
- **Non-empty group** → the dialog *requires* a destination: "Move 4 items to →
  `<group picker>`", with a "+ New group" option inline. Deletion and
  reassignment happen together. There is no "delete anyway" escape hatch, and a
  group is never deleted out from under its items.

**The last group in a section** can be deleted only if it is empty — otherwise
the picker would have nothing to offer.

### 3d. Client

- **New `src/recurring/groups.ts`** — `useRecurringGroups()`, `DEFAULT_GROUPS`,
  `ensureDefaultGroups()`, `createGroup` / `updateGroup` / `deleteGroup`.
- **`src/cashflow/recurring.ts`** — add `group_id` to the SELECT, to `Row` and
  to `RecurringItem`; `RecurringInput` gains `groupId`; create/update pass it
  through to the template.
- **`src/cashflow/RecurringModal.tsx`** — a **required** Group `<select>`
  filtered by direction, with an inline "+ New group" option. Save is disabled
  until a group is chosen, matching how the modal already gates on name/amount.
  If the user has deleted every group in that direction, the select is replaced
  by the create-group form directly — there is no state in which the modal can
  be saved without a group.

### 3e. Layout

```
Needs a group ─ one-time triage strip, only while legacy items exist
Due now       ─ confirm-to-record strip (unchanged)

INCOME                                    ₹1,20,000/mo · 3 items
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌─────────────┐
│ Salary   │ │ Freelance│ │ Dividends│ │ + New group │
│ ₹1,00,000│ │  ₹15,000 │ │   ₹5,000 │ └─────────────┘
│  1 item  │ │  2 items │ │  1 item  │
└──────────┘ └──────────┘ └──────────┘
  ▼ tapped → expands in place to the item rows

EXPENSES   …same shape…
SAVINGS    …same shape…
```

- Three sections with clear headings, each showing a **section total (monthly
  equivalent) and item count**.
- Group cards in a responsive grid, each with icon, name, monthly total, item
  count and next due date.
- **Click expands inline** (your choice) into the existing `RecurringRow` list —
  same pattern as the `/friends` group tiles and `ItemBreakdown`.
- **No "Ungrouped" card, ever.** Items created after this ships always have a
  group, because the modal won't save without one.
- **Legacy items** (created before this change) are handled by a **one-time
  triage strip** above the sections — *"3 recurring items need a group"* with an
  inline picker per item, styled like the existing "Due now" strip. It is a
  prompt to fix, not a permanent home: once every item has a group the strip
  disappears and never returns. Each row is pre-selected with a **suggested**
  group where the existing categoriser can infer one (e.g. a template named
  "Netflix" → Subscriptions), so the common case is one confirm tap.
- Keep the "Due now" strip and the `?add=` / `?edit=` / `?convertFrom=`
  deep-link handling — Planned Cashflow links straight into it.
- A11y: each card is a `<button aria-expanded>` controlling its panel.

### 3f. i18n

Extend the `recurring` namespace (en/hi/nl, key-identical) with `groups.*`,
default group names, `newGroup`, an ICU-plural `itemCount`, the delete-group
dialog (including its "move N items to" variant) and the needs-a-group triage
strip. hi/nl need native review, as with every prior batch.

**Files:** `supabase/migrations/0045_*.sql`, `packages/db/src/index.ts`,
`packages/db/sync-streams.yaml`, `src/recurring/groups.ts` (new),
`src/cashflow/{recurring.ts,RecurringModal.tsx}`, `app/recurring/page.tsx`,
`packages/core/i18n/src/locales/recurring/{en,hi,nl}.json`

---

## 4. Templates — remove ordering

- `app/templates/page.tsx` — delete the ▲/▼ chip stack, the `move()` handler and
  the `reorderTemplates` import.
- `src/templates/write.ts` — delete `reorderTemplates`, and drop the
  `MAX(IFNULL(sort,0))` read from `createTemplate` (one less query per create).
- `src/templates/hooks.ts` — `ORDER BY IFNULL(sort,0), name` → `ORDER BY name COLLATE NOCASE`.
  (Say if you'd rather have newest-first.)
- **The `sort` column stays.** Removing it means a migration plus an `AppSchema`
  change for zero user-visible gain; leaving it inert costs nothing.
- i18n — drop `moveUp` / `moveDown` / `reorder` from `templates` en/hi/nl.

---

## 5. Dividers → separated row tiles

The hairline `borderBottom: "1px solid var(--border)"` list pattern appears
**28 times across 19 files** — the two you flagged are the visible tip.

**Approach:** one reusable pattern, applied to the two you named now and rolled
out to the rest as a follow-up sweep (so this change stays reviewable).

Add to `globals.css`:

```css
.row-stack { display: grid; gap: 6px; }
.row-tile  {
  background: var(--surface-2); border-radius: 10px;
  padding: 11px 14px; transition: background .15s;
}
.row-tile:hover { background: var(--surface-3, var(--surface-2)); }
```

Separation comes from **space and a recessed surface**, not a line — which is
what Apple and Google both do in their modern list styles.

- **`app/groups/[id]/page.tsx:203`** — members list becomes
  `.row-stack` / `.row-tile`. The card wrapper drops to `padding: 8`.
  (The `borderBottom` at line 37 is a page-header rule, not a list divider —
  left alone.)
- **`app/help/page.tsx:135`** — each FAQ Q/A becomes its own `.row-tile`;
  the open state tints the tile rather than drawing a rule beneath it.
- The group-detail **expenses** list (~line 218) uses the same pattern and is in
  the same file, so it comes along.

**Follow-up sweep (not in this change):** `loans`, `cards`, `friends`,
`investments`, `receipts/*`, `TransactionRow`, `Billing`,
`PendingSettlements`, `ItemBreakdown`, `dashboard/tiles`.

---

## 6. Navigation icons — Material Symbols

Today `NAV_GROUPS` carries Unicode geometry glyphs (`◧ ✦ ▤ ⇅ ▧ ▭ ◑ ◇ ⌕ …`).
They render in the text font — hence thin — and several are arbitrary
(`/settings` and `/groups` are both `◇`; `/investments` is `▲`).

**One correction to your choice, worth making explicitly.** You picked Material
Symbols via CDN. Same icons, but I'd **self-host the woff2** instead, because
PocketCare is an offline-first PWA:

- a CDN font is a third-party request that **fails offline** — the nav would
  show raw ligature text (`space_dashboard`) instead of icons;
- it needs a `font-src` CSP entry and a third-party connection on every cold load;
- self-hosting is one ~90 KB static file in `public/fonts/`, added to the
  service-worker precache.

Identical glyphs, no downside. Tell me if you'd still rather use the CDN.

**Change**

- `apps/web/public/fonts/material-symbols-rounded.woff2` (static, subset to the
  ~20 icons used) + `@font-face` in `globals.css` with `font-display: block` —
  `block` matters here: with `swap` the browser paints the ligature *name* as
  words until the font loads.
- A `.msym` class (`font-variation-settings: 'FILL' 0, 'wght' 400, 'opsz' 24`,
  `font-feature-settings: 'liga'`, `color: currentColor`).
- Add the font to the `sw.js` precache list.
- `NAV_GROUPS` `icon` values become ligature names:

  | Item | Symbol | Item | Symbol |
  |---|---|---|---|
  | Dashboard | `space_dashboard` | Budgets | `donut_small` |
  | Ask PocketCare | `auto_awesome` | Goals | `flag` |
  | Accounts | `account_balance` | Planned Cashflow | `waterfall_chart` |
  | Transactions | `swap_horiz` | Recurring | `autorenew` |
  | Templates | `bookmarks` | Loans | `request_quote` |
  | Cards | `credit_card` | Investments | `trending_up` |
  | Splits | `call_split` | Insights | `insights` |
  | Groups & trips | `groups` | Statements | `description` |
  | Search | `search` | Settings | `settings` |
  | Notifications | `notifications` | Help & FAQ | `help` |

- Render at 20 px, `color: currentColor`, drop the `opacity: 0.75` — the active
  item already carries `var(--accent)`.
- **No emoji, strictly.** Also replaces: the `💬 Feedback` button
  (`chat_bubble`), the InsightFeed empty-state `✦` (`insights`), and the `‹`
  back chip (`arrow_back`). `NotifNavItem`'s existing `BellIcon` switches to
  `notifications` for consistency; the other hand-drawn SVGs in
  `src/ui/icons.tsx` stay as-is — they're used inside components, not the nav.

**Files:** `app/AppShell.tsx`, `app/globals.css`, `public/fonts/*`,
`public/sw.js`, `src/ui/feed/InsightFeed.tsx`

---

## 7. Dashboard tiles — no nested scrolling, and bar charts that match the line charts

### 7a. Root cause of the trapped scroll

`globals.css`:

```css
.dash-tile-body > section {
  height: 100%; overflow-y: auto; overflow-x: hidden;
  overscroll-behavior: contain;   /* ← this is the bug you're feeling */
}
```

`overscroll-behavior: contain` **explicitly disables scroll chaining**. So when
the pointer is over a tile, the tile consumes the scroll and, on reaching its
own end, refuses to hand it to the page. That's precisely the "I can't scroll
the page from the tile" symptom — and on touch it's worse than on a wheel,
because a swipe that starts inside a tile is captured for its whole duration.

**Correction — I previously called this desktop-only. That was wrong**, and you
were right to push back. I'd read the `@media (max-width: 860px)` override
(`height: auto; overflow-y: visible`) and stopped there. Two things I missed:

- **The breakpoint is 860px, which is not "mobile".** A phone in landscape, an
  iPad in landscape (1024px), and most Android tablets are all *above* it — so
  they take the desktop path and get fixed-height, scroll-trapping tiles. If
  you hit this on a tablet or a rotated phone, that's why.
- **The dashboard isn't the only offender.** A repo-wide sweep found nested
  scrollers in page content that trap at *every* width — see 7e.

So the fix below is device-agnostic: no width-conditional behaviour anywhere.

**Fix**

```css
.dash-tile-body > section {
  height: 100%; box-sizing: border-box; min-height: 0;
  display: flex; flex-direction: column;   /* lets a chart area flex + shrink */
  overflow: hidden;                        /* clip, never scroll */
}
```

…and **delete the mobile override entirely** rather than keep two behaviours.
With tiles clipping at every width, `height: auto; overflow-y: visible` is no
longer needed; one code path means the bug can't come back on one form factor
only. Mobile keeps its single-column, natural-height grid — that part of the
media query stays.

No tile scrolls in either axis, at any width. Anything that doesn't fit is
*designed out* (7b) rather than hidden behind a scrollbar.

### 7b. Make the content fit — `useFitRows`

Tiles are **user-resizable** (`grid-column: span W_COLS[…]` / `grid-row: span
H_ROWS[…]`), so a hard-coded "show 4 rows" is wrong at every size but one. New
`src/dashboard/useFitRows.ts`: a `ResizeObserver` on the list container
returning `max(1, floor(available / ROW_H))`.

Lists render `items.slice(0, fit)` plus a **"+N more →"** link to the full page.
This is not a new pattern — `BudgetsTile` (line 318) and the upcoming-payments
tile (line 548) already do exactly this; it just becomes universal and
size-aware.

Applies to: Recent activity, Budgets, Goals, Subscriptions, Splits balances,
Upcoming payments, and the category-pie legend.

*Intentionally left scrollable:* the **Add-a-widget modal** (`maxHeight: 60vh`).
A modal has the space, which is the case your rule allows for.

### 7c. Charts fill their tile instead of forcing a height

Every chart is a fixed pixel height today — `220`, `230`, `240`, and worst,
`HBarTile`'s `height={Math.max(180, data.length * 34)}`, which grows to **272 px
for 8 rows** inside a cell whose row unit is `clamp(80px, 10.5vh, 118px)`. That
is the overflow that made the scrollbar necessary.

- All `ResponsiveContainer height={NNN}` → `height="100%"`, wrapped in
  `<div style={{ flex: 1, minHeight: 0 }}>`.
- `HBarTile` loses its data-driven height; bar count comes from `useFitRows`.
- Add `.recharts-responsive-container, .recharts-wrapper { min-height: 0 !important }`
  next to the existing `min-width: 0` rule (same class of recharts intrinsic-size
  bug already documented in `PROJECT_REFERENCE.md`).

### 7d. Bar-chart polish

The gap between the area charts and the bar charts is specific, not vague:

| | Area / line charts | Bar charts today |
|---|---|---|
| Tooltip | formatted, styled cursor | `MonthCompare`: raw numbers · `HBar`: **none at all** |
| Hide-amounts | respects `useAmountsHidden()` | **ignores it** |
| Currency | `format(money(…))` | `v.toLocaleString()` — unitless |
| Y axis | compact ticks (`12.5k`) | hidden / absent |
| Gradient | vertical, `0.5 → 0.03`, soft | `gBar` horizontal `0.55 → 1`, heavy |

**The hide-amounts row is a privacy bug, not polish.** Hide-amounts is a
privacy feature, and these two tiles render real figures straight through it.
Worth fixing regardless of the redesign.

**Fixes**

- Shared `<ChartTooltip>` + a `chartMoney(hidden, base)` formatter used by
  *every* chart, so currency and masking can't drift apart again.
- `HBarTile`: add the tooltip; currency-format `LabelList`; respect `hidden`;
  replace the arbitrary `YAxis width={96}` clip with a `tickFormatter` that
  ellipsises long category names; soften `gBar` to the `gTrend` opacity ramp;
  `radius={[0, 6, 6, 0]}`; `barSize` derived from the fit calc so bars stay
  proportionate at every tile size.
- `MonthCompareTile`: legend swatches for income/expense, `LabelList` values
  above the bars, formatted tooltip, and a horizontal-only `CartesianGrid` so it
  reads with the same visual weight as the area charts.
- Match `isAnimationActive` duration and easing across bar and area charts.

### 7e. App-wide nested-scroll audit

`overscroll-behavior` + `overflow-y: auto` appear in **16 places**. Your rule —
no nested scrolling unless there's space — sorts them cleanly into three buckets.

**Remove — in-page content that traps the swipe (the ones that hit you):**

| Where | Today | Fix |
|---|---|---|
| `app/friends/page.tsx:306` | person sheet's itemised transactions, `maxHeight: 260` | show first N + "View all →"; no cap, no scroll |
| `app/groups/[id]/page.tsx:268` | invite suggestions rendered as an **inline card**, `maxHeight: 220` | cap to top 6 matches + "keep typing to narrow" hint |
| `app/page.tsx` dashboard tiles | §7a–c | clip + `useFitRows` |

**Keep — genuine overlays, which is the "you have space" case:**

`Modal.tsx:29` (the overlay itself must scroll), the dashboard Add-a-widget
modal, `transactions/[id]/edit:294`, and the four typeahead popovers
(`LabelPicker`, `SearchSelect`, `MultiSelect`, `InstrumentPicker`) — these are
absolutely-positioned popovers over a dimmed page, not content competing with
page scroll.

**Keep, with one change — `.assist-thread` (globals.css:147):** a chat log
scrolling is inherent to chat, and the assistant page is a full-height flex
column where the page itself doesn't scroll, so there's nothing to chain *to*.
Leaving `overflow-y: auto`; **dropping `overscroll-behavior: contain`**, which
buys nothing there and is the exact property causing trouble elsewhere.

**Guard rail so this doesn't regress:** the console assertion in Verification
step 6 generalises to the whole app — walk `document.querySelectorAll('*')` for
`scrollHeight > clientHeight + 1` on anything that isn't inside `[role=dialog]`
or a popover. Worth keeping as a dev-only check.

**Files:** `app/globals.css`, `src/dashboard/tiles.tsx`,
`src/dashboard/useFitRows.ts` (new), `app/page.tsx`, `app/friends/page.tsx`,
`app/groups/[id]/page.tsx`

---

## Verification

1. `pnpm --filter @pocketcare/web typecheck` (or `cd apps/web && ../../node_modules/.bin/tsc --noEmit`).
2. `node --test --experimental-strip-types packages/core/*/src/*.test.ts` — the
   new insight generators are pure, so `genDividends` / `genProjection` get unit
   tests (empty-holdings → `[]`, bucket maths, no-crash on zero portfolio value).
3. `pglast` parse of `0045_recurring_groups.sql`.
4. Manual, on the grouping invariant specifically:
   - seed defaults on a fresh profile; confirm no duplicate groups after seeding
     on a second device;
   - the recurring modal cannot be saved without a group, including when every
     group in that direction has been deleted;
   - deleting a non-empty group forces a destination and moves the items;
   - a profile with pre-existing recurring items shows the triage strip, and the
     strip disappears permanently once cleared;
   - `pocketcare.audit_ungrouped_recurring()` returns zero rows afterwards;
   - `/recurring?add=income` still opens the modal (Planned Cashflow deep link).
5. Offline check: DevTools → Offline, hard reload — nav icons must still render
   as glyphs, not words.
6. No-scroll rule, verified **on a real touch device, not just a narrow window** —
   DevTools' responsive mode does not reproduce touch scroll capture, which is
   how I missed this:
   - swipe starting **inside** a tile scrolls the page, on phone and tablet;
   - test at **three widths** — phone (<860px), tablet/landscape phone
     (860–1100px, the path I wrongly assumed was unreachable), and desktop;
   - the app-wide console assertion (7e) reports zero unexpected scrollers;
   - resize each tile to its **smallest** span: nothing clips, "+N more"
     appears, charts shrink rather than overflow;
   - the `/friends` person sheet and the group invite typeahead no longer trap
     a swipe;
   - toggle hide-amounts: both bar tiles mask their labels, tooltips and
     `LabelList` values.

## Docs (mandatory, same change set)

- `docs/features/recurring.md` — grouping model, user flow, sequence diagram.
- `docs/features/insights.md` — full-bleed feed; the two new card types.
- `docs/features/templates-and-recurring.md` — ordering removed.
- `docs/features/dashboard.md` — tiles clip instead of scroll; `useFitRows`.
- `PROJECT_REFERENCE.md` gotchas — add the `overscroll-behavior: contain`
  finding next to the existing recharts-in-grid note; both are the same family
  of bug and the next person will hit one looking for the other.
- `docs/architecture/02-data-model.md` — `recurring_groups` in the ER diagram.
- `docs/architecture/03-sync-and-offline.md` — new stream entry.
- `PROJECT_REFERENCE.md` — dated change-log entry.

## Deploy notes

- `supabase db push`, then **redeploy `sync-streams.yaml`** in the PowerSync
  dashboard. Skipping the redeploy means groups never sync.
- No new npm dependency, so `pnpm-lock.yaml` is untouched and CI stays green.
  (`pnpm` isn't available in the agent sandbox, so this was a deliberate
  constraint on the icon decision.)
- `git push` is yours — the sandbox has no credentials.
