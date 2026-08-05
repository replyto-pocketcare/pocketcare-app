# Screen spec — Dashboard

> Source: `apps/web/app/page.tsx` (read 2026-08-05). This is the porting reference per `docs/plans/mobile-pixel-parity-plan.md` Phase B — values/structure below are read directly from web source, not eyeballed from a screenshot. Tokens referenced by name resolve via `tools/parity/generate-tokens.mjs`'s output (Android `SanvyaColors`/`SanvyaRadius`, iOS `Color.*`/`SanvyaRadius`).

## Scope of this spec / this porting pass

`page.tsx` is 501 lines and includes a fully custom drag-to-reorder, resize-handle, long-press-to-edit dashboard tile system (`DraggableGrid`, `AddWidgetModal`) rendering 12 distinct tile types from `apps/web/src/dashboard/tiles.tsx` (979 lines: recent, spending, trends, splits, budgets, goals, subscriptions, cashflow, netTrend, byCategory, byLabel, monthCompare — several with their own charts). **That tile catalog + editing UX is out of scope for this pass** — it's a large, separable body of work and porting it under time pressure is exactly the shortcut that produced the false-DONE problem this plan exists to fix. This spec covers, and this pass ports: the three top-level states (loading / empty-onboarding / populated), the header action bar, the net-worth hero, and the accounts strip. The tile catalog is tracked as its own follow-up (one row per tile, see `docs/mobile/TODO.md`).

## States

1. **Loading** (`balances.length === 0 && (accountsLoading || syncPending)`): skeleton placeholders — a hero-shaped skeleton (132px), a card with a title skeleton + 6 small skeletons in an auto-fill grid, a 190px skeleton, two 150px skeletons. Never show the empty state during this — it previously flashed incorrectly.
2. **Empty / onboarding** (`balances.length === 0`, not loading): centered card, max-width 460, radial gradient background (`--accent-ghost` → `--surface`), heading "Welcome to Sanvya", copy: *"Start by adding your first account — just your own note of somewhere your money sits. Nothing here connects to your bank; you type the amounts in yourself."* CTA button → add-account flow. `Walkthrough` component also mounts here (first-run overlay, not covered by this spec).
3. **Populated**: header + hero + accounts card + tiles grid (tiles deferred, see Scope above).

## Header (populated state)

- Left: `h1` "Dashboard" (`t("pages.dashboard")`). While in edit mode, a small `--accent`-colored hint line below it: "Reorder with the ▲▼ arrows (or drag on desktop) · handles resize" (edit-mode UI itself deferred with the tile catalog).
- Right, not editing: three controls — "Customize" chip (icon: sliders), "Hide"/"Show" chip (icon: eye/eye-off, toggles `amountsHidden` global pref), "Account" ghost button (icon: plus) → `/accounts/new`.
- Right, editing: "Widget" ghost button + "Done" button (green, `--positive` background). Edit-mode itself deferred.

## Net-worth hero (`NetWorthHero`) — port this exactly, it's the single most visible element

- Container: `border-radius: 24px` (token `radiusLg`), padding `26px 28px`, text color `#f1ede3`, **background `linear-gradient(150deg, #5f6647 0%, #3e4a38 100%)`** (NOT `--accent`/terracotta — a distinct deep-green gradient, `--forest`-family, only used here). Box-shadow `0 20px 44px -22px rgba(62,74,56,0.7)` (translate to platform elevation/shadow as closely as supported).
- Top-right toggle pill: background `rgba(255,255,255,0.14)`, text `#eaf0da`, 12px/600, rounded-pill, padding `5px 12px`. Label: "Excluding blocked" when currently showing available, "Including blocked" when showing total (i.e., label always names what tapping it will switch TO). Tapping flips `showAvailable`.
- Eyebrow label: 12px/600, uppercase, letter-spacing 0.06em, color `#c6cdb3`. Text: "Available net worth" when `showAvailable`, else "Net worth".
- Big amount: `clamp(30px, 9vw, 46px)` / weight 750, margin-top 6. Value is `net` (= `available` if `showAvailable` else `total`, both from `NetWorth.total`/`NetWorth.available` — Android: `LedgerRepository.watchNetWorth("INR")`, already real). Respects the global hide-amounts pref (renders `••••••` when hidden — money must go through the shared formatter, never raw).
- Delta pill (only when `months.length > 0`): inline-flex, rounded-pill, background `rgba(255,255,255,0.14)`, 12.5px/600. Up-arrow path or down-arrow path (chevron), color `#dde7c9` if up else `#f0d8c9`. Text: `"+" or "−"` + formatted absolute delta + `" this month"`. Delta = last month's `(income − expense)` in minor units, from the monthly income/expense grouping (Android: new `LedgerRepository.watchMonthlyIncomeExpense()`, ported this pass — matches the web SQL exactly: `GROUP BY strftime('%Y-%m', occurred_at), type`).
- Sparkline: SVG area+line chart, last 8 months of cumulative `(income−expense)/100`, running sum (`acc += ...`) — i.e. it's a cumulative net-flow trend, not monthly deltas plotted independently. Line color `#eaf0da`, 2.2px stroke, area fill gradient `#c6cdb3` 50%→0% opacity. `viewBox 0 0 300 64`, `preserveAspectRatio="none"`, scales to container width. Skip entirely if fewer than 2 months of data (matches web's `if (values.length < 2) return null`).
- Footer line: "Base currency {base}" — 12.5px, color `#c6cdb3`.

## Accounts card

- `.card`-styled section (surface bg, `--border` 1px, `radiusLg`, `--shadow`), padding 20, gap 14.
- Header row: "Accounts" (h2) + "View all" chip → accounts list route, chip text gets `" (N)"` suffix when `balances.length > 8`.
- Grid: `auto-fill, minmax(min(112px,100%), 1fr)`, gap 8. First 8 accounts only (`.slice(0, 8)`).
- Each account chip: background = `account.color` if set else `colorForId(account.id)` (deterministic per-id color — port this function, don't invent new colors), text white, `border-radius: 12px` (token `radiusSm`), padding `9px 11px`, box-shadow `0 6px 16px -12px rgba(43,39,35,0.6)`. Three stacked lines, each `overflow: hidden; text-overflow: ellipsis; white-space: nowrap`: account type (10px, opacity 0.85, capitalized, underscores→spaces), account name (12px/600), balance (14.5px/750, subtle text-shadow `0 1px 2px rgba(0,0,0,0.22)`, through the hide-amounts formatter). Tapping navigates to that account's edit screen.

## `colorForId` (source: `apps/web/src/colors.ts`) — port exactly

18-color palette (`ACCOUNT_COLORS`, listed in `apps/web/src/colors.ts`, includes non-earthy jewel tones like indigo/violet/denim/teal/plum/slate — this is deliberate, not a token-system violation, don't substitute the earthy palette here). Hash: `h = 0; for each char: h = (h*31 + charCode) >>> 0 (unsigned 32-bit); index = h % 18`. Empty/null id → fallback `#7c7264`.

## Data already available (Android — verified real, `DashboardViewModel.kt`/`LedgerRepository.kt`)

`netWorthFormatted`/accounts/recentTransactions already wired. This pass adds: `showAvailable` toggle state, `NetWorth.available` (already computed, just wasn't surfaced), and the monthly income/expense flow for the sparkline+delta. iOS has an equivalent `DashboardViewModel` — needs the same additions ported (check before assuming parity — this spec doesn't verify iOS's ViewModel, only its View, which is being rewritten this pass to match this spec, not its own prior invented design).

## Known deviation found and fixed this pass

iOS's existing `DashboardView.swift` hero was **not** this design — flat `Color.accent` (terracotta) background with an invented "Assets / Liabilities" split that doesn't exist anywhere in the web source. Replaced to match this spec exactly (gradient, toggle, delta pill, sparkline, footer line) as part of this change.

## Explicitly deferred (tracked separately, not silently dropped)

- 12-tile customizable grid (`apps/web/src/dashboard/tiles.tsx`) + drag/resize/edit-mode UX (`DraggableGrid`, `AddWidgetModal`).
- `Walkthrough` first-run overlay component.
- Loading-skeleton exact shapes (a simple spinner/placeholder is acceptable for now; not pixel-matched this pass).
