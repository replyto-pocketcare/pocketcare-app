# Screen spec — Search

> **Source:** `apps/web/app/search/page.tsx` (148 lines), `apps/web/src/ui/FloatingInput.tsx`
> (35), `apps/web/src/ui/TransactionTile.tsx` (273), `apps/web/src/splits/collapse.ts` (93),
> `apps/web/src/ui/icons.tsx` (197, for `SlidersIcon`), `apps/web/src/ui/MaterialIcon.tsx` (98),
> `apps/web/src/ui/Money.tsx` (28), `apps/web/app/globals.css` (`.input`, `.chip`, `.card`,
> `.floating`, `.list-grid`, `.tx-tile`, `.fade-up`), `packages/core/i18n/src/locales/search/*`,
> `packages/core/money/src/index.ts`.
> Derived 2026-08-23 by source translation, not from screenshots.
>
> **Scope:** the `/search` route only. It has **no native screen on either platform today** —
> this document is what both are built from. The chrome around it (util row, bottom nav,
> banners) is `docs/mobile/screen-specs/app-shell.md`; not repeated here.
>
> **Native targets:** `apps/android/.../ui/search/` and `apps/ios/App/Search/`.
> Reuse, do not re-derive: `TransactionTileLogic.kt` / `TransactionTileLogic.swift` (already
> ported avatar/merchant/tag logic), `DateTimeField.kt` (Android date picker), the
> `SanvyaButton`/`SanvyaChip`/`SanvyaInput` component layer, and `S.Search.*` /
> `Generated/S.swift Search` (i18n accessors — **already generated**, see §6).

## 1. Component tree, render order

```
SearchPage                                    "search" namespace, class="fade-up"
├── h1                                        t("title")
├── input .input                              free-text query
├── filter-toggle row
│   ├── chip "Filters" (+ count, ▴/▾)          toggles the filter panel
│   └── chip "Clear"                           only when activeFilters > 0
├── filter panel .card                         only when showFilters
│   ├── type chip row (All/Income/Expense/Transfer)
│   ├── select .input                          account, "All accounts" + every account
│   ├── from/to date row (each: label + input[type=date])
│   └── min/max amount row (2× FloatingInput)
├── results-count line                        t("resultsCount", { count })
└── results
    ├── .list-grid of TransactionTile[]         when results.length > 0
    └── "no matching" .card                     otherwise
```

No loading state, no error state, no premium gating — see §4.

## 2. Filter state and the deep-link prefill

State is seven independent `useState`s: `q, type, accountId, from, to, min, max,
showFilters`. `activeFilters` is a derived count of `[type≠"all", accountId, from, to, min,
max]` truthy — drives the chip's `· N` suffix and whether "Clear" renders. `clearFilters()`
resets all six filter fields (not `q`) to their defaults.

**Deep link, once per mount:** a `useEffect` reads `useSearchParams()` — `q, type, account,
from, to, min, max` — and seeds the matching state, guarded by a `prefilled` flag so it never
re-applies after the user edits something. If `type` isn't one of the four known values it is
ignored. If any filter param besides `q` was present, `showFilters` is forced open. This exists
because `AssistantChat.tsx` deep-links here — e.g. *"show my Swiggy spends last month"* becomes
`/search?q=Swiggy&type=expense&from=2026-06-01&to=2026-06-30` — so the assistant's link must
land the user already filtered, not just on a blank search box.

**Native:** there is no query-string equivalent. Carry the same six keys as typed navigation
arguments (Android `SavedStateHandle` / Compose Nav args; iOS a `SearchDestination` payload) and
apply the identical "open filters if anything besides q is set" rule. The assistant screen is
the only caller that needs to construct this payload — confirm its native port passes all six
fields, not just `q`.

## 3. The query and the filter predicate — port byte-for-byte

Three `useQuery` calls, all local SQLite via PowerSync, no server round-trip:

```sql
-- rows (LIMIT 2000, newest first)
SELECT t.*,
  (SELECT GROUP_CONCAT(l.name, ', ') FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id WHERE tl.transaction_id = t.id) AS labels,
  (SELECT pm.label FROM payment_methods pm WHERE pm.id = t.payment_method) AS method_label
FROM transactions t WHERE t.deleted_at IS NULL AND t.type != 'opening_balance'
ORDER BY t.occurred_at DESC LIMIT 2000

-- cats
SELECT id, name FROM categories WHERE deleted_at IS NULL

-- accts
SELECT id, name, type, color FROM accounts WHERE deleted_at IS NULL
```

Filtering and ranking happen **client-side in a `useMemo`**, not in SQL — there is no
full-text index. The 2000-row cap on the base query and a **300-row cap on the filtered/
rendered output** (`.slice(0, 300)`) are both deliberate ceilings on an unbounded scan; port
both numbers exactly, not just the visible one.

Predicate, applied to every one of the 2000 rows, in this order (short-circuits on first
failure — order doesn't change results but does change how much work an early exit skips):

1. `type !== "all" && t.type !== type` → reject.
2. `accountId` set and matches neither `t.account_id` **nor** `t.to_account_id` → reject.
   (A transfer's *destination* account counts as a match — this is why it isn't just
   `t.account_id`.)
3. `day = t.occurred_at.slice(0, 10)` (first 10 chars of the ISO timestamp) compared
   lexically against `from`/`to` — relies on ISO8601 sort order, not a parsed-date compare.
4. `minA`/`maxA`: **`Math.round(Number(min) * 100)`**, then compared against
   `Math.abs(t.amount)`. This hardcodes a 2-decimal-place minor-unit conversion — it does
   **not** call `minorUnits(currency)` from `@sanvya/money`, which the rest of the codebase
   uses because minor-unit precision varies by currency (JPY has 0, KWD has 3). For an
   all-INR/2-decimal ledger this is invisible; for a multi-currency one entering "100" as a
   minimum against a 0-decimal-currency transaction filters against the wrong scale. **Port
   this exactly as written (hardcoded ×100)** — it is a pre-existing web bug, not a spec to
   silently fix on native, and fixing it only on one platform would make the two disagree on
   result sets for the same input. Flag it to the web team; do not diverge unilaterally.
5. Free text `term = q.trim().toLowerCase()`: builds one haystack per row —
   `[labels, note, description, type, method_label, catName(category_id), account.name,
   account.type, toMajor(money(amount, currency)).toFixed(2)]`, `filter(Boolean).join(" ")`,
   lowercased — and does a plain `.includes(term)`. Note the **major-unit amount string** is
   in the haystack, so typing "45.00" can match by amount. `toFixed(2)` here is also always
   2 decimals regardless of currency, same caveat as above but for search-matching rather than
   filtering, so it's lower-stakes (a false negative on an odd-currency amount search, not a
   wrong balance).

`accts` is queried with a `color` column that **is never read** anywhere in this file — dead
column in the query, harmless, don't port the fetch of it if the native repository call lets
you project narrower; not worth preserving as a "feature."

**Native repository:** no existing method matches this on either platform (`git grep` for a
transactions search/filter repository call came back empty). This is new: implement the same
three queries (GROUP_CONCAT and the two column names are plain SQLite, ports directly) plus the
JS predicate translated 1:1, including the 2000/300 caps and the hardcoded ×100.

## 4. States

There is no explicit loading or error state in the source — `useQuery` defaults to `data: []`
before PowerSync resolves, so a page-load render and a genuinely-zero-results render are
**visually identical** (the "no matching" card, or a `resultsCount` of 0). Because these are
local SQLite reads (no network), that resolve is normally sub-frame, so this omission is not a
visible defect on web. Native should match: do not add a spinner or skeleton this screen never
had — resolve the repository query synchronously enough that none is needed, same as web.

| State | Trigger | Render |
|---|---|---|
| Populated | `results.length > 0` | `.list-grid` of `TransactionTile` |
| Empty | `results.length === 0` (true empty, or filters exclude everything) | `t("noMatching")` in a muted card |
| Filters closed (default) | `showFilters === false` | just the chip row |
| Filters open | `showFilters === true`, or any deep-link filter param was present | the filter `.card` |

No premium/entitlement gating anywhere in this file — no `useEntitlement` import, no tier
check. Every filter and every result is available at every tier.

## 5. Tokens

| Element | Value | Token |
|---|---|---|
| Page wrapper | `gap 18`, `fade-up` | gap: raw literal (18px, no named token — the shell's own page padding, `SHELL.page`, is separate and still applies around this); animation: `MOTION.fadeUp` (400ms, translateY 8) |
| `h1` | 26/700, `-0.02em` (22/700 below 860px) | `TYPOGRAPHY.styles.h1` / `h1Compact` |
| Free-text `.input` | radius 12, border 1px `--border`, padding `11 14`, font 15 | `SHAPE.row`-adjacent — actually `--radius-sm` (`TYPOGRAPHY.styles.body` for the 15px) |
| Filter/clear chips | pill radius 999, border 1px, padding `8 14`, font 14 | `SHAPE.pill`, `TYPOGRAPHY.styles.chip` |
| Chip active fill | `data-active="true"` → `--accent` bg, white text | color tokens `accent` |
| Filter panel `.card` | `--surface`, 1px `--border`, radius `--radius-lg`, shadow `--shadow`, padding 14 (inline), gap 12 (inline) | `radius-lg`, `ELEVATION.card`; the 14/12 padding/gap are raw literals local to this screen |
| Type chip row | gap 6 (inline) | raw literal |
| Account `<select>` | same `.input` styling | as above |
| From/To date labels | `.muted`, font-size 12 (inline) | `--text-2` for colour; **12px is a raw literal**, not `TYPOGRAPHY.styles.eyebrow` (11) or any catalogued size |
| From/To row gap | 8 (inline), each field `flex: 1 1 140px` | raw literals |
| `FloatingInput` (min/max) | see `.floating` — padding `20 14 7`, radius `--radius-sm`, font 15; label at `top:14/font 15` idle → `top:6/font 11/color --accent-soft` focused/filled | `radius-sm`; the label's 11px floated size and the 0.15s transitions are raw literals in `.floating`, not separately catalogued |
| Results-count line | `.muted`, font-size 13 (inline) | `--text-2`; 13px raw literal (do not confuse with `TYPOGRAPHY.styles.statLabel`, which is 13/**600** — this text is regular weight) |
| `.list-grid` | `repeat(auto-fill, minmax(min(320px,100%), 1fr))`, gap 12 | `SHELL.listGrid` (minColumnWidth 320, gap 12) |
| `TransactionTile` as `.tx-tile` (`card` prop true) | border 1px `--border`, radius `--radius-sm`, padding `13 15 !important`, hover lift | `radius-sm`; see `TransactionTile` row below |
| "No matching" card | `.muted .card`, padding 16 (inline), margin 0 | `radius-lg`/`shadow` from `.card`; 16px padding raw literal |
| `SlidersIcon` | 15px, stroke 1.8 (default 18 overridden to 15 at the call site) | raw SVG icon — **not** in the Material Symbols subset; see §7 |
| Chevron `▴`/`▾` | inline text char, `opacity: 0.6` | raw literal — not a token, not an icon glyph |

### `TransactionTile` (as rendered here: `card`, non-`dense`)
Avatar 34×34 circle, deterministic colour from `avatarColor(title)` (7-colour palette, sum of
char codes mod 7 — **port the hash exactly**, it's how a merchant keeps a stable colour across
platforms). Title 14/600, one line, ellipsised. Subtitle (full narration, only when it differs
from the derived title) 11.5px, wraps (`overflowWrap: anywhere`) — deliberately not truncated;
see the file's own header comment on why (a UPI narration ellipsised at 40 chars is
unreadable). Tags row (category + labels, each with a `MaterialIcon` glyph) 11.5px, wraps.
Account line (own row, only when not `dense`) 11.5px with the `account_balance` glyph. Amount
14.5/700, coloured `--positive` for unsplit income else `--text`; sign is `−`/`+`/none per
type, **split rows always render as `−`** regardless of type. Split rows show the collapsed
`SplitChip` pill (10.5px, uppercase, `--accent`/`--accent-ghost`/`--accent-soft` border).

## 6. i18n

Namespace **`search`** — `packages/core/i18n/src/locales/search/{en,hi,nl}.json`, fully
translated in all three (17 keys each; en/hi/nl all present, no gaps). Keys used by this
screen, all of them:

`title`, `searchEverything`, `filters`, `clear`, `type.all`, `type.income`, `type.expense`,
`type.transfer`, `allAccounts`, `resultsCount` (plural: `_one`/`_other`, interpolates `count`),
`noMatching`, `minAmount`, `maxAmount`, `fromDate` (called with a JS default `"From date"` even
though the key exists — the default is unreachable, not a real fallback path), `toDate`.

**Native scaffolding already exists for this namespace** — both platforms' generated typed
accessors are present and ready to call even though no screen uses them yet:
`S.Search.*` in `apps/android/app/src/main/java/com/sanvya/app/i18n/S.kt` (e.g.
`S.Search.resultsCount(res, count)` → `getQuantityString`), and the `Search` enum in
`apps/ios/App/Generated/S.swift`. Use those; do not hand-roll new string constants.

## 7. Assets to add

`SlidersIcon` (filters glyph) is a hand-drawn stroke SVG from `apps/web/src/ui/icons.tsx`
(`viewBox 0 0 24 24`, `stroke-width 1.8`, `currentColor`), **not** one of the codepoints in the
Material Symbols subset (`Icons.kt` / `SanvyaIconView.swift` have no `tune`/`filter`/`slider`
entry). Native needs a new vector asset — trace the two `<path>`s
(`M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3` and `M2 14h4M10 8h4M18 16h4`, three vertical
sliders with handles) rather than substituting a similar-looking Material icon; it is a
distinct icon system used only for a handful of chrome/utility glyphs (see also `BellIcon`,
`EyeIcon` in the same file), separate from the Material Symbols font used for category/label/
account tags.

## 8. Data access summary

| Read | Query | Native repository |
|---|---|---|
| Transactions | `transactions` + correlated `labels`/`method_label` subqueries, LIMIT 2000 | none yet — new |
| Categories | `categories` (id, name) | none yet — new (or reuse if another screen already has a categories lookup; check before adding a second one) |
| Accounts | `accounts` (id, name, type, color — color unused) | none yet — new |
| Split info | `expense_postings` ⋈ `transactions` ⋈ `expenses`, aggregated per expense | `useSplitInfo()`/`collapseSplitRows()` in `src/splits/collapse.ts` — no native port found; the aggregation logic (own_share + lend = paid; own_share + borrow = your share) must be ported exactly, including the "paid > 0 ? paid : borrow" fallback so a fully-borrowed split doesn't show ₹0 |

No writes on this screen at all — it only navigates to `/transactions/:id/edit` via the tile's
`href`; editing happens on that screen, not here.

## 9. Deliberately not ported / must not copy as-is

- **The hardcoded ×100 amount-filter conversion (§3.4)** — port it for parity (both platforms
  must agree with web on the same input), but it is a known bug, not a design choice. Do not
  "fix" it only on native.
- **Query-string prefill** — the mechanism (not the feature) is web-only; use typed navigation
  arguments instead (§2).
- **The unused `color` column fetch on `accts`** — no need to project it if the native query
  layer lets you select narrower; it was never a feature.

## 10. Done-when

- [ ] Free-text search matches the same haystack fields, same lowercase/includes semantics,
      including the amount-as-string match.
- [ ] All six filters (type, account, from, to, min, max) combine with AND, exactly as §3 orders
      them (order affects nothing observable, but the accountId-matches-either-side rule and the
      date lexical-compare must be exact).
- [ ] 2000-row base cap and 300-row rendered cap both present.
- [ ] Deep-link navigation args reproduce the "open filters if anything but q is set" rule; the
      assistant screen's native port constructs the full six-field payload, not just `q`.
- [ ] Split transactions collapse to one tile with the `Split` chip; siblings are hidden, not
      duplicated.
- [ ] `TransactionTile` avatar colour hash matches web's char-code-sum-mod-7 exactly (cross-
      platform colour stability for a shared account).
- [ ] Empty state and zero-loading-state both read identically to web (no spinner added).
- [ ] `S.Search.*` / `Generated/S.swift Search` used for every string — no new hardcoded English.
- [ ] No value in the screen is a literal where a token exists; every genuine literal (§5's
      "raw literal" rows) is called out as such in code review, not silently assumed to be a
      token.
- [ ] CI green on both platforms.
