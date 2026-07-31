# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — money+ledger+finance+budget (P1.1-
               P1.3) confirmed green on both platforms, then ported
               splits-insights + splits-math (P1.4, commit 17291cb).
               Android confirmed green via human `./gradlew test` ->
               BUILD SUCCESSFUL. iOS hit 2 more real Swift 6 build
               errors post-port, both fixed same session:
               (a) 27a91cb -- SplitsInsights.swift's shared global
               ISO8601DateFormatter flagged non-Sendable; fixed by
               allocating fresh per call in parseIsoMillis (chose this
               over nonisolated(unsafe) since it's production code with
               real concurrent-Task risk, and ISO8601DateFormatter's
               thread-safety isn't an Apple-documented guarantee).
               (b) 6f320b9 -- global test fixtures (fixtureEdges/
               fixtureSettlements) flagged non-Sendable because
               FriendEdge/FriendSettlement are public structs from a
               DIFFERENT module (Domain, consumed via @testable import
               from DomainTests) -- Swift's automatic Sendable synthesis
               only applies within the same module. Fixed proactively by
               adding explicit Sendable to all 18 plain-data public
               structs across Sources/Domain (not just the 2 flagged),
               to preempt this recurring for P1.5+. FriendStats (a real
               mutable final class) deliberately left non-Sendable.
               NEITHER iOS fix has been build-verified yet -- next step.
Android state: money/ledger/finance/budget/splits-insights/splits-math
               all DONE+green (human-confirmed `./gradlew test` BUILD
               SUCCESSFUL for P1.4).
iOS state:     money/ledger/finance/budget DONE+green. P1.4 DOING:
               SplitsInsights.swift + SplitsMath.swift ported (17291cb),
               2 more build errors found+fixed (27a91cb, 6f320b9), not
               yet re-verified by `swift test`.
Vectors:       DONE (P0.1), 250 total. 97 registered (87 confirmed
               green + 10 new P1.4: Android confirmed, iOS pending
               reverify); 153 still fully skipped across 10 unported
               domains.
Next up:       Human runs `cd apps/ios/Domain && swift test`. Expect
               splits-insights 6/6/0, splits-math 4/4/0 (total/passed/
               skipped), same as Android. If green, mark P1.4 DONE and
               move to P1.5 receipts ([H] tag -- strong model/
               human-paired per the standing rule, needs only P1.1).
Traps/notes:   Kotlin/Swift block comments both NEST -- grep for literal
               `/*` before every commit. Bare int literals need explicit
               widening on both platforms (Int64(0) / 0L). Registries
               keyed by (domain, fn). iOS: `swift test --package-path
               Domain` for real vector tests, NOT `xcodebuild test
               -scheme PocketCare` (App-level placeholder only). Swift's
               NSNumber.isEqual is NOT trustworthy for fractional
               doubles -- jsonValueEqual compares .doubleValue directly.
               Swift 6 strict concurrency: any public struct from
               Sources/Domain that a *Vectors.swift file puts in a
               global `let` fixture needs explicit `Sendable` -- add it
               to new structs as you write them, don't wait for the
               compiler to flag it. COMMIT EVERY SESSION.
Blocked:       Nothing structurally. P1.4's 2 latest iOS fixes
               (27a91cb, 6f320b9) await their first real build/test run.
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
| P1.4a / P1.4b | splits+insights — Android / iOS | [M] | P1.1 | DONE (2026-07-31, 17291cb — human confirmed `./gradlew test` BUILD SUCCESSFUL, splits-insights 6/6/0 + splits-math 4/4/0) / DOING (17291cb + fixes 27a91cb, 6f320b9 — 4/4 fns, 10 vectors, 2 real Swift 6 build errors found+fixed, NOT yet re-verified by `swift test`) |
| P1.5a / P1.5b | receipts — Android / iOS | [H] | P1.1 | TODO / TODO |
| P1.6a / P1.6b | upi+sync-policy+diagnostics — Android / iOS | [M] | P1.1 | TODO / TODO |
| P1.7a / P1.7b | entitlements+gate map — Android / iOS | [S] | P0.4 | TODO / TODO |

### Phase 2 — data layer
Not expanded yet — expand once Phase 1 is ~80% DONE (plan §6).

### Phase 3+ (UI slices S1–S6, native surfaces P4.x, release P5.x)
Not expanded yet (plan §7-8).

## Decisions needing a human (standing list)
- Any new dependency beyond the §0 irreducible set (PowerSync, Supabase SDK, RevenueCat, FCM).
  - ✅ 2026-07-31: `kotlinx.serialization` (test-scope, Android only, P0.4a) — approved in-session for parsing golden-vector JSON in `:domain`, which has no Android SDK and thus no built-in JSON parser. iOS needed no equivalent approval (Foundation's JSONSerialization is already available, not a new dependency).
- [H] tasks: P1.5, and any Phase 2 items once expanded — strong model or human-paired only.
- Exact minimum OS versions (proposal due with P0.2/P0.3: minSdk + iOS min).
- Real bundle ids / Universal-Links domain (plan §10).
