# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — P0.2 DONE: Android `./gradlew build
               test` BUILD SUCCESSFUL (AGP 9.2.0/Gradle 9.4.1/built-in
               Kotlin, after 3 real fix rounds) and human confirmed it runs
               on-device. Now starting P0.3: did a pre-emptive iOS version
               audit BEFORE the first real xcodegen/xcodebuild attempt
               (lesson from Android's reactive-fix cost), found + fixed 2
               real bugs by reading docs, human about to attempt the first
               real build.
Android state: DONE. `./gradlew build test` green, installs + runs on a
               physical device via `installDebug`. apps/android/README.md
               has a "Run on a device" section (USB debugging, adb,
               Android Studio emulator, wireless debugging).
iOS state:     project.yml/Package.swift never generated or built — about
               to attempt the first real build. Pre-build audit (verified
               via search 2026-07-31, not yet build-verified) found: (1)
               project.yml's SWIFT_VERSION was "6.0", should be "6" — Xcode's
               Swift Language Version build setting takes major-version-only
               values (4/4.2/5/6), not toolchain patch versions; fixed. (2)
               README/CI's simulator destination was "iPhone 16", doesn't
               match Xcode 26.x's actual default-provisioned lineup (iPhone
               17 Pro/Pro Max/Air); changed to "iPhone 17 Pro". Domain/
               Package.swift's "swift-tools-version: 6.0" is a DIFFERENT,
               correctly-dotted axis (SwiftPM manifest tools version, not
               the Xcode language-mode setting) — left as-is. Still 0 real
               builds attempted; these are doc/search-verified corrections,
               not build-verified ones — more real errors are plausible on
               first attempt, same as Android's first round.
Vectors:       DONE (P0.1). tools/golden-vectors -> vectors/*.json, 16
               domain files, 250 vectors, >=1 per public function.
Next up:       Human runs (apps/ios): `brew install xcodegen` (if needed),
               `xcodegen generate`, `swift test --package-path Domain`
               (fast path, no simulator), then `xcodebuild test -project
               PocketCare.xcodeproj -scheme PocketCare -destination
               'platform=iOS Simulator,name=iPhone 17 Pro'` — report any
               error back rather than guessing further. P0.4a (Android
               vector runner) is unblocked but not started — iOS is the
               active thread. Also open: applicationId/bundle-id/App-Group
               placeholders (plan §10) still need a human "yes" on both
               platforms before any store submission.
Traps/notes:   **Kotlin block comments nest** — never write a literal `/*`
               inside a `/** ... */` doc comment (glob paths like
               `foo/*.json` are a classic accidental trigger). **AGP 9.0+
               built-in Kotlin**: applying the kotlin-android plugin
               alongside AGP 9.x is now a hard error — use
               `libs.plugins.kotlin.jvm` for pure-JVM modules only, nothing
               extra for Android modules. **Xcode SWIFT_VERSION build
               setting wants "6", not "6.0"** — different from SwiftPM's
               dotted `swift-tools-version`, don't confuse the two when
               scaffolding new targets. CI jobs `android`/`ios` in
               .github/workflows/ci.yml (gradle-version "9.4.1", iOS
               simulator "iPhone 17 Pro"). Android CI uses
               gradle/actions/setup-gradle (runs `gradle`, NOT `./gradlew`).
               iOS CI runs `xcodegen generate` fresh every time. Neither CI
               job blocks `deploy-production`.
               COMMIT EVERY SESSION, even docs-only ones.
Blocked:       P0.3 blocked on ever attempting a first build (sandbox has
               no JDK/Gradle/Xcode/Swift toolchain).
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
| P0.3 | iOS skeleton (`apps/ios`, SwiftPM `Domain`, App Group) | [M] | — | DOING (2026-07-31, claude-sonnet-5) |
| P0.4a | Vector runner — Android (kotlin.test) | [S] | P0.1, P0.2 | TODO |
| P0.4b | Vector runner — iOS (XCTest) | [S] | P0.1, P0.3 | TODO |
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
- [H] tasks: P1.5, and any Phase 2 items once expanded — strong model or human-paired only.
- Exact minimum OS versions (proposal due with P0.2/P0.3: minSdk + iOS min).
- Real bundle ids / Universal-Links domain (plan §10).
