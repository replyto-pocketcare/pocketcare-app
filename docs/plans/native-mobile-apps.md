# Plan — Android & iOS apps: React Native (Expo) + native surfaces

> **Status:** PLANNED (2026-07-30, rev 2). Nothing built yet.
> **Rev 2 supersedes rev 1 (same day):** rev 1 chose Kotlin Multiplatform + fully-native UI, which required porting every TS core domain against golden test vectors. Superseded because the entire spec-bearing logic of this repo is TypeScript and **React Native runs it unchanged** — the highest-risk workstream (logic porting by LLM executors) is deleted, not mitigated. All native-only surfaces (widgets, Live Activities, App Intents) are separate native extensions even in a fully-native app, so RN gives up nothing there.
> **Executor:** written for smaller/cheaper LLM agents. Follow the task protocol in §1 exactly. Do not improvise architecture.
> **Companion:** `docs/plans/full-test-plan.md`. Every phase here has an exit gate defined there.

## 0. Goal and non-negotiables

Ship **PocketCare for Android and iOS built with React Native (Expo, dev builds / CNG — never Expo Go)** with home-screen **widgets**, iOS **Live Activities**, and **native push notifications**, against the **unchanged** existing backend (Supabase + PowerSync). The web app keeps working; changes to `apps/web` only where explicitly listed.

**Golden rules (identical to CLAUDE.md):**

1. Money = **integer minor units** via `@pocketcare/money` — used directly, not reimplemented. Never floats.
2. Balances derive from the **append-only ledger**; corrections are compensating entries.
3. Everything server-side is in the **`pocketcare`** schema — schema-qualify every direct call.
4. Server authoritative; device DB is an offline cache reconciled by sync.
5. Amounts stay in their account's currency; convert at display time via `exchange_rates`.
6. Never a cross-row constraint on a synced table (wedges the upload queue — CLAUDE.md).
7. Soft-delete via `deleted_at`; reads filter it.

## 1. Task protocol for the executor LLM

1. Read `PROJECT_REFERENCE.md` §"Native mobile" (created in Phase 0) and only the sections of this plan for your current task.
2. Pick exactly **one** unchecked box. Do that task. Nothing else.
3. Done only when the task's *Done-when* passes. Otherwise the box stays unchecked.
4. After every task: update the checkbox + one line in the mobile change log in `PROJECT_REFERENCE.md`.
5. **Never** without explicit human approval in the current conversation: modify `apps/web` or `packages/*` beyond what a task names, write a migration, touch `sync-streams.yaml`, add a dependency, delete anything. **`pnpm-lock.yaml` cannot be regenerated in the sandbox** — any task adding a dependency must end by telling the human to run `pnpm install` locally (CI is `--frozen-lockfile`).
6. Conflicts: CLAUDE.md wins, then §0, then task text. Unclear → stop and ask.

## 2. Architecture decision (ADR)

**Decision: React Native + Expo (dev build/CNG), reusing the TS monorepo core directly; native Swift/Kotlin only for OS surfaces.**

- `apps/mobile` — revived (the original stack, deleted in the 2026-07-02 web-only pivot; its build gotchas are already documented in PROJECT_REFERENCE: metro `watchFolders`, `.npmrc node-linker=hoisted`, babel preset + reanimated plugin, `EXPO_PUBLIC_*` env, single-React `pnpm.overrides`).
- **Reused unchanged:** `@pocketcare/{money,finance,ledger,budget,entitlements,receipts,upi,sync-policy,diagnostics,splits-insights,reconcile,guardrail,crypto,i18n,types,db,data}` — including `packages/db`'s `AppSchema`, connector (op-coalescing, fault injection), and quarantine/dead-letter code, and `packages/data` repositories. **The ~300-test core suite remains the single spec; nothing is ported.**
- **Sync:** `@powersync/react-native` (native SQLite) with the same `AppSchema` object and `sync-streams.yaml`. **Auth:** same `supabase-js` flows as web (guest, OTP, Google via native session; in-place guest→registered upgrade).
- **UI:** RN + Reanimated/Moti + Gesture Handler; charts via **Victory Native (Skia)** sharing the web charts' data contract; Zustand for UI state only (matches the original locked stack).
- **Native modules (small, isolated, the only Swift/Kotlin in the repo):** WidgetKit + Glance widgets, ActivityKit Live Activities, App Intents / app shortcuts / QS tile, FLAG_SECURE/privacy screen. Each wrapped as an Expo config plugin so `expo prebuild` stays the source of truth for native projects.

| Rejected | Why |
|---|---|
| KMP + native UI (rev 1) | Forces double-maintenance of financial logic (TS spec + Kotlin port). Highest-risk work for LLM executors; RN deletes it. |
| Fully separate Swift + Kotlin apps | Same flaw, tripled. |
| Capacitor wrap | Not native UI/feel. |

**Known frictions, owned up front:** (a) the single-React constraint — RN's pinned React must be reconciled with the root `pnpm.overrides` react `18.3.1` pin; pick the newest Expo SDK whose RN supports it and verify `next build` still passes (this exact bug is documented — two Reacts break web prerender); (b) Hermes vs Node runtime differences (mainly `Intl`) — caught structurally by test-plan layer L1, which runs the core suite under Hermes; (c) OTA: JS-only fixes may ship via `expo-updates` (store-policy compliant), native-module changes always need a store build.

## 3. Repo layout (target)

```
apps/mobile/                 # Expo app (CNG). expo-router.
  app/                       # routes, mirroring web's page structure
  src/{powersync,auth,widgets-snapshot,notifications,diagnostics}
  plugins/                   # expo config plugins for the native targets
  targets/widget-ios/        # WidgetKit + Live Activity extension (Swift)
  targets/widget-android/    # Glance widget (Kotlin)
docs/mobile/                 # parity checklist, per-screen specs
```

`supabase/`, `packages/*`, `sync-streams.yaml`: shared, unchanged except §6's one migration.

## 4. Phase 0 — Scaffold + prove the reuse claim  ✅ gate: TP L1 green

- [ ] **P0.1 — Expo app scaffold** in the monorepo. Restore the documented setup: `babel.config.js`, `metro.config.js` (watchFolders=root, nodeModulesPaths, disableHierarchicalLookup), root `.npmrc` `node-linker=hoisted` (⚠️ requires local `pnpm install` — human step), `.env` copy/symlink with `EXPO_PUBLIC_*`, single-React reconciliation per §2(a).
  *Done-when:* `expo prebuild` + Android assemble + iOS simulator build green in CI; `next build` for web still green; human confirmed `pnpm install` + lockfile committed.
- [ ] **P0.2 — Hermes spec run (test-plan L1).** CI job executes the `packages/core` test suites under Hermes (bundle the tests, run on hermes CLI or in an RN test harness). Every failure = engine incompatibility to fix via polyfill/adapter — **never** by forking core logic.
  *Done-when:* full core suite green under Hermes; job wired to CI.
- [ ] **P0.3 — PowerSync spike:** `@powersync/react-native` + the real `AppSchema` from `packages/db` + real connector against local Supabase: sync down reference data + one account, write one transaction offline, watch it upload. Validates the central reuse assumption before any UI exists.
  *Done-when:* spike screen shows a synced round-trip on both platforms.
- [ ] **P0.4 — Reference section.** Add "Native mobile" section to `PROJECT_REFERENCE.md`: this layout, the ADR, mobile change log, feature-parity table (feature × android/ios). Executors load that, not the repo.

## 5. Phase 1 — Data & auth wiring (no porting — wiring)

- [ ] **P1.1 — PowerSync setup:** lazy init mirroring web's `getDb()`/`getRepositories()`; re-key on auth user change; local-only `failed_writes`/`sync_attempts` tables via the shared quarantine module. Watched queries hooked to the shared repositories (`packages/data`).
- [ ] **P1.2 — Auth:** guest/OTP/Google (`signInWithOAuth` via in-app browser or native Google Sign-In + `signInWithIdToken` — decide in-task, document), in-place guest upgrade, offline session marker (port web's `pc_auth` semantics to MMKV: never downgrade to logged-out while offline).
- [ ] **P1.3 — Diagnostics capture:** RN adaptation of the ring buffer (MMKV-backed), wrapped console, global error handler, structured sync-failure sink (`setSyncDiagnosticSink` — already a shared hook in `packages/db`). Redaction comes from shared `@pocketcare/diagnostics`.
- [ ] **P1.4 — Write-path helpers:** RN equivalent of web `write.ts` (id/user_id/timestamps auto-fill) — extract to `packages/data` if trivially shareable (task may touch `packages/data`: allowed, named here).
- [ ] **P1.5 — Repair panel logic** wired from shared code (`src/sync/repair.ts` equivalent — evaluate hoisting the web implementation into `packages/data`; named exception as above).

*Done-when:* test-plan L3 suite (local Supabase + fault-injection presets: 0040 partial-set replay, head-of-line block, 401 refresh, quarantine drain) passes on both platforms.

## 6. Phase 2 — UI slices (same slices as rev 1, RN implementations)

Theme: generate RN theme from `packages/ui-tokens` (no hand-copied hex). i18n: `i18next` + shared catalogs used **directly** — no conversion step, same namespaces, live language switch. One shared money formatter honoring hide-amounts (web shipped three separate leaks; see PRIV-* cases).

- [ ] **S1 — MVP ledger:** onboarding/walkthrough (keep the "not connected to your bank" copy faithfully), auth screens, accounts (list/new/edit), transactions (list/new/edit + breakdown + cross-currency), dashboard-lite, settings-lite (currency/language/theme/hide-amounts).
- [ ] **S2 — Planning:** budgets, goals/EF, cashflow hub (recurring/subs/loans, mark-paid, auto-post), credit cards (native card list; the three.js wallet is web-only — optionally revisit later via expo-gl, not in this plan).
- [ ] **S3 — Social:** splits & groups (incl. Patterns thresholds), invite deep links via App Links/Universal Links (`/join?token=` survives auth), UPI settle-up — Android real Intent + chooser, iOS copy/QR-first, two-sided confirmation, optimistic pending netting.
- [ ] **S4 — Capture:** receipts — camera via `react-native-vision-camera`, OCR via ML Kit (Android) / Vision (iOS) native wrappers **returning word bounding boxes** so the shared line-rebuild + reconciliation gate in `@pocketcare/receipts` is reused as-is; statement import (same shared parsing where text-layer, same `importTransactionsBulk` semantics).
- [ ] **S5 — Wealth:** investments, insight cards, statements (premium), search.
- [ ] **S6 — Assistant (optional, last):** same edge function; native speech input (SFSpeechRecognizer / Android SpeechRecognizer).

*Done-when (each slice):* parity rows flipped; slice's test-catalog cases automated where marked; screenshots on PR.

## 7. Phase 3 — Native surfaces (the Swift/Kotlin that must exist regardless)

- [ ] **P3.0 — Migration `00xx_native_push.sql`** (only backend change in this plan): `push_subscriptions` + `platform ('web'|'fcm'|'apns')`, `token`, nullable `live_activity_token`; `notify-dispatch` fans out web-push/FCM/APNs. CLAUDE.md migration rules apply (schema-qualify, re-runnable, pglast).
- [ ] **P3.1 — Notifications:** `notifee` (or expo-notifications — decide in-task) + FCM/APNs; channels/categories mapped to existing `notification_prefs`; deep links with prefill (settle-record → prefilled txn form); single dispatcher stays `notify-dispatch` + `pushed_at` (no second pipeline).
- [ ] **P3.2 — Widgets (snapshot pattern — unchanged from rev 1):** the RN app writes a small **pre-formatted, pre-masked snapshot** (net worth ±blocked, balances, budget progress, next 3 payments, stale-since) to App Group (iOS) / SharedPreferences-DataStore (Android) on relevant sync/write; Glance + WidgetKit render it. Widgets never open the PowerSync DB.
- [ ] **P3.3 — Live Activities (iOS, Swift extension + config plugin):** (a) trip mode — running group spend + your share, updated by APNs `liveactivity` pushes triggered off the existing `group_expense` fan-out, batched ≤1/15min; (b) EMI/bill due today → ends on mark-paid. Requires P3.0's token column.
- [ ] **P3.4 — Quick capture:** Android app shortcuts + QS tile; iOS App Intents ("log 200 rupees groceries") writing through the normal repos (offline-safe by construction).
- [ ] **P3.5 — App security:** biometric lock (expo-local-authentication), FLAG_SECURE / iOS privacy screen; field-level crypto **reused from `packages/core/crypto`** — verify the WebCrypto surface it uses exists in RN (polyfill `expo-crypto`/`react-native-quick-crypto` if not) and run test-plan SEC-1 cross-platform round-trip (web↔android↔ios) before any mobile write of sealed fields. Flag for human review — do not let a small model swap crypto primitives to make a polyfill fit.

## 8. Phase 4 — Monetization + release

- [ ] **P4.1 — RevenueCat** RN SDK → same `entitlements` semantics; gates via shared `@pocketcare/entitlements`, offline-capable; Free/Premium boundary copied from the web gate map, not re-decided.
- [ ] **P4.2 — CI/CD:** EAS Build (or fastlane if self-managed — decide in-task) with lanes: unit+Hermes-spec, integration (local Supabase), device (Firebase Test Lab — test plan §TL), beta (Play internal / TestFlight), staged rollout 5→20→100%. `expo-updates` for JS-only hotfixes; policy: any native-module or SDK change = store build.
- [ ] **P4.3 — Store prep:** privacy labels matching reality (diagnostics are opt-in share only), data-safety forms, `assetlinks.json` + `apple-app-site-association` on the web origin (touches `apps/web/public/` — named exception).
- [ ] **P4.4 — Launch gate:** test-plan exit criteria green; TalkBack/VoiceOver pass on S1; hi/nl flagged reviews resolved or accepted.

## 9. Risks / open decisions (human calls)

- **Single-React / Expo SDK choice (P0.1)** — the one place this plan can break the web build; validated in Phase 0 by running `next build` in the same CI.
- **Hermes `Intl` coverage** for hi-IN/nl formatting — L1 catches it; fix is polyfill, never a core fork.
- **Crypto polyfill (P3.5)** and Google-native-auth token exchange — the two tasks needing a stronger model or human pairing.
- Wearables remain out of scope; the snapshot pattern is designed to extend to them.
- OTA update policy vs App Store review comfort — human decision at P4.2.
