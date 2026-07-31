# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — after iOS xcodebuild confirmed green
               (see prior entries: Android opData parallel-bug fix +
               P2.3 diagnostics wiring, commit bbb90c4), user said "yes
               please" to starting P2.5. Began with ledger (accounts +
               transactions + balance/net-worth derivation), the
               dependency root every other domain's repository will read
               off. New files, both platforms: WriteHelpers.kt/.swift
               (Kotlin/Swift mirror of apps/web/src/write.ts's
               insertRow/updateRow/softDelete — generic synced-row
               helpers every repository builds writes on) and
               LedgerRepository.kt/.swift (accounts/transactions reads +
               writes; watchAccountBalances/watchNetWorth call the
               already-ported deriveBalance/aggregateNetWorth, i.e. the
               actual point of P2.5 — never recomputing balance math
               here). Schema confirmed against PocketCareSchema.kt/.swift
               (P2.1) column-by-column, not assumed; query shapes copied
               from apps/web/src/hooks.ts's real useAccountBalances/
               useNetWorth/useBlockedByAccount/useRates so mobile matches
               the web app's actual behavior (IFNULL defaults, emergency-
               fund exclusion, latest-rate-wins ordering) rather than a
               plausible-looking reimplementation.
Real API findings this session (source-verified, not guessed): Kotlin's
               Queries.watch returns Flow<List<T>> with a real combine()
               operator — used freely for watchAccountBalances/
               watchNetWorth. Swift's Queries.watch returns
               AsyncThrowingStream<[T], Error>, which has NO built-in
               combine/combineLatest — building one blind (no compiler)
               was judged disproportionate risk for Phase 2's actual
               Done-when (TP L3 sync correctness, not UI reactivity), so
               iOS's derived views (accountBalances/netWorth) are one-shot
               async snapshots instead of reactive streams; single-table
               reads (watchAccounts/watchTransactions) ARE real streams.
               This is a genuine, documented platform asymmetry, not an
               oversight — flagged inline in LedgerRepository.swift's
               header comment for whoever wires up UI in Phase 3+.
               RateLookup (both platforms) is a plain function-type alias,
               NOT a `fun interface`/functional-interface protocol — built
               as a lambda assigned to an explicitly-typed val, not via a
               SAM-style `RateLookup { ... }` constructor call (that
               syntax needs an actual functional interface). Kotlin
               Boolean columns written as explicit Long 0/1, not Boolean,
               since the SQLite bind layer's Boolean support wasn't
               independently confirmed from this sandbox.
Android state: 16/16 Phase 1 domains DONE. :data module (P2.2a/P2.3a/
               P2.4a) source-verified per prior entries, STILL NEVER
               build-verified — no `./gradlew build` has run against
               this code at any point in this whole arc. P2.5a: 1/7
               domains (ledger) done, same never-build-verified caveat.
iOS state:     16/16 Phase 1 domains DONE. Data package (P2.2b/P2.3b/
               P2.4b): xcodebuild confirmed green through round 3 + the
               P2.3 diagnostics wiring is NOT yet re-verified since that
               addition (prior entry). P2.5b: 1/7 domains (ledger) done,
               also not yet real-compiler-verified.
Vectors:       DONE (P0.1), 250/250 green on both platforms (Phase 1).
Next up:       Get a real compiler run on BOTH platforms for the P2.5
               ledger slice (this is genuinely new, more complex surface
               — SQL string building, cursor mapping, generic dictionaries
               — than the P2.2-P2.4 fixes so far). Then continue P2.5 in
               dependency order: finance+budget next (reads ledger's
               accounts), then splits, receipts, upi. P2.6 (repair logic)
               still fully untouched.
Traps/notes:   Same traps from rounds 1-3, plus this session's two new
               findings above (Flow.combine vs no AsyncThrowingStream
               equivalent; RateLookup as a plain lambda, not a SAM call).
Blocked:       P2.2/P2.3/P2.4/P2.5 all still BLOCKED on TP L3 (real sync
               round-trip against reachable Supabase infra) even once a
               piece compiles clean — that's a materially higher bar than
               "compiles," per Phase 2's Done-when. Android additionally
               blocked on ever getting a first real Gradle build this
               entire arc.
```

## Rules (short form — full protocol in plan §1)

- Claim **1 task (max 3)** you can FINISH this session. Match your tag: [S] small-model OK · [M] mid · [H] strong model/human-paired.
- Statuses: `TODO` → `DOING (date, model)` → `DONE (date, commit)` | `BLOCKED (reason)`.
- DONE requires the task's *Done-when* in the plan to have passed — show the output. For P0.2/P0.3 that means real Gradle/Xcode output (CI or human machine), not "the files exist."
- Can't finish → revert incomplete code, mark BLOCKED with one line. Never leave a broken tree.
- **End of session: statuses updated here + Handover rewritten + one line in `PROJECT_REFERENCE.md` mobile change log + COMMIT. Not optional — see the trap above.**
- Dependencies: don't claim a task whose "Needs" isn't DONE.

## Queue

### Phase 0 — vectors + skeletons
| ID | Task (plan ref) | Tag | Needs | Status |
|---|---|---|---|---|
| P0.0 | Decommission RN scaffold | [M] | — | DONE (2026-07-31, N/A — never committed, removed by repo reset) |
| P0.1 | Golden-vector exporter (`tools/golden-vectors/export.ts`) | [M] | — | DONE (2026-07-31, 8e8bcfd) |
| P0.2 | Android skeleton (`apps/android`, pure-Kotlin `:domain`) | [M] | — | DONE (2026-07-31, dc923f2 — human ran `./gradlew build test`, BUILD SUCCESSFUL, on AGP 9.2.0/Gradle 9.4.1/built-in Kotlin) |
| P0.3 | iOS skeleton (`apps/ios`, SwiftPM `Domain`, App Group) | [M] | — | DONE (2026-07-31, 1b3804a — human ran `xcodebuild test`, passed, app confirmed running on simulator) |
| P0.4a | Vector runner — Android (kotlin.test) | [S] | P0.1, P0.2 | DONE (2026-07-31, human ran `./gradlew test`, all registered domains green) |
| P0.4b | Vector runner — iOS (XCTest) | [S] | P0.1, P0.3 | DONE (2026-07-31, human ran `swift test`, all registered domains green after 2 real fixes — see change log) |
| P0.5 | PROJECT_REFERENCE "Native mobile" section + parity table | [S] | — | DONE (2026-07-31, same session as this file) |

### Phase 1 — domain ports (one row = one platform = one task)
| ID | Task | Tag | Needs | Status |
|---|---|---|---|---|
| P1.1a / P1.1b | money — Android / iOS | [M] | P0.4a / P0.4b | DONE (2026-07-31, 7d3107a + Swift fix 6be76b9 — human confirmed `[vectors] domain=money total=40 passed=37 skipped=3 failed=0` both platforms) / DONE (same) |
| P1.2a / P1.2b | ledger — Android / iOS | [M] | P1.1 same-platform | DONE (2026-07-31, 5a705de — human confirmed `total=10 passed=10 skipped=0 failed=0` both platforms) / DONE (same) |
| P1.3a / P1.3b | finance+budget — Android / iOS | [M] | P1.2 | DONE (2026-07-31, e8ef8b8 + Swift fixes 29a9d01/77607ac — human confirmed `finance total=33 passed=33` and `budget total=10 passed=10`, both `failed=0`, both platforms) / DONE (same) |
| P1.4a / P1.4b | splits+insights — Android / iOS | [M] | P1.1 | DONE (2026-07-31, 17291cb — human confirmed `./gradlew test` BUILD SUCCESSFUL, splits-insights 6/6/0 + splits-math 4/4/0) / DONE (2026-07-31, 17291cb + fixes 27a91cb, 6f320b9 — human confirmed `swift test` green after the two Swift 6 fixes) |
| P1.5a / P1.5b | receipts — Android / iOS | [H] | P1.1 | DONE (2026-07-31, 56a3200 — 4 sub-domains ported, 2 real bugs caught+fixed pre-commit: JS single-`.replace` vs Kotlin's replace-all, findDate UTC-vs-local; human confirmed `./gradlew test` green) / DONE (same commit, human confirmed `swift test` green) |
| P1.6a / P1.6b | reconcile+upi+sync-policy+diagnostics+guardrail — Android / iOS | [M] | P1.1 | DONE (2026-07-31, d895c30 — 5 sub-domains ported: reconcile [FNV-1a bank-drift checksums, hidden U+0001/U+0000 control-byte literals in the TS source caught via raw-byte inspection, not the Read tool's misleading rendering], upi [mulberry32 seeded PRNG for `newPaymentRef`, hand-rolled `encodeURIComponent`/`decodeURIComponent`, non-textbook FNV offset constant caught by cross-checking two candidate values against the real vectors], sync-policy [em-dash/arrow Unicode strings verified byte-exact via Python `ord()`], diagnostics [highest-risk domain after receipts: multi-pass order-sensitive redaction pipeline, `\b` word-boundary regex, ₹€£ symbols]; human confirmed `./gradlew test` green, no fixes needed) / DONE (same commit, human confirmed `swift test` green, no fixes needed) |
| P1.7a / P1.7b | entitlements — Android / iOS | [S] | P0.4 | DONE (2026-07-31, d895c30 — ported faithfully including a source quirk: `Tier` has 4 values but `canUse()` only special-cases "premium", so "lite"/"pro" silently fall through to the free-tier check; not fixed, just documented, since only "free"/"premium" have vector coverage; human confirmed green) / DONE (same commit, human confirmed green). "gate map" deliberately NOT ported — no golden vectors exist for it; it's a UI-side feature-gating table, deferred to Phase 3+ UI work, not pure domain logic. |

**Phase 1 gate cleared 2026-07-31: all 16 domains / 250 vectors green on both `./gradlew test` and `swift test --package-path Domain`, human-confirmed, zero fixes needed on either platform for P1.5-P1.7 (the extra Python cross-check pass against the full TS test surfaces — see PROJECT_REFERENCE.md change log — evidently paid off). Phase 2 below is now expanded.**

### Phase 2 — data layer (expanded 2026-07-31, plan §6)
One task = one platform, same pattern as Phase 1. Order matters: schema parity blocks everything else (repositories/connector/auth all need the models to exist); connector + quarantine are paired (dead-letter needs the connector's retry/backoff hookup); auth is independent of the sync pipeline and can run in parallel once schema parity lands.

| ID | Task | Tag | Needs | Status |
|---|---|---|---|---|
| P2.1a / P2.1b | Schema parity — mirror `AppSchema` (`packages/db/src/index.ts`) as Kotlin data classes / Swift structs + a parity check script (3-way: `AppSchema` ↔ Kotlin ↔ Swift, catches column drift at build/CI time, not runtime) | [M] | P1 (done) | DONE (2026-07-31, 700cd24) / DONE (same commit) |
| P2.2a / P2.2b | PowerSync connector port — op-coalescing upload queue matching `packages/db`'s fault-injection semantics (retry classification via the now-ported `sync-policy` domain, exponential backoff via `backoffMs`) | [M] | P2.1 | Code complete, NOT build-verified (no real Gradle run this whole arc) — BLOCKED (TP L3) / Code complete, xcodebuild clean 3 rounds in a row (human-confirmed 2026-07-31, incl. a real data-correctness fix, see change log) — BLOCKED (TP L3) |
| P2.3a / P2.3b | Quarantine / dead-letter queue — wires `shouldQuarantine`/`MAX_PERMANENT_ATTEMPTS` (already-ported `sync-policy` domain) into the connector's actual retry loop, plus local persistence for quarantined ops so they're inspectable (diagnostics `formatLog`/`makeEntry`, already ported, log them) | [M] | P2.2 | Code complete 2026-07-31 (dead-letter persistence + new DiagnosticsLog.kt wiring `makeEntry`/`formatLog` into the failure path), NOT build-verified — BLOCKED (TP L3) / Code complete 2026-07-31 (dead-letter persistence was already done; new DiagnosticsLog.swift closes the `makeEntry`/`formatLog` gap that was the actual remaining piece), NOT yet re-verified by xcodebuild since this addition — BLOCKED (TP L3) |
| P2.4a / P2.4b | Auth — guest/OTP/Google sign-in, in-place guest→registered upgrade, offline marker so the UI can tell "signed out" from "signed in but offline" | [M] | P2.1 | Code complete, NOT build-verified — BLOCKED (TP L3) / Code complete, Auth.swift confirmed xcodebuild-clean (2026-07-31) — BLOCKED (TP L3) |
| P2.5a / P2.5b | Repositories — read/write facades over the local PowerSync SQLite DB for each domain (money/ledger/finance/budget/splits/receipts/upi), calling the already-ported pure domain functions for any derived value (balances, progress, etc.) rather than recomputing ad hoc | [M] | P2.1, P2.2 | DOING (1/7 domains — ledger done 2026-07-31: WriteHelpers.kt + LedgerRepository.kt, source-verified, NOT build-verified; finance/budget/splits/receipts/upi remain) / DOING (1/7 — WriteHelpers.swift + LedgerRepository.swift, source-verified, NOT build-verified; same remaining list) |
| P2.6a / P2.6b | Repair logic — detect + resolve the drift `reconcile`'s checksums surface (missingRemote/missingLocal/mismatched), matching `packages/db`'s repair semantics | [M] | P2.2, P2.3 | TODO / TODO |

*Done-when (each):* TP L3 (sync integration, per plan's test-plan doc) passes for that piece on that platform — a real PowerSync round-trip against a test Supabase project, not just unit tests of the surrounding logic. This is a materially different verification bar than Phase 1's pure-function vectors: these tasks touch actual I/O (SQLite, network), so "compiles and the domain-logic unit tests pass" is necessary but not sufficient — plan's `docs/plans/full-test-plan.md` L3 fault-injection presets are the real gate.

**P2.1 note:** it does no I/O (it's a static schema mirror, not a connector), so TP L3 doesn't apply to it directly — its actual Done-when was met by (a) all 63 tables/columns/indexes/local-only flags present identically on all three platforms, verified by a bracket-aware structural diff against the real `AppSchema` object (zero mismatches), and (b) the parity-check mechanism itself: regenerating from a clean `AppSchema` reproduces byte-identical output, so a future `git diff` after changing `packages/db/src/index.ts` is the ongoing drift check. See PROJECT_REFERENCE.md change log for the generation approach (introspect + codegen, not hand-transcribe).

### Phase 3+ (UI slices S1–S6, native surfaces P4.x, release P5.x)
Not expanded yet (plan §7-8).

## Decisions needing a human (standing list)
- Any new dependency beyond the §0 irreducible set (PowerSync, Supabase SDK, RevenueCat, FCM).
  - ✅ 2026-07-31: `kotlinx.serialization` (test-scope, Android only, P0.4a) — approved in-session for parsing golden-vector JSON in `:domain`, which has no Android SDK and thus no built-in JSON parser. iOS needed no equivalent approval (Foundation's JSONSerialization is already available, not a new dependency).
- [H] tasks: P1.5, and any Phase 2 items once expanded — strong model or human-paired only.
- Exact minimum OS versions (proposal due with P0.2/P0.3: minSdk + iOS min).
- Real bundle ids / Universal-Links domain (plan §10).
