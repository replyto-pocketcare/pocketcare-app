# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — P0.2+P0.3 confirmed running by human;
               built P0.4a/P0.4b (vector runners, both platforms, empty
               registries) then P1.1a/P1.1b (money — the FIRST real domain
               port, both platforms) in the same session. Told to "move
               ahead" after P0.4 shipped, so kept going rather than
               stopping to wait for a build report — none of this is
               build-verified yet, that's the very next step.
Android state: P0.2 DONE, P0.4a DOING, P1.1a DOING (commit 7d3107a).
               domain/src/main/.../money/Money.kt: 13/14 fns ported
               (money, fromMajor, toMajor, minorUnits, add, subtract,
               negate, scale, sum, convert, split, itemsReconcile,
               isZero/isNegative); format() deferred (150+-entry locale
               table, cross-platform ICU string risk, own follow-up task).
               domain/src/test/.../money/MoneyVectors.kt registers all 13
               into FunctionRegistry, called from VectorRunnerTest.money().
iOS state:     P0.3 DONE, P0.4b DOING, P1.1b DOING (commit 7d3107a).
               Domain/Sources/Domain/Money.swift: same 13 fns, same
               deferrals. Domain/Tests/DomainTests/MoneyVectors.swift
               registers them, called from VectorRunnerTests.testMoney().
Vectors:       DONE (P0.1). tools/golden-vectors -> vectors/*.json, 16
               domain files, 250 vectors, >=1 per public function.
Next up:       Human runs the real build/test on both platforms — this is
               the first attempt at BOTH the vector-runner infra (P0.4)
               AND real domain logic (P1.1) together, so treat everything
               as unverified: Android `cd apps/android && ./gradlew test`,
               iOS `cd apps/ios && xcodegen generate && xcodebuild test
               -project PocketCare.xcodeproj -scheme PocketCare
               -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
               Expect "[vectors] domain=money total=40 passed=37 skipped=3
               failed=0" (money.json has 40 vectors across 14 fns, 3 of
               them format() -- unregistered, deferred, always skip) and
               all-skipped for the other 15 domains. Report back whatever
               actually prints
               — money's rounding edge cases (fromMajor(0.005), scale's
               half-away-from-zero case) are the highest-value things to
               check first if anything's wrong.
Traps/notes:   **Kotlin AND Swift block comments both nest** — never write
               a literal `/*` inside a `/** ... */` doc comment. iOS files
               use only `//`/`///` line comments to sidestep this
               entirely. **Golden-vector registries are keyed by (domain,
               fn)**, not fn alone. **Money rounding**: Kotlin uses
               BigDecimal.valueOf(Double).setScale(0, HALF_UP) (NOT
               kotlin.math.round — its tie-break rule isn't documented as
               round-half-away-from-zero); Swift uses the stdlib's
               explicit `.toNearestOrAwayFromZero`. **Currency decimal
               places**: Kotlin uses java.util.Currency (authoritative);
               Swift has no equally-authoritative single API, so it uses
               an explicit verified ISO 4217 exception table instead of
               trusting NumberFormatter's automatic behavior (search
               surfaced inconsistent-behavior reports). **Raw numeric JSON
               comparison differs by platform**: Kotlin's JsonElement
               equality is TEXTUAL (500.0 != 500), needed Vectors.kt's
               jsonNumber() helper; Swift's NSNumber `isEqual` is
               VALUE-based, no helper needed there — don't assume the two
               platforms need identical workarounds. **Always check a
               thrown error's TYPE, not just its message** when
               vector.throws.name isn't the generic "Error" — both
               runners had this gap until this session; fixed in
               VectorRunnerTest.kt / VectorRunnerTests.swift.
               COMMIT EVERY SESSION, even docs-only ones.
Blocked:       Nothing structurally blocked. Everything from this session
               is waiting on the human's next build attempt (sandbox has no
               JDK/Gradle/Xcode/Swift toolchain to verify locally).
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
| P1.2a / P1.2b | ledger — Android / iOS | [M] | P1.1 same-platform | TODO / TODO |
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
