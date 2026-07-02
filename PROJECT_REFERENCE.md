# PROJECT_REFERENCE.md — PocketCare

> **Living index / audit of the whole repo. Read this first in every session to minimize context.**
> Keep it updated whenever structure, decisions, or conventions change. Detailed rationale lives in `ARCHITECTURE.md`.

**Last updated:** 2026-07-02 · **Status:** WEB-ONLY. Full feature build across all pages (dashboard, all-3 transactions, 3D card wallet, goals, subs, loans, investments, settings, PWA, onboarding/login, dark mode). Mobile deleted. 49 core tests passing.

## ⚠️ Pivot (2026-07-02): web-only
Mobile (`apps/mobile`) was DELETED. Sole client is `apps/web` (Next.js), installable as a **PWA** via Chrome. Shared `packages/*` (money, finance, ledger, budget, entitlements, i18n, types, ui-tokens, db, data) remain the engine. Animations use **three.js / @react-three/fiber** (card wallet), **framer-motion** (progress bars), **recharts** (charts).

---

## What this is
Offline-first personal expense & wealth manager. Cross-device (iOS/Android + **web**), home-screen widgets, wearable companions. **Multi-language + multi-currency.** Earthy, minimal theme with elegant animations. Freemium.

## Stack (locked)
- **Monorepo:** Turborepo + pnpm. `apps/mobile` (Expo) + `apps/web` (Next.js) share `packages/*` core (~90% logic reuse).
- **Mobile:** React Native + Expo (dev build / CNG — **never Expo Go**), TypeScript strict.
- **Web:** Next.js App Router + PowerSync **Web SDK** (WASM SQLite, **no SSR** for synced DB; enable `asyncWebAssembly`+`topLevelAwait`).
- **Local DB:** SQLite via **PowerSync** (native on mobile, WASM in browser). **Sync:** PowerSync ↔ **Supabase** Postgres (server-authoritative).
- **Backend:** Supabase (Auth, Postgres, RLS, Storage, Edge Functions).
- **UI:** Reanimated 3 + Moti + Gesture Handler; **Skia**/Victory Native for charts; Zustand for UI state only.
- **i18n/l10n:** i18next + react-i18next (shared bundles in `packages/core/i18n`), expo-localization, **Intl** for number/date/currency formatting, RTL support.
- **Payments:** RevenueCat. **Notifications:** expo-notifications + Edge Functions.
- **Native:** WidgetKit (iOS) + App Widget (Android); watchOS + Wear OS companions.

## Golden rules (financial integrity — do not violate)
1. Money = **integer minor units**, never floats. Use the `Money` type in `src/lib/money`.
2. Balances are **derived from an append-only ledger**, never mutated in place.
3. Initial-balance changes = new `opening_balance`/`adjustment` ledger entries.
4. Transaction + its breakdown items written in **one atomic SQLite tx**; items **must sum** to total (client + Postgres check).
5. Sync is **server-authoritative**; synced ledger entries are immutable — corrections are compensating entries.
6. Reads always come from local SQLite (fully usable offline).
7. **Multi-currency:** amounts stored in their account's native currency + ISO code; **never** converted in place. Convert only at display/aggregation time via `exchange_rates` (as-of date for history). Cross-currency transfers capture `fx_rate` + `to_amount`.
8. **One user id from first launch** (Supabase anonymous auth). Guest→registered = upgrade same UID in place (no data movement). All tables FK `user_id` `ON DELETE CASCADE` → deletion is one cascade. See ARCHITECTURE.md §9.

## Data model (see ARCHITECTURE.md §4 for columns)
`profiles · accounts · transactions · transaction_items · categories · budgets · credit_card_details · goals · goal_allocations · loans · recurring_commitments · subscriptions · holdings · price_snapshots · exchange_rates · entitlements · guest_sessions · statements`

`profiles` holds `base_currency`, `locale`, `rate_mode`. Translations are static JSON in `packages/core/i18n` (not a DB table).

Account types: `savings | current | credit_card | cash | mutual_funds | stocks`.
Transaction types: `income | expense | transfer | opening_balance | adjustment`.

## Structure (Phase 0 built ✅ except where noted)
```
apps/mobile (Expo router: app/_layout, app/index)      ✅ skeleton
apps/web    (Next.js App Router: app/layout, app/page)  ✅ skeleton
packages/types            ✅   packages/ui-tokens (earthy theme) ✅
packages/core/money  ✅ tested (15)   packages/core/finance ✅ tested (13)
packages/core/entitlements ✅ tested (3)   packages/core/ledger ✅ tested (8)
packages/core/budget ✅ tested (10: period bounds, progress, threshold, CC cycle)
packages/core/i18n ✅ (en/hi/ar, RTL)
packages/db (schema + connector + auth; incl. credit_card_details) ✅   packages/data (interfaces + PowerSync repos) ✅
  db sync config: sync-streams.yaml (recommended, edition 3) ✅ · sync-rules.yaml (legacy)
supabase/migrations: 0001_init ✅ · 0002_seed_and_credit_cards ✅ (validated)   supabase/functions ⬜
apps/mobile: index, accounts, account/new, transaction/new, budgets, src/{powersync,notifications} ✅
apps/web: providers + accounts, accounts/new, transactions/new, budgets, src/powersync ✅
```
Total tests: **49 passing** (`pnpm test:core`). Repos: accounts, transactions, balances, budgets, creditCards.
Reuse boundary: everything in `packages/*` is shared; only presentation differs (RN primitives vs DOM). Charts share a data contract, platform-specific renderers.
Package names: `@pocketcare/{types,money,finance,i18n,entitlements,db,data,ui-tokens,mobile,web}`.

## Feature index (21 + extras) → all mapped in ARCHITECTURE.md §5
Accounts, balances, transactions+breakdown, budgets, credit cards, goals/emergency fund, blocked-balance views, subscriptions+simulator, investments toggles, dashboard, loans/recurring, compounding projections, sub-item calculator, search+statements, onboarding+3-day guest, freemium gating, widgets, wearables.

## Freemium split (proposed)
Free: accounts, transactions, basic budget, search. Premium: advanced analytics, goals+projections, subscription simulator, investment auto-fetch, statements, widgets/wearables, comparisons. Gate via `useEntitlement(feature)` (works offline).

## Roadmap phases
0 Foundations (monorepo, mobile+web wired to Supabase/PowerSync) · 1 Core ledger (MVP) · 2 Budgets+credit cards · 3 Goals+EF · 4 Recurring/loans/subs · 5 Investments+dashboard · 6 Statements/onboarding/guest/freemium · 7 Widgets+wearables+web PWA.
Each feature ships to mobile **and** web in the same phase (shared core); web uses a PWA in place of OS home-screen widgets.

## Open decisions
Market-data API for holdings · FX rate provider for `exchange_rates` · launch languages (which + RTL) · RevenueCat vs native billing.

## Gotchas / platform notes
- **PowerSync web must NOT be instantiated during SSR** (crashes: `SSRDBAdapter … tx.execute is not a function`). `apps/web/src/powersync.ts` creates the DB lazily, browser-only (`getDb()`, `getRepositories()`); `app/providers.tsx` gates the tree until `initSystem()` resolves on the client. Never construct `PowerSyncDatabase` at web module top-level.
- i18n JSON is imported plainly (no `with { type: "json" }` import attributes) for SWC/webpack compatibility.
- **Client env must be referenced statically**: `process.env.NEXT_PUBLIC_*` (web) / `process.env.EXPO_PUBLIC_*` (mobile). Dynamic `process.env[key]` is NOT inlined into the client bundle → value is undefined at runtime. Both `src/powersync.ts` files use static consts.
- **One root `.env` for the monorepo**: `apps/web/next.config.js` loads `../../.env` (dependency-free parser). Expo (mobile) still needs the vars in `apps/mobile/` — symlink or copy the root `.env` there.
- **Mobile monorepo setup (required to compile):** `apps/mobile/babel.config.js` (babel-preset-expo + reanimated plugin), `apps/mobile/metro.config.js` (watchFolders = repo root, nodeModulesPaths, disableHierarchicalLookup). Root `.npmrc` sets `node-linker=hoisted` because Metro can't resolve pnpm's symlinked store — **reinstall (`pnpm install`) after adding it**.
- Transaction save: both apps' add-transaction screens pick an account + type and call `repositories.transactions.create` (atomic txn+items). Breakdown items only sent when >1.

## Conventions
- **Toolchain:** Node 22+ (`.nvmrc`), pnpm 9 workspaces, Turborepo. TS strict + `noUncheckedIndexedAccess` + `verbatimModuleSyntax`.
- **Erasable TS only** in shared packages (no `enum`/namespaces) — const-object unions instead — so Node type-stripping runs tests with no build step.
- **Tests:** required for all money/finance/entitlements logic. Run `pnpm test:core` (Node built-in `node:test`, `--experimental-strip-types`). Currently 31 passing.
- **Secrets:** `.env` from `.env.example`; web vars need `NEXT_PUBLIC_`, mobile vars need `EXPO_PUBLIC_`. Never commit `.env`.
- **Money:** always use `@pocketcare/money` (integer minor units); never do raw arithmetic on amounts.
- _TODO: lint/format config (eslint/prettier), commit style — add when apps get built out._

## Web app pages (apps/web/app)
`/` dashboard (net worth ±blocked, accounts, recent, spending pie) · `/accounts` (+color, net-worth toggle) · `/accounts/new` · `/transactions` (search+filter) · `/transactions/new` (income/expense/transfer + cross-currency + breakdown) · `/cards` (three.js wallet, scroll-driven, settle-up) · `/budgets` (animated bar) · `/goals` (EF-first, animated bar) · `/subscriptions` (+impact simulator) · `/loans` (loans + recurring + % income) · `/investments` (holdings + auto-fetch toggle) · `/settings` (currency, language, dark mode, categories+sub-categories, colored labels, plan) · `/onboarding` · `/login` (guest→register in place).
Shell: `AppShell.tsx` (sidebar nav, dark-mode toggle, install button, SW register). Data hooks: `src/hooks.ts` (net worth via ledger+FX, respects `include_in_net_worth`). Writes: `src/write.ts`. 3D: `src/cards/WalletScene.tsx`. PWA: `public/manifest.webmanifest`, `public/sw.js`, icons.
Also: `/insights` (recharts: cashflow, net trend, by category/label, month comparison — Premium) · `/statements` (period picker, printable/PDF — Premium) · `/accounts/[id]/edit` (name/type/color/net-worth/archive).
New deps to install: `@react-three/fiber @react-three/drei three framer-motion recharts` (+types).
Migrations to apply: `0002`, `0003`, `0004` (budgets: name/start_date/end_date). **Redeploy sync-streams** (labels, subscriptions, loans, holdings, credit_card_details).
Premium gating via `useTier()` (reads entitlements). Settings has a Free/Premium toggle (updates entitlements.tier). Budgets support name + scope(category/label) + recurring period OR custom date range (repo handles both).

## Change log
- 2026-07-02 — **Proper auth flow:** register (username, email, password, confirm) → converts guest in place via `updateUser({email, data:{username}})` → **email OTP step** (`verifyOtp` type `email_change`) → set password. Sign-in via `signInWithPassword`. Sessions persist (persistSession + detectSessionInUrl true). Friendly error mapping; "already registered" nudges to sign in. **Supabase config needed:** disable "Secure email change"; add `{{ .Token }}` to the *Change Email Address* email template (for the 6-digit OTP); SMTP for delivery.
- 2026-07-02 — **Branding + polish + cards redesign:** PocketCare **logo** (`src/ui/Logo.tsx`, leaf-in-pocket) in sidebar/onboarding/login; regenerated favicon + PWA icons. **Onboarding gate** (first-run redirect via `onboardingSeen`; onboarding/login render full-screen, no sidebar). **Sign-out warning** modal (guests warned of data loss). **Cards redesigned** in CSS + framer-motion (three.js `WalletScene` removed): wallet header, cards emerge into a vertical list, details on card face (holder = user's display name, optional last-4 via migration `0007`), balance/due on the right; statement/due **editable anytime**; "Add card" button. Global polish: `Modal`, `Spinner/Loading/Skeleton`, route-transition `template.tsx`, card hover-lift, focus rings. **Apply 0006 + 0007; redeploy streams for 0006 (transaction_audit).**
- 2026-07-02 — Settings: **account section** (username edit via auth metadata, guest status + 3-day deletion countdown, sign out), **theme control** (shared `src/theme.ts` store, synced with sidebar), **Help & Support**. Sidebar shows guest chip + countdown. **Transaction editing with audit**: migration `0006` `transaction_audit` table (+AppSchema +streams), `transactions.update()` writes changes + appends audit record (clears items if amount changes), `/transactions/[id]/edit` page shows edit history. Account balance editing (direct adjustment vs recorded transaction). **Apply 0006 + redeploy streams** (added transaction_audit). Webpack pnpm-symlink warnings (js-tokens/react/loose-envify) are harmless.
- 2026-07-02 — Tier moved to a **local reactive store** (`src/tier.ts`, localStorage) — entitlements isn't synced client-side, so the DB-based toggle silently failed. Added `Spinner/Loading/Skeleton` (framer-motion); used on app boot + 3D wallet load. Migration `0005`: rich default categories + sub-categories + starter labels via shared `seed_default_categories()` + **backfill loop for existing users** (fixes empty categories/labels for pre-existing guests). Account edit now edits **balance** (direct adjustment vs recorded transaction). **Labels wired** into the transaction form (colored chips + custom text).
- 2026-07-02 — **Complete-product pass:** named/tagged budgets (category/label + recurring OR custom timeframe; migration `0004`), account editing (`accounts.update` + `/accounts/[id]/edit`), full **Insights** page (recharts: cashflow, net trend, category, label, month-vs-month), **Statements** (period picker + printable PDF), **Free/Premium toggle** in Settings + `useTier()` gating on insights/statements/simulator. 49 tests passing; migrations 0001–0004 valid.
- 2026-07-02 — Initial architecture & reference created (planning phase).
- 2026-07-02 — Added web app: monorepo (Turborepo) with `apps/web` (Next.js + PowerSync WASM) sharing `packages/*` core with mobile.
- 2026-07-02 — Added multi-language (i18next + Intl + RTL) and multi-currency (per-account currency, `exchange_rates`, display-time conversion, base currency).
- 2026-07-02 — Guest identity: anonymous Supabase auth UID from first launch; in-place upgrade on register; cascade delete on `user_id`. (ARCHITECTURE.md §9)
- 2026-07-02 — **Phase 0 implemented:** Turborepo monorepo, shared packages (types, money+FX, finance, i18n, entitlements, db, data, ui-tokens), Expo + Next.js skeletons. 31 unit tests passing on money/finance/entitlements.
- 2026-07-02 — **Phase 1 (build):** Supabase migration `0001_init.sql` (all tables, RLS owner policies, deferred items-reconcile trigger, updated_at triggers, cascade deletes, guest-purge fn; validated via libpg_query). New `@pocketcare/ledger` (signed effects, ledger-derived balances, available/blocked, net-worth FX aggregation) — 8 tests. PowerSync `SupabaseConnector` + anonymous-auth helpers. PowerSync-backed account/transaction/balance repositories (atomic txn+items with reconcile guard). Mobile screens: accounts list (reactive `useQuery`), add-transaction with "+" breakdown builder. **39 tests passing.**
- 2026-07-02 — Switched sync config to **Sync Streams** (`sync-streams.yaml`, edition 3): user_data stream (queries array, auto_subscribe) + global exchange_rates (with synthesized id).
- 2026-07-02 — **WEB-ONLY PIVOT + full feature build:** deleted mobile; built dashboard, all-3-type transactions + search, three.js credit-card wallet (scroll-driven), goals (EF-first), subscriptions + impact simulator, loans/recurring (% of income), investments, settings (dark mode, currency, language, sub-categories, colored labels, plan), onboarding + login (guest→register in place), PWA (manifest/SW/icons/install). Account colors + per-account net-worth inclusion. Migration `0003` (categories.parent_id, accounts.include_in_net_worth, labels table). Schema+streams extended (labels, subscriptions, loans, holdings). Animated progress bars (framer-motion), charts (recharts).
- 2026-07-02 — **Phase 2 (build):** `@pocketcare/budget` (period bounds D/W/M/Y, budget progress, threshold-crossing for notifications, credit-card billing cycle with month clamping) — 10 tests. Migration `0002` (credit_card_details surrogate id; new-user trigger seeds profile + free entitlement + default categories + guest session). Budget & CreditCard repos (+ settle-up = transfer). Mobile: budgets screen, account/new, notifications helper. **Web mirrored**: providers + accounts, accounts/new, transactions/new, budgets. credit_card_details added to AppSchema + streams (redeploy streams). **49 tests passing.**
