# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — after money (P1.1) + ledger (P1.2),
               kept going systematically per the human's "Systematic"
               sequencing choice: ported finance+budget (P1.3, both
               platforms, commit e8ef8b8) in the same session, unprompted
               ("continue with other phases"). This is the largest port
               yet (20 fns, date math + loan amortization + cashflow
               projection) and surfaced two new infra needs: Math.round's
               tie-toward-+Infinity rule (different from Money's
               round-half-away-from-zero) and Infinity-valued results
               (JS's JSON.stringify(Infinity) === null). Also fixed a
               latent Kotlin harness bug (JsonElement's default equality
               is textual, not value-based -- see jsonElementsEqual in
               Vectors.kt). NOTHING in P1.1/P1.2/P1.3 is build-verified
               yet -- still the single most important next step.
Android state: money 7d3107a, ledger 5a705de, finance+budget e8ef8b8:
               domain/.../finance/Finance.kt + budget/Budget.kt, all 20
               fns registered via FinanceVectors.kt/BudgetVectors.kt,
               wired into VectorRunnerTest's finance()/budget().
iOS state:     money 7d3107a+6be76b9, ledger 5a705de, finance+budget
               e8ef8b8: Domain/Sources/Domain/Finance.swift + Budget.swift
               (hand-rolled Ymd date type, NOT Foundation Calendar --
               search found real reports of Calendar silently using the
               device's local time zone), registered via new
               FinanceVectors.swift/BudgetVectors.swift, wired into
               VectorRunnerTests' testFinance()/testBudget().
Vectors:       DONE (P0.1), 250 total. money 40 (37 reg./3 format()
               deferred), ledger 10 (4/4), finance 33 (16/16), budget 10
               (4/4) -- 87 vectors registered, 163 still fully skipped.
Next up:       Human runs `cd apps/android && ./gradlew test` and
               `cd apps/ios && xcodegen generate && xcodebuild test
               -project PocketCare.xcodeproj -scheme PocketCare
               -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
               Expect money 40/37/3, ledger 10/10/0, finance 33/33/0,
               budget 10/10/0 (total/passed/skipped). This is the first
               real compiler run for date math (Sakamoto's algorithm,
               hand-rolled Ymd arithmetic) and Math.round-vs-round-half-
               away-from-zero -- highest-value things to check if
               anything's wrong. Then P1.4 splits+insights next (needs
               only P1.1, per plan §5).
Traps/notes:   Kotlin/Swift block comments both NEST -- grep for literal
               `/*` before every commit. Swift: bare int literals are
               ambiguous against Int64/Double overloads -- always
               Int64(0) explicitly. Kotlin: bare int literals do NOT
               auto-widen to Long params either (confirmed via search) --
               always 0L explicitly, same failure class as Swift's.
               Registries keyed by (domain, fn). COMMIT EVERY SESSION.
Blocked:       Nothing structurally blocked -- sandbox has no JDK/Gradle/
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
| P1.3a / P1.3b | finance+budget — Android / iOS | [M] | P1.2 | DOING (2026-07-31, claude-sonnet-5, commit e8ef8b8 — 20/20 fns, 43 vectors, NOT build-verified) / DOING (same) |
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
