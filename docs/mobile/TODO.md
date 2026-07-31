# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — P0.2 AND P0.3 both DONE: human
               confirmed both apps built, tested, and RUNNING (Android on
               device via installDebug, iOS on simulator via Xcode). Built
               P0.4a + P0.4b (golden-vector runners, both platforms) in the
               same session — not yet build-verified, that's the immediate
               next step.
Android state: DONE (P0.2). `./gradlew build test` green on AGP 9.2.0/
               Gradle 9.4.1/built-in Kotlin, runs on-device. P0.4a added:
               domain/src/test/kotlin/.../vectors/{Vectors,FunctionRegistry,
               VectorRunnerTest}.kt — loads tools/golden-vectors/vectors/*
               via a Gradle test-resources srcDir (no copy), one @Test per
               domain (16), all skipped until FunctionRegistry is
               populated by Phase 1 tasks. Needed kotlinx.serialization
               (human-approved in-session — real dependency decision,
               :domain has no Android SDK / no free JSON parser) — 1.11.0,
               confirmed compatible with Kotlin 2.4.10 via search.
iOS state:     DONE (P0.3). `xcodebuild test` green after 2 real-build
               fixes (SWIFT_VERSION "6.0"->"6", missing PocketCareTests
               Info.plist), confirmed running on simulator. P0.4b added:
               Domain/Tests/DomainTests/{VectorFixtures,FunctionRegistry,
               VectorRunnerTests}.swift — SwiftPM can't declare resources:
               outside the package, so vectors are read straight off disk
               via a path computed from #filePath at runtime instead of
               bundled. Same empty-registry/all-skipped design as Android,
               one test method per domain (16), mirrors it 1:1.
Vectors:       DONE (P0.1). tools/golden-vectors -> vectors/*.json, 16
               domain files, 250 vectors, >=1 per public function.
Next up:       Human runs the real build on both platforms to verify P0.4:
               Android `cd apps/android && ./gradlew test` (should show
               "[vectors] domain=X total=Y passed=0 skipped=Y failed=0"
               for all 16 domains); iOS `cd apps/ios && xcodegen generate
               && xcodebuild test -project PocketCare.xcodeproj -scheme
               PocketCare -destination 'platform=iOS Simulator,name=iPhone
               17 Pro'` (same expected shape via print()). If either
               fails, report back — this is genuinely new code, unlike the
               dependency-version fixes, so treat it as unverified. Once
               green, P0.4a/P0.4b -> DONE and P1.1a/P1.1b (money — Android/
               iOS, the first real domain port) unblock.
Traps/notes:   **Kotlin AND Swift block comments both nest** — never write
               a literal `/*` inside a `/** ... */` doc comment (a glob
               path like `foo/*.json` is the classic accidental trigger;
               hit this twice this session, once in Placeholder.kt, once
               while writing VectorRunnerTest.kt). The iOS vector-runner
               files sidestep this by using only `//`/`///` line comments,
               never `/* */` — worth doing generally in new Swift files.
               **AGP 9.0+ built-in Kotlin**: applying kotlin-android
               alongside AGP 9.x is a hard error. **Xcode SWIFT_VERSION
               wants "6"**, not a dotted version (different axis from
               SwiftPM's `swift-tools-version`). **SwiftPM resources:
               can't reference paths outside the package** — use a
               #filePath-relative runtime path instead when a Swift target
               needs to read repo-root fixtures; Gradle's sourceSets
               resources.srcDir has no such restriction. Golden-vector
               registries on both platforms are keyed by (domain, fn), not
               fn alone — the JSON's "fn" field isn't unique across
               domains. CI jobs `android`/`ios` in .github/workflows/ci.yml
               (gradle-version "9.4.1", iOS simulator "iPhone 17 Pro") —
               still only run the existing build+test, not yet updated to
               specifically surface vector pass counts, though the test
               output itself already contains them via println/print.
               COMMIT EVERY SESSION, even docs-only ones.
Blocked:       Nothing structurally blocked. P0.4a/P0.4b DONE status is
               waiting on the human's next build attempt (sandbox has no
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
| P1.1a / P1.1b | money — Android / iOS | [M] | P0.4a / P0.4b | TODO / TODO |
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
