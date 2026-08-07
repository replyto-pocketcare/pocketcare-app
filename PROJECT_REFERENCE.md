# PROJECT_REFERENCE.md — Sanvya (LLM boot file)

> **Purpose: read this INSTEAD of scanning the repo.** Compact architecture + patterns + where-things-live. Rules for working here: `CLAUDE.md`. Dated change history: **`AUDIT_HISTORY.md`** (all new dated entries go there, never here). Update THIS file only when something evergreen changes: a new table/stream, a new adopted pattern/convention, changed structure, a new standing instruction. Keep it this size.

## What this is
Offline-first, multi-currency personal expense & wealth manager. **Live:** `apps/web` (Next.js PWA). **In flight:** pure-native Android (Kotlin/Compose) + iOS (Swift/SwiftUI) apps — see §Native mobile. PowerSync (local SQLite) ↔ Supabase Postgres, server-authoritative. Freemium (RevenueCat planned), i18n en/hi/nl, earthy minimal theme, India-first (INR default, UPI).

## Stack (locked)
Turborepo + pnpm 9 + Node 22 (`.nvmrc`) · TS strict, erasable-syntax only in shared packages (no enums) · Next.js App Router + PowerSync Web SDK (WASM SQLite, no SSR) · Supabase (Auth/Postgres/RLS/Edge Functions) · three.js/@react-three/fiber (card wallet), framer-motion, recharts · i18next (namespace-per-feature JSON in `packages/core/i18n`) · Web Push via `notify-dispatch` edge fn.

## Golden rules (never violate — full versions in CLAUDE.md)
1. Money = integer minor units via `@sanvya/money`. Never floats.
2. Balances derive from the append-only ledger; corrections are compensating entries, never mutation.
3. Everything server-side lives in the **`sanvya`** schema — schema-qualify every direct call/RPC.
4. Server authoritative; client DB is an offline cache reconciled by sync.
5. Multi-currency: store native currency + ISO code; convert only at display via `exchange_rates` (as-of date). Cross-currency transfers capture `fx_rate` + `to_amount`.
6. **Never a cross-row constraint on a synced table** — PowerSync uploads ops in separate transactions; partial sets wedge the queue forever. Enforce client-side + server *audit* function.
7. Soft-delete via `deleted_at`; every read filters it.
8. One user id from first launch (anonymous auth); guest→registered upgrades the SAME UID in place. Deletion = one FK cascade.

## Data model (details: `docs/architecture/02-data-model.md`)
- **Entities:** profiles · accounts · transactions · transaction_items · categories · labels · budgets · credit_card_details · goals · goal_allocations · loans · recurring_commitments · recurring_groups · subscriptions · planned_cashflow · holdings · price_snapshots · exchange_rates · entitlements · guest_sessions · statements · notifications · notification_prefs · expenses · expense_participants · expense_items · expense_item_shares · settlements · split_group_members · receipt_scans · payment_handles(+disclosures) · transaction_templates · bug_reports · client_errors · failed_writes/sync_attempts (LOCAL-ONLY).
- **Lookups** (enums-as-tables, global read-only `reference_data` stream): account_types · transaction_types · category_kinds · periods · commitment_kinds · tiers · rate_modes · payment_methods.
- **Junctions:** transaction_labels · budget_categories · budget_labels · account_type_payment_methods.
- Labels/budget scope come ONLY from junctions (no text columns). Payment-method pickers read `account_type_payment_methods` and store the code.
- Server-only (no sync stream): push_subscriptions, payment_handles. Local-only tables never sync (`localOnly: true`).
- Some FKs are deliberately ABSENT on synced child rows (e.g. `transaction_templates.group_id`, loan→account link): a child can upload before its parent → 23503 → quarantine. Client enforces; `sanvya.audit_*()` fns observe.

## Repo structure
```
apps/web                  Next.js app. Pages/AppShell in app/; logic in src/ (write.ts, hooks.ts, powersync.ts,
                          sync/{repair,deadletter}, splits/, cashflow/, categorize/, diagnostics/, onboarding/)
apps/android              pure-native Kotlin app — :app :domain :data modules (Compose); domain vector-green
apps/ios                  pure-native Swift app — App/Domain/Data/Generated (SwiftUI); Domain vector-green
packages/core/*           15 pure-TS domain pkgs (money finance ledger budget entitlements guardrail reconcile
                          crypto receipts upi diagnostics sync-policy splits-insights suggestions i18n) — 317 tests, THE SPEC
packages/db               AppSchema + SupabaseConnector (op-coalescing, fault injection) + quarantine + auth
packages/data             repository interfaces + PowerSync implementations
packages/{types,ui-tokens}
supabase/migrations       0001_init … 0047 (numbered, ordered); supabase/functions: split-invite(+accept),
                          market-sync, redeem-coupon, receipt-scan, payment-handle, notify-dispatch, assistant
packages/db/sync-streams.yaml   PowerSync sync config (redeploy in dashboard after schema changes)
docs/                     architecture/ features/ plans/ mobile/{TODO,STARTER_PROMPT,CONTINUE_PROMPT}.md
```

## Client patterns (follow these, don't invent)
- **Read** via `useQuery` (PowerSync react); **write** via `write.ts` helpers (`insertRow`/`updateRow`/`softDelete` — auto-fill id/user_id/timestamps). Transaction+items in ONE local write transaction.
- `useSyncExternalStore` getSnapshot must return a **stable reference** (cache it; module-level constant for server snapshot) or React error #185.
- Money display ONLY via `useMoneyFmt()` — it honors hide-amounts. Charts go through `chartMoney()`/`chartTooltip()`. (Three privacy leaks shipped by bypassing this; don't be the fourth.)
- Premium gates via `useEntitlement`/`useTier` (works offline). Plans render from `src/billing/plans.ts`, never hard-coded.
- Design tokens in `globals.css :root`; use `.card`/`.btn`/`.chip`/`.tap-row`/`.row-stack`; CSS-var fills for charts. Dashboard tiles CLIP, never scroll (`useFitRows`). Mobile no-horizontal-scroll invariants: grid children `min-width:0`, `.input{max-width:100%}`, wide tables get overflow wrappers.
- i18n: one namespace per feature (`packages/core/i18n/src/locales/<ns>/{en,hi,nl}.json`), register in `resources`/`NAMESPACES`, consume via `useTranslation("<ns>")`. Keys must be identical across locales. Persisted ledger text stays English (data, not UI).
- `TransactionTile` is the ONLY transaction row component. One allocation implementation (`@sanvya/receipts` `splitByWeights` — `splits/math.ts` re-exports it).
- Auth: `initSystem` connects only if a session exists; offline NEVER downgrades to logged-out (persisted marker); re-key local DB only when user id changes. Settlements queries must filter `status <> 'disputed'` (5 sites).
- **State preservation (R1, all platforms — plan §7 R1, test cases LIFE-1..9):** no visible restart or lost input across fold/unfold, resize, rotation, backgrounding, or process death. Android: ViewModel + `rememberSaveable` + `SavedStateHandle`, `WindowSizeClass` layouts, never `android:configChanges` opt-outs. iOS: `@SceneStorage` + draft-save on `scenePhase == .background`. Web: route in URL, long-form drafts persisted (receipt pattern). Long forms auto-persist drafts on background everywhere. Committed data is safe by architecture (immediate local SQLite write).

## Sync & migration rules (the incident-derived ones)
- **Add a column to a synced table = 2 steps:** mirror in `AppSchema` (`packages/db/src/index.ts`) + `supabase db push` & redeploy sync-streams. **New synced table = 4 steps** (AppSchema, migration w/ RLS+grants, sync-streams.yaml entry, push+redeploy).
- Migrations: schema-qualify every function; re-runnable (`drop policy/trigger if exists` first); validate with pglast. No cross-row constraints (rule 6).
- Upload path coalesces only *consecutive* same-table ops — write all items, then all shares, not interleaved.
- Failure handling: `@sanvya/sync-policy` classifies (default transient; 401/408/429 transient; SQLSTATE beats HTTP status); permanent → 3 attempts → quarantine to local-only `failed_writes` (write-then-delete order); surfaced by ProblemsPanel (named rows, export-before-discard ALWAYS, sequential direct retry). No `ON CONFLICT` on PowerSync views.
- Error self-reporting via `report_client_error` RPC directly (never through the sync queue).

## Web build gotchas
Never construct PowerSyncDatabase at module top level (SSR crash) — lazy `getDb()` browser-only. `process.env.NEXT_PUBLIC_*` referenced statically only. Root `pnpm.overrides` pins ONE react/react-dom — don't remove; prefer `parent>child` scoped overrides for any future version conflict. One root `.env` (web loads `../../.env`). Root `.npmrc` `node-linker=hoisted` stays.

## Native mobile (direction: rev 3 — pure native, owner decision)
Three maintained apps: Android (Kotlin 2.x + Compose + Glance), iOS (Swift 6 + SwiftUI + WidgetKit/ActivityKit), web. No cross-platform layer (RN + KMP rejected; the RN attempt's breakage history is in AUDIT_HISTORY). Third-party allowed ONLY: PowerSync native SDKs, Supabase SDKs, RevenueCat, FCM — anything else needs a human yes.
- **Progress:** Phase 0+1 DONE (2026-07-31): 16 domains / 250 golden vectors green on both `./gradlew test` and `swift test`. Phase 2 (data layer: repositories/connector/auth) in flight — see TODO.md Handover for exact state.
- **Plan:** `docs/plans/native-mobile-apps.md` · **Tests:** `docs/plans/full-test-plan.md` · **Queue + Handover:** `docs/mobile/TODO.md` · **Prompts:** `docs/mobile/{STARTER,CONTINUE}_PROMPT.md`.
- **Drift control:** golden vectors (`tools/golden-vectors/`, exported from the TS core) are law for both ports — behavior changes start in `packages/core`; 3-way schema parity script; generated tokens/i18n; new web features must queue mobile counterparts in the same change set.
- **Porting ground truth:** `packages/data/src/powersync-repositories.ts` is the authoritative write layer to port (web's `hooks.ts`/`write.ts` sit above it). Splits has no dedicated repo in `packages/data` — web `splits/write.ts`+`hooks.ts` are its spec.
- Mobile session logs → AUDIT_HISTORY.md "Mobile change log". Feature parity table lives in `docs/mobile/TODO.md`.

## Testing
`pnpm test:core` — 317 tests, Node `node:test` + type-stripping (sandbox: `node --test --experimental-strip-types packages/core/*/src/*.test.ts`). Web: `pnpm --filter @sanvya/web typecheck`. Full strategy + ~100-case catalog: `docs/plans/full-test-plan.md`. Money/domain tests go in `packages/core` (the spec), never duplicated per app.

## Docs maintenance (MANDATORY on feature changes — full rule in CLAUDE.md)
Feature doc in `docs/features/`, Mermaid diagrams updated, indexes updated, **dated entry in `AUDIT_HISTORY.md`** (not here), regenerate PDF if architecture changed.

## Web pages (quick index)
`/` dashboard · `/accounts(+/new,/[id]/edit)` · `/transactions(+/new)` · `/cards` · `/budgets` · `/goals` · `/cashflow` · `/recurring` · `/investments` · `/insights`* · `/statements`* (+analyze) · `/friends` (splits; `/groups`→redirect) · `/receipts/{new,review,split}` · `/search` · `/settings` (+categories/labels/data) · `/notifications` · `/onboarding` · `/login` · `/join` · `/help` · `/admin/*` (English-only). *=premium.

## Open decisions
Market-data + FX providers · launch languages/RTL · hi/nl native review before release · mobile: min OS versions, real bundle ids/domain (placeholders were guesses), PowerSync Swift SDK validation.
