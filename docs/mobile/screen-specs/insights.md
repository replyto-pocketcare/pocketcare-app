# Insights — mobile screen spec

Source-verified from `apps/web/app/insights/page.tsx` (47 lines), `src/insights/{types,generators,useInsightStack}.ts` (86+422+274 lines), `src/ui/feed/{InsightCard,Charts2D,InsightFeed,ProgressRail}.tsx` (113+125+224+37 lines), `src/market/dividends.ts` (89 lines), `packages/core/mindfulness/src/index.ts` (92 lines), `src/entitlement.ts` (79 lines). Written 2026-08-06 for task #28. This is the largest screen ported so far — 18 pure generator functions producing up to 12 ranked "insight cards", each with a headline/metric/bullets and one of 5 chart visual kinds.

## Why this is bigger than Loans/Budgets/Goals

Every other screen ported so far maps roughly 1:1 to a data-entity CRUD form. Insights is a **derived analytics feed**: it reads ~9 tables, computes ~20 aggregate shapes in memory, feeds them through 18 independent pure "generator" functions (each either returns 0 or 1 card, or a handful), ranks + dedupes the results by a cadence key, and renders the top 12 as swipeable full-screen cards — each with its own chart. There is no create/edit/delete here; it's 100% read + compute + visualize.

**Current mobile state (both platforms) is entirely fake** and must be deleted, not extended: Android's `ui/insights/InsightsViewModel.kt` and iOS's `InsightsViewModel.swift`/`InsightsView.swift` hardcode a nonexistent "StreamTV" subscription and a made-up "dining" keyword heuristic — neither reads real budgets/goals/categories/labels/subscriptions/holdings, neither produces anything resembling web's real cards. iOS's version (unlike Android's orphaned one) **is** wired into `MainTabView.swift` as a live bottom tab — the replacement must keep that tab wired, not disconnect it.

## Entitlement gate (new pattern — first mobile call site)

Web gates the whole page behind `useEntitlement().isPaid` (`src/entitlement.ts`): reads the single `entitlements` row (`SELECT tier, premium_trial_start_date, ... FROM entitlements LIMIT 1`), normalizes `tier` to `free|lite|pro` (`"premium"` legacy value maps to `"pro"`), takes the higher of that and any active `comp_tier` (a redeemed coupon, valid while `comp_until > now`), and additionally treats a 14-day-old-or-less `premium_trial_start_date` as paid even on the free tier. `isPaid = effective !== "free" || isTrial`.

`domain/entitlements/Entitlements.kt`/`.swift` already has `canUse(feature, tier)` / `Feature.AdvancedAnalytics` ported (P1.7a) but **no mobile screen has ever called it** — this is the first. Insights' own gate is closer to web's raw `isPaid` (tier+trial+comp, not the free-feature-allowlist `canUse`), so port a small `isPaid(tier, premiumTrialStart, compTier, compUntil, now): Boolean` pure function into the same `Entitlements.kt`/`.swift` file (mirrors `normalize`/rank/trial logic above, ~15 lines) rather than reusing `canUse` directly. Read the `entitlements` table via a new tiny repository method (`PrefsRepository.watchEntitlement(): Flow<EntitlementRow?>` or a new `EntitlementsRepository`, real `db.watch()`, one row, `LIMIT 1`) rather than adding a whole quota/billing UI — only `tier`, `premium_trial_start_date`, `comp_tier`, `comp_until` are needed for the boolean gate itself (do read+expose the other quota columns on the row struct for future reuse, but nothing else consumes them yet).

Locked-state UI (`InsightsPage`'s `!isPaid` branch): a centered card with a lock icon, "Unlock insights" headline, a short body line, and a button to `/settings` (mobile: whatever the existing Settings/upgrade route is called on each platform). No page title otherwise — the feed itself has no page chrome (web sets `document.body.dataset.fullbleed`; mobile equivalent is simply: no `TopAppBar`/`NavigationTitle`, full-bleed `Scaffold`/`View`).

## Data aggregation (`useInsightStack.ts` → mobile equivalent)

Web runs 14 raw SQL aggregate queries reactively via `useQuery`. Mobile should **not** try to replicate all 14 as raw-SQL `db.watch()` queries verbatim — instead, watch the underlying tables' full row sets (most already have a `watch*()` repository method; a few are new, listed below) and compute the same aggregates **in Kotlin/Swift** from the in-memory lists. This is architecturally simpler (one join/group-by helper instead of 14 fragile hand-written SQL strings per platform) and equivalent in output for the row volumes a personal-finance app has. It also gets list-staleness fixed "for free" from day one (matching the Goals/Budgets fix earlier this session) since every input is a real `db.watch()` stream, not a one-shot snapshot.

**Tables needed, one `watch*()` stream each** (✅ = repository method already exists and can be reused as-is; 🆕 = needs a new method, same file/pattern as its siblings):
- ✅ `transactions` — `LedgerRepository.watchAllTransactions()` (Android) / iOS equivalent — gives `type`, `amount` (minor), `currency`, `category_id`, `occurred_at`, `description`, `note`.
- ✅ `categories` — `LedgerRepository.watchCategories()`.
- ✅ `transaction_labels` ⋈ `labels` — Android already has `LedgerRepository.watchTransactionLabelNames(): Flow<Map<transactionId, List<labelName>>>`; port the equivalent raw-JOIN `watch()` to iOS if missing (check `LedgerRepository.swift` first — it may already exist under a different name).
- ✅ `budgets` — `BudgetRepository.watchBudgets()`.
- 🆕 `budget_categories` — a raw `SELECT budget_id, category_id FROM budget_categories` watch, both platforms (BudgetRepository already has *some* per-budget category lookup per the Budgets screen work — check `categoryIds()` first; if it's one-shot/per-id, add a bulk `watchBudgetCategories(): Flow<List<Pair<budgetId, categoryId>>>` instead of N one-shot calls).
- ✅ `goals` + `goal_allocations` — `GoalsRepository.watchGoals()` / `watchAllocations()` (added this session for the staleness fix — already real `db.watch()` on both platforms).
- 🆕 `subscriptions` — no repository reads this table anywhere yet. Add `SubscriptionsRepository.watchActive(): Flow<List<SubscriptionRow>>` (`SELECT id, name, amount, currency, billing_cycle FROM subscriptions WHERE deleted_at IS NULL AND is_active = 1`), matching the `Loan`/`Budget` repository-file shape (mapper fn, real `db.watch()`). Columns: `name: String?`, `amount: Long` (minor), `currency: String`, `billing_cycle: String?` (`weekly|monthly|quarterly|yearly`, null = monthly).
- ✅ `holdings` — `InvestmentsRepository.watchHoldings()`.
- 🆕 `market_dividends` — add `InvestmentsRepository.watchDividends(): Flow<List<DivRow>>` (`SELECT symbol, exchange, ex_date, pay_date, amount, currency FROM market_dividends`, global/read-only table, no `user_id`/`deleted_at` filter — matches web's query exactly).
- 🆕 `market_quotes` — add `InvestmentsRepository.watchQuotes(): Flow<List<QuoteRow>>` (`SELECT symbol, exchange, price, currency FROM market_quotes`).
- ✅ rates — `LedgerRepository.watchRates(): Flow<RateLookup>` (Android); iOS's `rates()` is one-shot per the staleness-bug research this session — for Insights, call it once per rebuild pass (acceptable: exchange rates change daily, not per-keystroke; matches web's own `useRates()` which is a plain closure, not itself reactive to a specific rate row).
- ✅ base currency — hardcode `"INR"` (matches every other screen's established simplification; there is still no mobile `useBaseCurrency` equivalent).

**Android**: combine all these `Flow`s with `combine(...)` (the same pattern used for Goals/Budgets this session — N flows in, one `collect` that rebuilds the UI state). **iOS**: the established "N parallel `Task`s writing into cached `latest*` vars + a shared `rebuild()` call" pattern from `GoalsViewModel.swift` (this session's staleness fix) — do NOT attempt a single `combineLatest`-equivalent; Swift's `AsyncSequence` has none, and this codebase's precedent is explicit per-stream `Task`s.

### In-memory aggregation logic (mirrors `useInsightStack.ts` exactly — build these from the raw watched lists, in this order)

Let `now = current instant`, `thisM = "yyyy-MM"` for the current month, `thisM` computed from `now`.

1. **`days: List<DayAgg>`** — 14 entries, one per day from `now-13d` to `now` inclusive (ascending). `DayAgg(day: "yyyy-MM-dd", income: Long, expense: Long)`. For each transaction with `type in (income,expense)` and `occurred_at` date within the window, bucket by `date(occurred_at)` and sum `amount` into `income` or `expense`. Missing days get `0`/`0` (the continuous-series requirement — web does this by seeding a `Map` then iterating `i in 13..0`).
2. **`months: List<MonthAgg>`** — 8 entries, `now`'s month back 7 months (ascending), same income/expense sum bucketed by `yyyy-MM`, continuous (zero-filled gaps).
3. **`cats: List<CatAgg>`** — this month's expense transactions grouped by `category_id` → `categories.name` (fallback `"Uncategorised"` for null `category_id` or a category not found), sorted descending by expense total. `CatAgg(name, expense: Long)`.
4. **`labels: List<CatAgg>`** — this month's expense transactions joined through `transaction_labels`→`labels`, grouped by label name, sorted descending, **capped to top 8**.
5. **`budgets: List<BudgetAgg>`** — from `budgets` where `period` is null or `"monthly"`. For each, look up its `budget_categories` rows; if it has scoped categories, `spent = sum(catExpense[cid] for cid in scoped)` (using the per-category-id expense map built alongside step 3, keyed by `category_id` not name); if no scoped categories, `spent = totalMonthExpense` (sum of all `cats`). `BudgetAgg(name: name?.trim() ?: "Budget", limit: Long, spent: Long)`.
6. **`streak: Int`** — consecutive-day logging streak ending today (or yesterday if nothing logged today yet): count distinct transaction-dates in the last 30 days into a day-set, then walk backward from today (or yesterday if today has none) while each day is present, incrementing a counter.
7. **`txnDays7: List<{day, count}>`** — last 7 days' transaction counts (any type), continuous/zero-filled, ascending.
8. **`topExpenses: List<TopExpense>`** — this month's expense transactions, `label = (description ?: note ?: "Expense").trim()`, sorted descending by `amount`, capped to top 6. `TopExpense(label, amount: Long)`.
9. **`weekday: List<SeriesPoint>`** (7 points, Sun..Sat) — average expense per weekday over the **last 60 days**: sum expense-by-date into a day→total map first, then for each of the 60 days accumulate into `wdSum[weekday]`/`wdCnt[weekday]`, `value = major(wdSum/wdCnt)` (0 if count is 0). `weekdayTop` = the label of the max-value point.
10. **month pace** — `dayOfMonth`, `daysInMonth` (actual days in current month), `thisSoFar` (sum of this-month expense up to and including today), `spendDays` (count of days 1..dayOfMonth with nonzero expense), `cumulative: List<SeriesPoint>` (running total per day-of-month, label = day number as string), `lastSameSoFar` (last month's expense sum for the same day-count window), `lastFull` (last month's full-month expense total), `daysInLastMonth`.
11. **`noSpend`** — `noSpendDays = max(0, dayOfMonth - spendDays)`, `daysElapsed = dayOfMonth`.
12. **`avgDaily`** — `thisAvg = thisSoFar / dayOfMonth` (0 if dayOfMonth is 0), `lastAvg = lastFull / daysInLastMonth`.
13. **`subs: List<SubAgg>`** + **`subsTotal`** — active subscriptions, monthly-normalised (`yearly → /12`, `weekly → *52/12`, `quarterly → /3`, else unchanged), `SubAgg(name: name?.trim() ?: "Subscription", monthly: Long)`, `subsTotal = sum(monthly)`.
14. **`goals: List<GoalAgg>`** — `GoalAgg(name: name?.trim() ?: "Goal", target: Long, saved: Long, emergency: Boolean)`; `saved` = sum of that goal's non-deleted `goal_allocations.amount_blocked`.
15. **`catSpike`** — needs a **4-month category history** (this month + 3 prior, expense transactions grouped by category+month — a 5th aggregate query in web, `catMonthRows`; add this as its own grouping pass over the same `transactions` list filtered to `occurred_at >= now - 4 months`, grouped by `(category, ym)`). For each category with both a this-month total and ≥1 prior-month total: `avgPrior = mean(prior totals)`; skip if `avgPrior <= 0` or `thisMonth < avgPrior * 1.3` or `thisMonth < 5000` (50 units in minor currency — i.e. ignore tiny spikes); keep the single category with the highest `thisMonth/avgPrior` ratio, or `null` if none qualify.
16. **`invest` (dividends + projection)** — see the Dividends section below; both are `null`/absent if `holdings.isEmpty()`.
17. **`mindfulnessTxns`** — expense transactions from the last 30 days, or with a non-null `intent`, mapped to `TransactionForInsight(id, amount, currency, occurredAt, intent, categoryId)`.

`major(minor) = round(minor) / 100.0`. `pct(a, b) = if (b == 0) (if (a > 0) 100 else 0) else round(((a - b) / abs(b)) * 100)`.

## Domain math to port (pure, both platforms — `Domain`/`domain` layer)

### `Dividends.kt` / `Dividends.swift` (port of `src/market/dividends.ts`, 89 lines, verbatim)
- `HoldingLite(symbol, exchange: String?, quantity: Double, currency: String)`, `DivRow(symbol, exchange: String?, exDate: String, payDate: String?, amount: Long, currency: String)`, `DivEvent(date: String, base: Long, upcoming: Boolean)`.
- `computeDividendEvents(holdings, dividends, getRate: (from,to)->Double, base: String): List<DivEvent>` — for each dividend row, match holdings by `symbol+exchange` first, fall back to `symbol`-only; sum matched `quantity`; skip if 0; `inCcy = amount * shares`; convert to base via `getRate` (rate=1 if already base); `upcoming = exDate >= today`. Sort ascending by date.
- `Period = week|month|quarter|year|all`; `Bucket(label, key, value: Long, upcoming: Boolean)`.
- `bucketize(events, period): List<Bucket>` — group by ISO-week / `yyyy-MM` / `yyyy-Qn` / `yyyy` (year & all both bucket by year), summing `value` and OR-ing `upcoming`; sort by key; cap to the last N per period (`week:12, month:12, quarter:8, year:6, all:999`).
- `dividendSummary(events): {trailing12: Long, upcoming12: Long, total: Long}` — `total` = sum of all; `trailing12` = sum where event date is in `[now-365d, now]`; `upcoming12` = sum where event date is in `(now, now+365d]`.

### `Mindfulness.kt` / `Mindfulness.swift` (port of `packages/core/mindfulness/src/index.ts`, 92 lines, verbatim — including its own acknowledged naivety, don't "improve" it)
- `TransactionForInsight(id, amount: Long, currency, occurredAt: String, intent: String?, categoryId: String?)`, `Insight(id, type, title, body, severity: "info"|"warn"|"success"|null)`.
- `computeTier1Insights(txns): List<Insight>` — empty if no txns. **Late-night spending**: count txns whose `occurred_at` UTC hour is `>= 22 || < 4`; if `> 0`, one insight (`id="late_night_spending"`, title "Late-night spending", body `"You logged $n transaction(s) between 22:00 and 04:00."`, severity info). **Small-purchase drift**: txns with `amount < 20000` (200 units minor); if `count > 5`, one insight (`id="small_purchase_drift"`, body `"You had $n spends under 200, totaling ${totalSmall/100}."`, severity info).
- `computeTier2Insights(txns): List<Insight>` — `tagged = txns where intent in (need, greed)`; if `tagged.size < 20` return empty. `ratio = greedAmount / taggedAmount * 100` (0 if taggedAmount is 0); one insight (`id="greed_ratio"`, title "Greed ratio", body `"${ratio.round}% of your tagged spending was marked as Greed."`, severity `warn if ratio>50 else success`).

### `Insights.kt` / `Insights.swift` (port of `src/insights/types.ts` + `generators.ts`, ~500 combined lines)

**Types** (mirror `types.ts` exactly, using primitives — no UI framework types in Domain):
```
SeriesPoint(label: String, value: Double, color: String? = null)
InsightTheme = positive | warning | neutral | celebratory
VisualSpec (sealed/enum):
  Bars(series: List<SeriesPoint>, unit: String? = null, horizontal: Boolean = false)
  Area(series: List<SeriesPoint>)
  Donut(series: List<SeriesPoint>, centerLabel: String? = null, centerSub: String? = null)
  Gauge(value: Double, max: Double, warnAt: Double? = null, dangerAt: Double? = null, unit: String? = null, centerLabel: String? = null)
  Progress(value: Double, target: Double? = null, centerLabel: String? = null)
InsightMetric(display: String, raw: Double? = null, deltaPct: Int? = null, direction: "up"|"down"|"flat"|null = null)
InsightCta(label: String, target: String)
InsightCard(id, type: String, theme: InsightTheme, generatedAt: String, periodStart: String, periodEnd: String,
            priority: Int, headline: String, subhead: String? = null, bullets: List<String>,
            metric: InsightMetric? = null, visual: VisualSpec, cta: InsightCta? = null,
            cadenceKey: String, cadenceFrequency: String)
```
`INSIGHT_PALETTE = ["#b06a4f","#5f7a52","#c08a3e","#9cae8e","#3e4a38","#c98a72","#7c7264","#5f6647"]` (fixed hex, theme-invariant — same list in both light/dark, matches web's literal array, not a CSS var).

**`GenContext`** — bundles every aggregate from the section above, plus `currency: String`, `now`, `dividends: DividendAgg?`, `projection: ProjectionAgg?`, `mindfulnessTxns: List<TransactionForInsight>?`. `DividendAgg(holdings: Int, trailing12: Long, upcoming12: Long, total: Long, buckets: List<SeriesPoint>)`. `ProjectionAgg(holdings: Int, currentValue: Long, endValue: Long, contributed: Long, years: Int, growthPct: Int, series: List<SeriesPoint>)`.

**18 generator functions**, each `(GenContext) -> List<InsightCard>` — port every one of these **exactly**, including the numeric thresholds (they're load-bearing, not decorative):

1. `genWeeklySummary` — last 7 of `days`; skip if `<3`. `inc/exp` = 7-day sums, `net = inc-exp`. Compares to the prior 7-day window (`prevNet`). Headline: "You saved X this week" (net≥0) or "You spent X more than you earned". Visual: `area`, series = each day's `net` (income-expense), labelled by weekday short name. Priority 92.
2. `genBudgetWarnings` — budgets where `spent/limit >= 0.8`, sorted by ratio desc, **top 2**. Over-limit (`spent>limit`) → priority 100, "X budget is over by Y"; else priority 96, "X budget is Y% used". Visual: `gauge(value=spent, max=limit, warnAt=limit*0.8, dangerAt=limit)`. CTA → budgets screen.
3. `genSavingsAchievement` — latest month; skip if `net<=0 || income<=0`. `rate = round(net/income*100)`. "You saved X in {month}" / subhead "{rate}% savings rate". Visual: `progress(value=net, target=income)`. Priority 84.
4. `genSpendingTrend` — last 6 months, skip if `<4`. Split in half, compare recent-half avg expense vs older-half avg. "trending down"(positive)/"creeping up"(warning). Visual: `area`, series = each month's expense. Priority 72.
5. `genCategoryBreakdown` — top 6 nonzero `cats`, skip if `<2`. "Where your money went" / "{lead} led at X". Visual: `donut`, centerLabel = total formatted. Priority 62.
6. `genStreak` — skip if `streak<3`. "{n}-day logging streak". Visual: `bars`, series = `txnDays7` counts by weekday. Priority 55.
7. `genBiggestExpense` — top 5 nonzero `topExpenses`, skip if empty. "Your biggest expense was X" / subhead = its label. Visual: `bars(horizontal=true)`, series = the 5 (label truncated to 16 chars +"…"). Priority 68.
8. `genWeekdayPattern` — skip if `<3` nonzero weekday points. "{weekdayTop} is your priciest day". Visual: `bars`, series = full 7-point `weekday`. Priority 50.
9. `genLabelBreakdown` — top 6 nonzero `labels`, skip if `<2`. "Spending by label". Visual: `donut`. Priority 54.
10. `genSubscriptions` — skip if no active subs. Top 6 by monthly cost. "X/mo on subscriptions" / "{n} active subscriptions". Visual: `donut`. CTA → subscriptions screen (if one exists on mobile; else omit the CTA — no dead link). Priority 64.
11. `genMonthPace` — skip if `dayOfMonth<3 || lastSameSoFar<=0`. `projected = thisSoFar/dayOfMonth*daysInMonth`. "spending faster"(warning)/"pacing under"(positive) than last month. Visual: `area`, series = `cumulative`. Priority 74.
12. `genNoSpendDays` — skip if `daysElapsed<5`. "{n} no-spend days this month". Visual: `donut` 2-slice (no-spend=positive color, spent=border color). Priority 48.
13. `genGoalProgress` — skip if no goal has `target>0`. Prefer the closest-to-done unfinished goal, else the emergency-fund goal, else the first eligible. `ratio=min(1,saved/target)`. "{n}% funded" or "fully funded!" if ≥100%. Visual: `gauge(value=saved,max=target)`. CTA → goals screen. Priority 60.
14. `genCategorySpike` — skip if `catSpike==null`. "X spending jumped {up}%". Visual: `bars`, 2 bars (Usual=forest color, This mo=warning color). CTA → transactions screen. Priority 78.
15. `genAvgDaily` — skip if `dayOfMonth<3` or both averages are 0. "You're averaging X/day". Visual: `bars`, 2 bars (Last mo=forest, This mo=accent). Priority 52.
16. `genDividends` — skip if `dividends==null || holdings==0 || total<=0`; skip if all buckets are zero (after taking last 8 nonzero buckets). "X in dividends this year" (if trailing12>0) else "...so far". Visual: `bars`, series = the buckets. CTA → investments screen. Priority 66.
17. `genProjection` — skip if `projection==null || holdings==0 || currentValue<=0`. "Your portfolio could reach X" / "In {years} years at {growthPct}% a year". Visual: `area`, series = the projection series. CTA → investments screen. Priority 59.
18. `genMindfulness` — skip if `mindfulnessTxns==null`. Runs `computeTier1Insights` + `computeTier2Insights`, maps each `Insight` to an `InsightCard` with **no visual** (or a blank/text-only visual — web has none; render these cards without a chart, text block only) — `theme = warn→warning, success→positive, else neutral`; `priority = 80 if tier2 else 45`; `subhead = "Need vs Greed"` (tier2) or `"Spending Insight"` (tier1); `bullets = [insight.body]`.

**`composeStack(ctx, limit=12)`**: run all 18 generators, flat-map results; dedupe by `cadenceKey` keeping the higher-priority card per key; sort descending by priority; take the top `limit`.

`fmt(minor, currency)` — reuse each screen's existing local `formatMoney(minor, currency)` helper (no shared one exists yet, per this session's convention — see AUDIT_HISTORY).

## Chart rendering (`Charts2D.tsx` → native Canvas, both platforms)

No charting library exists on mobile yet — draw these 5 kinds with plain `Canvas` (Compose `androidx.compose.foundation.Canvas` / SwiftUI `Canvas`), matching the geometry below (colors from `card.theme`'s accent token → `colors.positive|warning|accent|forest`, per `THEME_TOKEN`):

- **`bars`** (vertical): one bar per `SeriesPoint`, height ∝ value/max(values), rounded top corners, each bar tinted by its own `color` if set else `INSIGHT_PALETTE[i % 8]`; value label above each bar.
- **`bars` horizontal**: one bar per point, width ∝ value/max, rounded right corners, label at left, value at right, single accent-gradient fill (or flat accent — gradients are a nice-to-have, not required).
- **`area`**: a smooth (or straight-segment, acceptable simplification) line through the series, accent-colored stroke, gradient/solid fill under the curve fading to transparent.
- **`donut`**: ring chart, inner radius ≈62% of outer, segments in palette order (or explicit `color`), small gap between segments; center text = `centerLabel`/`centerSub`.
- **`gauge`**: a 240°-sweep arc (start 210°, end -30°, i.e. opens at the bottom) background track in `colors.border`, foreground arc filled to `value/max` ratio, colored `negative` if `value>=dangerAt`, `warning` if `value>=warnAt`, else accent; center text = `centerLabel` or the rounded percentage.
- **`progress`**: a full 360° ring (starts at top, clockwise) background track + foreground arc to `value/target` ratio, accent-colored; center text = `centerLabel` or rounded percentage.

Card layout (`InsightCard.tsx`, mobile-only — there is no desktop coverflow variant on phones): full-viewport-height card, chart in the top ~55-60%, a bottom sheet-like content card with an uppercase type-label chip, headline (large), optional subhead, optional big metric number + delta pill (▲/▼ colored positive/negative), a bulleted list, and an optional CTA button that navigates to the target screen.

## Feed UI (`InsightFeed.tsx`'s mobile `SnapFeed` → native paging)

Mobile web uses vertical scroll-snap, one card per viewport, `IntersectionObserver` tracking which card is "active" for the progress rail. Native equivalent: a vertical pager showing exactly one `InsightCard` per screen (Android: `androidx.compose.foundation.pager.VerticalPager`; iOS: a `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))` rotated, or a paged `ScrollView` — whichever is the established idiom for the target Compose/SwiftUI versions in this codebase; check for an existing full-screen pager precedent first, e.g. onboarding, before introducing a new one).

`ProgressRail` → a vertical stack of thin pill segments (one per card, filled up to `activeIndex`, matches web's `i <= activeIndex ? accent : border`), pinned to one side of the screen. Bottom pill: `"{activeIndex+1} of {total}"` + `"{remaining} left"` or `"all caught up"`.

Empty state (`total==0`): centered card, insights icon, "Your stack is empty for now" / "Add a few transactions and Sanvya will start surfacing weekly recaps, budget alerts and savings wins here."

## Nav wiring
- Android: `NavDrawer.kt`'s `DrawerNavItem("Insights", Icons.Default.Insights, comingSoonRoute("Insights"))` → route literal `"insights"`; add `composable("insights") { InsightsScreen(...) }` to `SanvyaNavHost.kt` (same shape as the Loans entry added this session).
- iOS: replace the existing fake `InsightsView`/`InsightsViewModel` in place — keep the `MainTabView.swift` tab wiring exactly as-is (`case .insights: InsightsView(...)`), only the view/viewmodel internals change.

## Edge cases (carried over from `docs/features/insights.md`, still apply)
- Charts stay unmasked even when "hide amounts" is on — this is an explicit analytics surface the user navigated to, unlike Dashboard tiles which mask.
- `genDividends`/`genProjection` both hard-require `holdings.holdings > 0` even though the payload could theoretically be computed at 0 — the guard is the first check in each generator, not an afterthought.
- The projection falls back to `avgCost` per share when no quote exists for a symbol (freshly-added holdings still project).
- Both investment generators and their underlying `Dividends.kt`/`.swift` math are being ported to mobile **for the first time** here — Investments (task #26/#40) never actually built the Dividend/Projection panels despite its own spec listing them; that gap is out of scope for this task (Insights only needs the read-only card math, not the interactive `/investments` panels with sliders) but is worth flagging for a future task.
