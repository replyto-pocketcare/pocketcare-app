# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — money (P1.1) shipped and hit ONE real
               Xcode build error ("Ambiguous use of 'money'" in Swift's
               sum(), fixed 6be76b9). Human confirmed both apps running,
               then chose "Systematic" over "fast-track a UI slice" when
               asked about sequencing — so P1.2 ledger (both platforms)
               was ported next, same session, per dependency order.
               NOTHING in P1.1 or P1.2 is build-verified yet.
Android state: P1.1a DOING (7d3107a, 13/14 money fns). P1.2a DOING
               (5a705de): domain/.../ledger/Ledger.kt — signedEffectFor,
               deriveBalance, availableBalance, aggregateNetWorth, all 4
               registered via LedgerVectors.kt, wired into
               VectorRunnerTest.ledger().
iOS state:     P1.1b DOING (7d3107a + fix 6be76b9). P1.2b DOING
               (5a705de): Domain/Sources/Domain/Ledger.swift, same 4 fns,
               registered via new LedgerVectors.swift, wired into
               VectorRunnerTests.testLedger().
Vectors:       DONE (P0.1), 250 total. money.json 40 (37 registered/3
               format() deferred). ledger.json 10, all 4 fns registered,
               zero throws vectors.
Next up:       Human runs `cd apps/android && ./gradlew test` and
               `cd apps/ios && xcodegen generate && xcodebuild test
               -project PocketCare.xcodeproj -scheme PocketCare
               -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
               Expect money: total=40 passed=37 skipped=3; ledger:
               total=10 passed=10 skipped=0. Then continue systematically:
               P1.3 finance+budget next (needs P1.2, per plan §5 order).
Traps/notes:   Kotlin/Swift block comments both NEST — grep new files for
               literal `/*` inside doc comments before every commit.
               Swift: bare integer literals (e.g. `0`) are ambiguous
               between money(Int64,_) / money(Double,_) throws overloads
               — always write Int64(0) explicitly; ledger's
               aggregateNetWorth applied this proactively. Registries are
               keyed by (domain, fn). COMMIT EVERY SESSION.
Blocked:       Nothing structurally blocked — sandbox has no JDK/Gradle/
               Xcode/Swift toolchain, everything waits on the human's
               next build attempt.
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
| P0.4a | Vector runner — Android (kotlin.test) | [S] | P0.1, P0.2 | DOING (2026-07-31, claude-sonnet-5) |
| P0.4b | Vector runner — iOS (XCTest) | [S] | P0.1, P0.3 | DOING (2026-07-31, claude-sonnet-5) |
| P0.5 | PROJECT_REFERENCE "Native mobile" section + parity table | [S] | — | DONE (2026-07-31, same session as this file) |

### Phase 1 — domain ports (one row = one platform = one task)
| ID | Task | Tag | Needs | Status |
|---|---|---|---|---|
| P1.1a / P1.1b | money — Android / iOS | [M] | P0.4a / P0.4b | DOING (2026-07-31, claude-sonnet-5, commit 7d3107a — 13/14 fns, format() deferred, NOT build-verified) / DOING (same) |
| P1.2a / P1.2b | ledger — Android / iOS | [M] | P1.1 same-platform | DOING (2026-07-31, claude-sonnet-5, commit 5a705de — 4/4 fns, 10 vectors, NOT build-verified) / DOING (same) |
| P1.3a / P1.3b | finance+budget — Android / iOS | [M] | P1.2 | TODO / TODO |
| P1.4a / P1.4b | splits+insights — Android / iOS | [M] | P1.1 | TODO / TODO |
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
