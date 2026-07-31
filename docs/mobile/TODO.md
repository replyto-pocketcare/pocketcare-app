# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — FIRST fully green build on both
               platforms. money+ledger+finance+budget (P1.1-P1.3) all
               confirmed passing by the human on real `./gradlew test` /
               `swift test` runs. Getting there took 3 real, non-obvious
               Swift fixes AFTER "compiled" but before "all green": (1)
               `xcodebuild test -scheme PocketCare` doesn't run the
               Domain package's own tests at all (two separate test
               tracks by design -- `swift test --package-path Domain` is
               the one that matters); (2) Swift 6 strict concurrency
               rejected FunctionRegistry's mutable `static var` (fixed
               with `nonisolated(unsafe)`, 29a9d01); (3) NSNumber.isEqual
               returned false for two textually-identical fractional
               doubles from different construction paths -- replaced
               with a value-based recursive comparator (77607ac),
               mirroring the jsonElementsEqual fix already made on the
               Kotlin side. Kotlin needed zero fixes after "compiled."
Android state: money 7d3107a, ledger 5a705de, finance+budget e8ef8b8 --
               all DONE, human-confirmed green.
iOS state:     money 7d3107a+6be76b9, ledger 5a705de, finance+budget
               e8ef8b8, plus infra fixes 29a9d01 (concurrency) and
               77607ac (NSNumber equality) -- all DONE, human-confirmed
               green.
Vectors:       DONE (P0.1), 250 total. 87 registered and passing (money
               37/40, ledger 10, finance 33, budget 10); 163 still fully
               skipped across the 12 unported domains.
Next up:       P1.4 splits+insights (needs only P1.1, per plan §5) --
               starting now, same session, per "let's move ahead."
Traps/notes:   Kotlin/Swift block comments both NEST -- grep for literal
               `/*` before every commit. Swift: bare int literals are
               ambiguous against Int64/Double overloads -- always
               Int64(0) explicitly; Kotlin needs 0L for the same reason.
               Registries keyed by (domain, fn). iOS has TWO test
               commands -- `swift test --package-path Domain` for the
               actual vector tests, `xcodebuild test -scheme PocketCare`
               only for the App-level placeholder -- always ask for the
               former's output, not just "it compiled." Swift's
               NSNumber.isEqual is NOT trustworthy for fractional
               doubles -- VectorRunnerTests.swift's jsonValueEqual now
               compares .doubleValue directly instead. COMMIT EVERY
               SESSION.
Blocked:       Nothing. Both platforms verified end-to-end for the first
               time this session.
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
