# Plan — Android & iOS apps: pure native (Kotlin + Swift), three maintained apps

> **Status:** PLANNED (2026-07-31, **rev 3 — current direction**). No native code yet.
> **Rev history:** rev 1 = KMP shared core + native UI (superseded same-day). rev 2 = React Native/Expo, reusing `packages/*` unchanged (attempted; hit a rolling series of third-party build breakages — Xcode/Clang vs. the `fmt` pod's `consteval` usage, `expo-localization`'s switch exhaustiveness against a newer iOS SDK than any release accounts for, three rounds of `lru-cache` default-vs-named-export mismatches under pnpm's hoisted linker, a stale `expo` pin from a string-sort bug — see the "Native mobile" § change log below for the full trail). **Rev 3 (owner decision, 2026-07-31):** stop absorbing other people's dependency churn — **two fully independent native apps**, first-party OS frameworks by default. No cross-platform layer of any kind (not RN, not KMP). Cost accepted knowingly: domain logic exists in three languages (TS/Kotlin/Swift); the discipline that makes this safe is §9 — golden vectors, parity gates, "web is the reference implementation."
> **Executors:** LLM agents working from the queue in `docs/mobile/TODO.md` under the protocol in §1.
> **Companion:** `docs/plans/full-test-plan.md` still describes L0-L6 test layers from the rev-2 era — treat its RN-specific steps (Hermes spec run, Maestro, EAS) as superseded by this doc; L1 golden vectors, L3 sync integration, L5 device-matrix, L6 Playwright still apply, ported to kotlin.test/XCTest instrumentation.

## 0. Goal and non-negotiables

Native apps with home-screen **widgets**, iOS **Live Activities**, **native notifications**, against the **unchanged** backend (Supabase + PowerSync). Web keeps working; `apps/web` untouched except named exceptions.

**Dependency policy (the reason for rev 3):** first-party OS frameworks by default. The irreducible third-party set — accepted because replacing them means rebuilding sync/backend/billing: **PowerSync native SDK (Kotlin / Swift)**, **Supabase SDK (supabase-kt / supabase-swift)**, **RevenueCat**, **Firebase Messaging (Android push — no alternative)**. Anything beyond this list requires a human "yes" in the session, recorded in TODO.md. UI, charts (Swift Charts / Compose+custom), OCR (ML Kit on Android, Vision on iOS), crypto (CryptoKit/Keystore), storage — all first-party.

**Golden rules (identical to CLAUDE.md, per-language types):**

1. Money = integer minor units: Kotlin `value class Money(val minor: Long)`, Swift `struct Money { var minor: Int64 }`. **Never** Float/Double/Decimal for stored amounts.
2. Balances derive from the append-only ledger; corrections are compensating entries, never mutation.
3. Everything server-side is in the **`pocketcare`** schema — schema-qualify every call.
4. Server authoritative; the device DB is an offline cache reconciled by sync.
5. Amounts stay in their account's currency; convert only at display via `exchange_rates`.
6. Never a cross-row constraint on a synced table (wedges the upload queue — CLAUDE.md).
7. Soft-delete via `deleted_at`; every read filters it.
8. **Web is the spec.** Any "how should this behave" question is answered by reading `apps/web` / `packages/*` source and the golden vectors — never by deciding fresh.

## 1. Executor protocol (queue + handover)

**The queue is `docs/mobile/TODO.md`.** This plan defines tasks; TODO.md tracks them. Rules:

1. **Session start:** read, in order: `PROJECT_REFERENCE.md` §"Native mobile" → `docs/mobile/TODO.md` (top **Handover** block first) → only the plan sections your claimed tasks cite. Load nothing else until a task requires it.
2. **Claim small:** pick tasks matching your capability tag — **[S]** small-model OK, **[M]** mid, **[H]** strong model / human-paired only. Claim **1 task by default, max 3**, only what you can *finish this session*.
3. **Finish means the task's *Done-when* passed** (build/test output shown). Half-done work is never left silently: either finish, or mark `BLOCKED` with a one-line reason and revert incomplete code.
4. **Session end — mandatory handover, even after a single task:** update TODO.md — task statuses, and rewrite the **Handover** block (≤15 lines). Add one line to the Mobile change log in `AUDIT_HISTORY.md`. **Commit immediately, every session — do not leave planning or code work uncommitted.** (Rev 3 exists partly *because* rev 2's planning docs sat uncommitted for a session and were lost in a reset; don't repeat that.)
5. **Never without explicit human approval in-session:** touch `apps/web` or `packages/*` (exceptions named per task), write a migration, change `sync-streams.yaml`, add ANY dependency (see policy in §0), delete files outside your own task's scope. Sandbox rules: CLAUDE.md (git delete permission first; `pnpm-lock.yaml` not regenerable; no `pnpm`, no Gradle/JDK-compiler/Xcode in the agent sandbox as of rev 3 — Kotlin/Swift build verification runs in CI or on the human's machine, not here).
6. Conflicts: CLAUDE.md > §0 > task text. Unclear → mark BLOCKED and ask; never guess on money, sync, or crypto.

## 2. Architecture decision (ADR)

**Two independent native apps + existing web. No shared runtime code between them.** What IS shared: the backend, `sync-streams.yaml`, the golden-vector fixtures, the design tokens (generated), the i18n catalogs (generated), and the test catalog.

| Rejected | Why |
|---|---|
| React Native / Expo (rev 2) | Attempted; hit a rolling series of third-party breakages (fmt/consteval, expo-localization, lru-cache ×3, stale expo pin) each owned by someone else's release cadence, not this team's. |
| KMP shared core (rev 1) | A cross-platform toolchain is itself the class of dependency being avoided (especially on the iOS side). |
| Capacitor | Not native. |

Per platform (latest stable at execution time — executors check versions, don't assume):
- **Android:** Kotlin 2.x, Jetpack Compose + Material 3, Gradle version catalogs, Glance (widgets), FCM, ML Kit, BiometricPrompt, DataStore, PowerSync **Kotlin** SDK, supabase-kt, coroutines/Flow.
- **iOS:** Swift 6 (strict concurrency), SwiftUI, Swift Charts, WidgetKit + ActivityKit (Live Activities), App Intents, Vision, CryptoKit/LocalAuthentication, PowerSync **Swift** SDK, supabase-swift, structured concurrency.

## 3. Repo layout (target)

```
apps/android/          # :app, :domain (pure Kotlin, no Android deps — vector-tested), :data, :widgets, :baselineprofile
apps/ios/              # App, Domain (pure Swift package — vector-tested), Data, Widgets+LiveActivity targets; XcodeGen project.yml
tools/golden-vectors/  # export.ts + vectors/*.json (single fixture source for BOTH apps)
tools/parity/          # schema-parity + token/i18n generators (§9)
docs/mobile/           # TODO.md (queue+handover) · parity table · per-screen specs
```

`supabase/` and `sync-streams.yaml` shared and unchanged except one planned migration (§7, `push_subscriptions` platform/token columns).

## 4. Phase 0 — Vectors + skeletons  ✅ gate: TP L1

- [x] **P0.0 [M] — Decommission the RN scaffold.** N/A as of rev 3 — the rev-2 `apps/mobile` scaffold was never committed to `origin/main`, so a repo-wide reset (2026-07-31) already removed it along with all uncommitted rev-2 build-fix history from disk. Nothing left to decommission. (The breakage narrative that justified rev 3 is preserved above in this doc's header and in AUDIT_HISTORY.md — it happened, it's just not sitting in the tree as files anymore.)
- [ ] **P0.1 [M] — Vector exporter.** `tools/golden-vectors/export.ts` (`node --experimental-strip-types`): imports the real functions from `packages/core/{money,finance,ledger,budget,receipts,upi,sync-policy,reconcile,guardrail,splits-insights,entitlements,diagnostics}` + `apps/web/src/splits/math.ts` source, runs a fixed corpus covering every edge case in the existing TS tests (largest-remainder, milli-quantities, cross-currency, FIFO settle-speed with `null`-not-zero, redaction passes), writes `vectors/<domain>.json` as `[{fn, input, expected}]` — amounts as strings, deterministic order. (`crypto` excluded — covered by a SEC-1 round-trip test instead, ported per-platform.)
  *Done-when:* two runs byte-identical; ≥1 vector per public function; committed.
- [ ] **P0.2 [M] — Android skeleton.** `apps/android` with `:domain` as a **pure-Kotlin module** (no Android imports — this is what makes vector tests fast and the logic honest), empty Compose app `care.pocket.android`, CI: `./gradlew build test`. **No JDK/Gradle in this sandbox as of rev 3** — write the skeleton, but verification runs in CI or on a human's machine; don't mark this DONE from a sandbox session without that output.
- [ ] **P0.3 [M] — iOS skeleton.** `apps/ios` with `Domain` as a **pure SwiftPM package**, empty SwiftUI app `care.pocket.ios`, App Group `group.care.pocket` configured now, XcodeGen, CI: `xcodebuild test` on simulator. **No Xcode in this sandbox** — same caveat as P0.2.
- [ ] **P0.4 [S]×2 — Vector runners.** kotlin.test runner in `:domain` and XCTest runner in `Domain` that load every JSON vector; all initially skipped, un-skipped per porting task. CI prints per-domain pass counts for both apps side by side.
- [ ] **P0.5 [S] — Docs bootstrap.** Keep `PROJECT_REFERENCE.md` "Native mobile" section (layout, ADR, progress line) in sync with this plan; session logs go to `AUDIT_HISTORY.md`, parity table lives in `docs/mobile/TODO.md`. Verify `docs/mobile/TODO.md` matches this plan's tasks.

## 5. Phase 1 — Port the domain, twice  ✅ gate: all vectors green on both apps

Port order = dependency order. **Each domain × each platform is its own task** (claim one at a time). Port from the TS source; the vectors decide correctness, not your reading of the code. Also port the TS tests not expressible as vectors (error paths).

| # | Domain | Android task | iOS task | Tag |
|---|---|---|---|---|
| P1.1 | money (arithmetic/allocation; formatting via `android.icu` / `NumberFormatter`) | [M] | [M] | |
| P1.2 | ledger (postings, derived balances, opening/adjustment) | [M] | [M] | |
| P1.3 | finance + budget (periods, thresholds, CC cycle) | [M] | [M] | |
| P1.4 | splits math + splits-insights (largest-remainder, pairwise edges, FIFO, thresholds) | [M] | [M] | |
| P1.5 | receipts (allocation, exact reconciliation, milli-quantities, text parsing) | [H] | [H] | parsing is subtle |
| P1.6 | upi + sync-policy + diagnostics redaction | [M] | [M] | |
| P1.7 | entitlements + gate map (copied from web's, not re-decided) | [S] | [S] | |

*Done-when (each):* that domain's vectors 100% green on that platform + ported negative-path tests green.

## 6. Phase 2 — Data layer, twice  ✅ gate: TP L3 on both

Not expanded into individual tasks yet — expand once Phase 1 is ~80% done (keeps this doc from drifting stale before it's relevant). Known shape from the rev-2 planning (still valid): 3-way schema parity script (`AppSchema` ↔ Kotlin ↔ Swift models), connector port (op-coalescing, fault injection matching `packages/db`'s), quarantine/dead-letter, auth (guest/OTP/Google, in-place upgrade, offline marker), repositories, repair logic.

## 7. Phase 3+4 — UI slices and native surfaces, twice

Not expanded yet. Slices mirror web's feature index (S1 onboarding/accounts/transactions/dashboard-lite → S2 budgets/goals/cashflow/cards → S3 splits/UPI → S4 receipts/statements → S5 investments/insights → S6 assistant), plus native-only surfaces (P4.x: widgets, Live Activities, native push, biometric lock). One planned backend migration lives here: `push_subscriptions` gains `platform`/`token`/`live_activity_token` columns + a `notify-dispatch` fan-out — do not start it without a human "yes" (§0 dependency/migration policy).

## 8. Phase 5 — Monetization + release

Not expanded yet. RevenueCat wiring (entitlements parity with web's `useEntitlement`), store listings, release signing, staged rollout.

## 9. Drift control — the three-app tax, managed

**Golden vectors are the law.** A red vector is fixed by fixing the port, never the vector. Any behavior change starts in `packages/core` (TS), re-exports new vectors, then both native apps are fixed to match — never the reverse. A 3-way schema parity script (Phase 2) catches `AppSchema`/Kotlin/Swift drift before it ships. Generated design tokens and i18n catalogs (not hand-copied) keep visual/copy parity. **Freeze rule:** a new web feature queues its Android + iOS counterparts in the same change set (as backlog items, not necessarily built same-day) so the parity table (PROJECT_REFERENCE) never silently falls further behind.

## 10. Risks / open decisions (human calls)

- Exact minimum OS versions (minSdk + iOS minimum) — proposal due with P0.2/P0.3.
- Real reverse-DNS bundle ids (`care.pocket.android` / `care.pocket.ios` used above are placeholders) and Universal/App-Links domain — confirm before P4.3 (store prep needs the real domain for `assetlinks.json`/`apple-app-site-association`).
- Market-data API, FX provider, launch languages — same open items as the web roadmap (PROJECT_REFERENCE "Open decisions"), inherited here.
- Any dependency beyond the §0 irreducible set.
