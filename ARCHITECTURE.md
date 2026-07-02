# PocketCare — Architecture & Implementation Plan

> Cross-device, offline-first personal expense & wealth manager.
> Theme: earthy, minimal, elegant animations. Freemium.
> This document is the source of truth for design decisions. `PROJECT_REFERENCE.md` is the living index used in future sessions.

---

## 1. Tech Stack (decided)

| Layer | Choice | Why |
|---|---|---|
| Monorepo | **Turborepo + pnpm workspaces** | Share core logic across mobile + web; one place for types, money, finance, data |
| Mobile app | **React Native + Expo** (dev build / CNG, not Expo Go) | One TS codebase for iOS/Android; native modules for widgets/wearables |
| Web app | **Next.js (App Router)** + PowerSync **Web SDK** (WASM SQLite) | Proper responsive/keyboard-first web experience, same offline-first data layer, same Supabase backend |
| Language | **TypeScript** (strict) | Type safety on financial logic |
| Local DB | **SQLite via PowerSync** (native on mobile, **WASM** in browser) | Local-first reads/writes, instant reactivity, offline on both platforms |
| Sync | **PowerSync** ↔ **Supabase Postgres** | Offline-first with a server-authoritative sync layer and conflict handling — the safest option for financial data |
| Backend | **Supabase** (Postgres, Auth, Storage, Edge Functions, RLS) | Auth, row-level security, realtime, managed Postgres |
| State/UI | Zustand (UI state) + PowerSync reactive queries (data) | Keep server data out of client state stores |
| Animations | Reanimated 3 + Moti + Gesture Handler; **Skia** for charts | 60fps, custom elegant motion |
| Charts | Victory Native XL / Skia-based | Expense, cashflow, category, comparison graphs |
| Widgets | iOS **WidgetKit** (Swift) + Android **App Widget** (Kotlin) via Expo config plugins (e.g. expo-apple-targets); data shared via App Group / shared prefs | Home-screen balances, shortcuts, budget/goal progress |
| Wearables | watchOS + Wear OS companion targets | Balances + quick-add transaction |
| i18n | **i18next + react-i18next** (shared package) + expo-localization | One translation layer for mobile + web; runtime locale switch |
| l10n formatting | **Intl** (`NumberFormat`, `DateTimeFormat`, currency style) | Locale-correct numbers, dates, currency symbols/placement |
| Payments | RevenueCat (App Store / Play billing) | Freemium entitlements across stores |
| Notifications | expo-notifications + Supabase Edge Functions (scheduled) | Budget thresholds, bills, subscriptions |

**Key constraints:**
- Mobile: PowerSync needs native modules → use a **development build** (CNG), never Expo Go.
- Web: PowerSync runs SQLite as **WASM in the browser**; **no SSR** for the synced DB (client-side data only). Next.js webpack must enable `asyncWebAssembly` + `topLevelAwait`. Marketing/auth pages can still be SSR/SSG; the app shell hydrates client-side.
- **~90% of business logic is platform-agnostic** and lives in shared packages consumed by both apps.

---

## 2. Money-Handling Rules (non-negotiable — financial integrity)

1. **All monetary values are integers in minor units** (e.g. paise/cents). Never floats. A `Money` type wraps `{ amount: bigint|number(int), currency: string }`.
2. **Balances are derived from an append-only ledger**, not stored as a mutable number that gets incremented. This prevents drift and makes sync conflicts non-destructive.
3. **Initial/opening balance is itself a ledger entry** (an `opening_balance` transaction), so "set/update initial balance at any time" = insert an adjustment entry. History is never rewritten.
4. **Every transaction is atomic locally**: the transaction row + its breakdown items are written inside one SQLite transaction. Partial writes are impossible.
5. **Breakdown items must sum to the transaction total** — enforced both client-side (before commit) and server-side (Postgres `CHECK`/trigger). Reject otherwise.
6. **Transfers are double-sided**: one logical transfer produces balanced ledger effects on source and destination accounts. For **cross-currency transfers**, the exact rate used is captured on the transaction (`fx_rate`, `to_amount`) so both sides reconcile exactly — no rounding leak.
7. **Sync conflict policy:** server-authoritative. Ledger entries are immutable once synced; corrections are new compensating entries. This makes last-write-wins safe because we never mutate money in place.

### Multi-currency rules
8. **Every amount is stored in its account's native currency** (minor units) alongside its ISO 4217 code. Stored amounts are **never** converted-in-place.
9. **Conversion happens only at display/aggregation time** (net worth, cross-account budgets/goals) using a rate from `exchange_rates`, and the source amount stays intact.
10. **Historical accuracy:** aggregate views use the rate **as-of** the relevant date (rate snapshots), so past net-worth figures don't retroactively change when today's rate moves. A "convert at today's rate" toggle is offered for at-a-glance current value.
11. Each user has a **base/display currency** (`profiles.base_currency`); all roll-ups normalize to it. Per-account and per-transaction currencies are preserved.

---

## 3. Offline-First Sync Model

```
 [ RN App ]  --writes-->  [ Local SQLite ]  <--PowerSync-->  [ Supabase Postgres ]
     ^                          |  (reactive queries)              |
     |                          v                                  v
   UI reads always from local SQLite            RLS enforces per-user isolation
```

- **Writes** go to local SQLite immediately (optimistic, instant UI). PowerSync's upload queue streams them to Supabase in order, with retry. Guaranteed at-least-once, ordered per client.
- **Reads** are always local → app is fully usable offline (view balances, add transactions, set budgets/goals).
- **Sync Rules** (PowerSync config) scope each user to only their rows.
- **Background sync** via expo-background-task so data is fresh on open.
- **Entitlement checks** (freemium) also cached locally so gating works offline; validated on reconnect via RevenueCat + Supabase.

---

## 4. Data Model

Postgres tables (mirrored to local SQLite). All tables carry `id (uuid)`, `user_id`, `created_at`, `updated_at`, `deleted_at` (soft delete for sync).

### Accounts & Ledger
- **accounts** — `name`, `type` (`savings|current|credit_card|cash|mutual_funds|stocks`), `currency`, `icon`, `color`, `is_archived`.
- **transactions** — `account_id`, `type` (`income|expense|transfer|opening_balance|adjustment`), `amount` (minor units), `currency` (ISO 4217, = account currency), `category_id`, `label`, `note`, `occurred_at`, `transfer_group_id` (links the two sides of a transfer), `to_account_id`, `to_amount` (for cross-currency transfers), `fx_rate` (rate captured at transfer time).
- **transaction_items** — `transaction_id`, `description` (default "Item 1"…), `amount`. Sum(items) == transaction.amount (constraint).
- **categories** — `name`, `type` (`income|expense`), `icon`, `color`, `is_system`. User-editable in Settings.

> Account balance = SUM of signed ledger effects for that account. A cached `balance` column may be maintained by a Postgres trigger for performance, but the ledger is authoritative.

### Budgets
- **budgets** — `scope` (`overall|category|label`), `scope_ref`, `period` (`daily|weekly|monthly|yearly`), `limit_amount`, `threshold_pct` (e.g. 80), `rollover` (bool). Notifications fire when spend crosses threshold.

### Credit Cards
- **credit_card_details** — `account_id`, `statement_day`, `due_day`, `credit_limit`.
- Bill settlement = a **transfer** transaction from a chosen account to the credit-card account (records only; does not pay a real bill).

### Goals & Emergency Fund
- **goals** — `name`, `target_amount`, `priority`, `is_emergency_fund` (bool), `target_date` (optional).
- **goal_allocations** — `goal_id`, `source_account_id`, `amount_blocked`. Money is "blocked" from a **savings** account.
- Rules: the emergency-fund goal is **always filled first**; other goals cannot receive allocations until it's funded. **Emergency fund is NOT blocked** from the savings account (it stays liquid but tracked); all other goals block their allocation.
- Balance views: **available balance** (minus blocked) vs **total balance** (with blocked) — a global toggle.

### Loans & Recurring Commitments
- **loans** — `principal`, `interest_rate`, `tenure_months`, `emi_amount`, `start_date`, `lender`.
- **recurring_commitments** — `kind` (`emi|subscription|recurring_expense`), `amount`, `frequency` (`daily|weekly|monthly|yearly`), `next_due`, `category_id`, `account_id`, `loan_id` (nullable), `subscription_id` (nullable). Auto-generates transactions on due date.
- Analysis: total recurring/month + **% of monthly income**.

### Subscriptions
- **subscriptions** — `name`, `amount`, `billing_cycle`, `next_renewal`, `category_id`, `is_active`. A subscription is also surfaced as a `recurring_commitment`.
- **Subscription impact simulator** (pre-purchase, feature #11): given amount + cycle, project cumulative cost and opportunity cost (what that money would grow to if invested/saved) over 1/3/5/10 yrs. Pure client calc, no row needed until they subscribe.

### Investments (Stocks / Mutual Funds)
- **holdings** — `account_id`, `symbol`, `quantity`, `avg_cost`, `auto_fetch` (bool toggle, feature #12).
- **price_snapshots** — `symbol`, `price`, `as_of`. Daily fetch via Supabase Edge Function (only for `auto_fetch = true`).
- Net-worth toggle: include/exclude investment mark-to-market (feature #12).

### Currency & Localization
- **exchange_rates** — `base_currency`, `quote_currency`, `rate`, `as_of` (date). Populated daily by an Edge Function; used for display/aggregation only. Local cache enables offline conversion at last-known rate.
- Amounts everywhere carry an ISO 4217 `currency`; conversion is a pure function `convert(amount, from, to, asOf)` in `packages/core/money`.
- **Translations** live as static JSON bundles in `packages/core/i18n` (not a DB table); user-defined data (category/label names) is stored verbatim and not translated — only system defaults are.

### Platform / Meta
- **profiles** — user prefs, `base_currency` (display), `locale` (language + region), `rate_mode` (`historical|current`), theme, net-worth toggles.
- **entitlements** — `tier` (`free|premium`), `source` (RevenueCat), `expires_at`. Cached locally.
- **guest_sessions** — `user_id` (anonymous auth UID), `device_id`, `created_at`, `expires_at` (created_at + 3 days). Drives the register nudge; scheduled job purges expired anonymous users. See §9 for the full guest→registered→delete lifecycle. Every table FKs `user_id` with `ON DELETE CASCADE`.
- **statements** — generated period statements (feature #17); PDFs stored in Supabase Storage.

---

## 5. Feature → Design Map (all 21 covered)

| # | Feature | Where it lives |
|---|---|---|
| 1 | Multiple accounts | `accounts` |
| 2 | 6 account types | `accounts.type` enum |
| 3 | Set/update initial balance anytime | `opening_balance`/`adjustment` ledger entries |
| 4 | Income/expense/transfer + category + label + breakdown | `transactions` + `transaction_items` (sum constraint) |
| 5 | Budgets D/W/M/Y + threshold notifications | `budgets` + notification engine |
| 6 | Credit card billing cycle + settle-up | `credit_card_details` + transfer txn |
| 7 | Goals with forced emergency fund first | `goals.is_emergency_fund` + priority rule |
| 8 | Save via blocking from savings (EF not blocked) | `goal_allocations` |
| 9 | Balance with/without blocked | available vs total balance toggle |
| 10 | Subscriptions + financial impact analysis | `subscriptions` + analytics |
| 11 | Pre-purchase subscription simulator | client projection tool |
| 12 | Stocks/MF daily fetch toggle + wealth toggle | `holdings.auto_fetch`, `price_snapshots`, net-worth toggle |
| 13 | Dashboard: accounts, net worth, records, graphs | Home screen + chart suite |
| 14 | Loans + recurring EMI/expenses + % of income | `loans`, `recurring_commitments`, analysis |
| 15 | Time-to-save with compounding | goal projection engine (FV formula) |
| 16 | "+" sub-item calculator on amount entry | transaction entry UI + item builder |
| 17 | Search records + generate period statements | search index + `statements` (PDF) |
| 18 | Onboarding + 3-day guest then purge | onboarding flow + `guest_sessions` |
| 19 | Freemium | `entitlements` + gating |
| 20 | Free expense tracking, paid advanced analysis | feature-flag gating table |
| 21 | iOS/Android home widgets | WidgetKit + App Widget targets (web: installable PWA instead) |
| + | Wearables (watchOS / Wear OS) | companion targets |
| + | **Web app** | Next.js app in monorepo, shares all core packages, PowerSync WASM |
| + | **Multiple languages** | i18next shared bundles, runtime switch, RTL, Intl formatting |
| + | **Multiple currencies** | per-account currency, `exchange_rates`, display-time conversion, base currency |
| + | Earthy minimal theme + animations | shared design tokens; Reanimated/Skia (mobile), CSS/Framer Motion (web) |

### Free vs Premium (proposed gating for #19/#20)
- **Free:** accounts, transactions + breakdown, basic categories, single simple budget, search, basic balance view.
- **Premium:** advanced analytics/graphs, multi-budget + notifications, goals + compounding projections, subscription impact simulator, investment auto-fetch, statement generation (PDF), widgets & wearable complications, period-to-period comparison.
- Gating enforced by a central `useEntitlement(feature)` hook backed by the `entitlements` table (works offline).

---

## 6. Compounding / Projection Engine (features 11 & 15)

Pure, unit-tested TS module (`lib/finance/projections.ts`):
- **Future value with recurring contributions:** `FV = P(1+r)^n + PMT · [((1+r)^n − 1) / r]` where `r` = periodic rate, `n` = periods.
- **Time-to-goal:** solve `n` given target, current, contribution, rate (closed-form log, fall back to iterative).
- Inputs: recurring commitments/income, assumed return rate (user-set, default conservative). Outputs feed goal ETA and subscription opportunity-cost.
- All computed locally; deterministic; covered by tests with known fixtures.

---

## 6.5 Internationalization & Localization (design)

- **Languages:** i18next with runtime switching; default from device locale (expo-localization on mobile, `navigator.language` on web), overridable in Settings and stored in `profiles.locale`. Translation JSON bundles in `packages/core/i18n/<lang>.json`, shared by both apps. Lazy-load non-active languages.
- **Formatting:** all numbers, dates, and currency rendered via `Intl` — correct decimal/grouping separators, date order, and currency symbol placement per locale. Currency formatting is independent of language (₹ amount can display in an English or Hindi UI).
- **RTL:** support right-to-left locales (Arabic, Hebrew, Urdu, Farsi) — `I18nManager` on RN, `dir="rtl"` + logical CSS properties on web. Layouts use start/end, not left/right.
- **Currency vs language are separate axes:** language = UI text; base currency = money roll-up; each account keeps its own currency. A user can run a Hindi UI with a USD base currency holding INR + EUR accounts.
- **Pluralization & ICU** handled by i18next; no string concatenation for translatable text.
- **Coverage:** system categories, onboarding, all UI chrome translated; user-entered data never auto-translated.

## 7. Monorepo Structure (proposed)

Turborepo + pnpm workspaces. Two apps, shared packages hold the platform-agnostic core.

```
apps/
  mobile/                    # Expo (React Native)
    app/                     # expo-router: (onboarding), (tabs), account/[id],
                             #   transaction/new, goals, budgets, subscriptions, loans, statements
    widgets/                 # native widget bridge
    ios/ android/            # native targets (widgets, wearables) after prebuild
  web/                       # Next.js (App Router)
    app/                     # marketing/auth (SSR/SSG) + client app shell (PowerSync WASM)
    components/              # web-specific UI (responsive, keyboard-first)

packages/
  core/
    money/                   # Money type, arithmetic, FX convert, formatting ← shared
    finance/                 # projections, budget calc, recurring engine ← shared
    entitlements/            # freemium gating                            ← shared
    i18n/                    # i18next config + <lang>.json bundles       ← shared
  db/                        # PowerSync schema + sync rules (native + WASM)
  data/                      # repositories (accounts, transactions, budgets, …)
  types/                     # shared domain types / enums
  ui-tokens/                 # earthy theme design tokens (color, space, type)

supabase/
  migrations/                # SQL schema + RLS + triggers (shared backend)
  functions/                 # edge functions: price fetch, guest purge, notifications
```

**Reuse boundary:** `packages/*` (money, finance, entitlements, db schema, data repos, types, tokens) is 100% shared. Only the presentation layer differs — React Native primitives in `apps/mobile`, DOM/responsive components in `apps/web`. Charts share a common data contract with platform-specific renderers (Skia on mobile, canvas/SVG on web).

---

## 8. Phased Roadmap

**Phase 0 — Foundations**
Monorepo (Turborepo + pnpm), shared `packages/*`, Expo dev build **and** Next.js app both wired to the same Supabase + PowerSync (native + WASM), Auth (**incl. anonymous guest identity, see §9**), `Money` type (currency-aware) + tests, **i18n scaffolding + Intl formatting from day one**, design tokens (earthy theme), navigation/app shell on both platforms.

**Phase 1 — Core ledger (free tier MVP)**
Accounts (6 types), opening balances, transactions (income/expense/transfer) with breakdown items + "+" calculator, categories, ledger-derived balances, search. Built on shared data/finance packages so mobile **and** web get it together. Offline write/read verified on both.

**Phase 2 — Budgets & credit cards**
Budgets (D/W/M/Y) + threshold notifications, credit-card billing cycle + settle-up transfer.

**Phase 3 — Goals & emergency fund**
Goals, emergency-fund-first rule, blocking allocations, available vs total balance toggle, compounding time-to-goal.

**Phase 4 — Recurring, loans & subscriptions**
Loans + EMI, recurring commitments engine, subscriptions, recurring % of income, subscription impact simulator.

**Phase 5 — Investments, multi-currency roll-up & dashboard analytics**
Holdings, daily price fetch toggle, net-worth toggles, **`exchange_rates` daily fetch + base-currency net-worth conversion (historical/current toggle)**, full dashboard chart suite (expense, cashflow, category, label, balance outlook, period comparison, spending structure). (Per-account currencies work from Phase 1; this phase adds cross-currency aggregation.)

**Phase 6 — Statements, onboarding, guest, freemium**
Period PDF statements, onboarding flow, 3-day guest + purge job, RevenueCat entitlements + gating.

**Phase 7 — Widgets, wearables & web polish**
iOS/Android home widgets, watchOS/Wear OS companions, installable **PWA** for web, plus web-specific polish (responsive layouts, keyboard shortcuts, larger-screen dashboard density).

**Cross-cutting throughout:** because presentation is the only platform-specific layer, each feature ships to **mobile and web in the same phase**. Web has no OS home-screen widgets (Phase 7 uses a PWA + dashboard instead); everything else reaches parity. Unit tests on all money/finance logic, sync conflict tests, animation polish, accessibility.

---

## 9. Guest Identity, Account Migration & Data Deletion

Everything a user creates is owned by a single `user_id` from the very first launch — guest or registered — so migration and deletion are trivial.

- **One id from first launch.** On first open we create a **Supabase anonymous auth user** (real `auth.users` row, `is_anonymous = true`). Its UID is the `user_id` on every row (accounts, transactions, goals, …) via RLS. No "guest vs real" branching in data code — a guest is just a user who hasn't registered yet.
- **`guest_sessions`** — `user_id`, `device_id`, `created_at`, `expires_at` (= created_at + 3 days). Tracks the countdown and drives the "register to keep your data" nudge.
- **Migration = zero data movement.** When a guest registers, we **upgrade the same anonymous user in place** (link email/password or OAuth to the existing UID via Supabase `updateUser` / identity linking). Because the UID never changes, all their accounts, transactions, budgets, goals, blocked amounts, etc. stay attached automatically — nothing is copied or re-keyed. We just flip `is_anonymous = false` and delete the `guest_sessions` row.
- **Deletion = one cascade.** All tables FK to `user_id` with `ON DELETE CASCADE`. Purging a user (expired guest, or a registered user exercising "delete my account") is a single delete of the auth user → every linked row and their Storage objects (statements, exports) go with it. A scheduled Edge Function runs daily: find anonymous users whose `guest_sessions.expires_at < now()` and delete them.
- **Offline note:** the anonymous UID is issued at first launch (needs one online moment to mint the token); it's then cached and used for all local PowerSync writes. If truly offline at first launch, generate a local UUID and reconcile on first connect.
- **Auditability:** because money is an append-only ledger keyed to one UID, a user's entire financial history is a clean, self-contained, individually-deletable set — good for both migration and privacy/GDPR "right to erasure".

> Covers feature #18 (3-day guest then purge) and makes account-deletion a first-class, reliable operation.

## 10. Open Questions / Risks
- **Investment price source:** which market data API (coverage for Indian MFs vs stocks)? Licensing + rate limits. → decide before Phase 5.
- **FX rate provider:** which source for `exchange_rates` (e.g. a daily FX API)? Coverage of needed currency pairs, licensing, rate limits. → decide before Phase 5.
- **Launch languages:** which locales ship first (and which need RTL)? Drives initial translation effort.
- **Widget data freshness offline:** widgets read last-synced snapshot from shared storage.
- **Guest data purge:** must be reliable + compliant (clear deletion after 3 days).
- **RevenueCat vs native billing:** confirm before Phase 6.
