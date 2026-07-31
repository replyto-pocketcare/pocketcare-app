# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (even later still) — P0.2 DONE. Human's Android
               build went through 3 real fix rounds then BUILD SUCCESSFUL:
               (1) Kotlin nested-comment compile error, (2) AGP
               8.6.0->8.13.0 version audit, (3) owner asked for TRUE latest
               Gradle -> migrated to AGP 9.2.0 + Gradle 9.4.1 + built-in
               Kotlin. `./gradlew build test` passes. iOS untouched.
Android state: Round 3: warning said Kotlin Gradle plugin wants Gradle
               >=8.14.4 soon. Rather than just bump within 8.x, owner chose
               real-latest Gradle (9.6.1 stable) — which per Google's own
               policy ("one major AGP version per Gradle major version")
               meant AGP 9.x too, not 8.13.0. Migrated: agp 9.2.0 (9.3
               exists but developer.android.com's compat table hadn't
               published its min-Gradle yet, so used the last
               fully-documented version), Gradle wrapper+CI 9.4.1 (AGP
               9.2.0's exact documented minimum). Applied the built-in-Kotlin
               migration from developer.android.com/build/migrate-to-built-in-kotlin:
               removed kotlin-android plugin from libs.versions.toml,
               root build.gradle.kts, app/build.gradle.kts; removed the
               explicit kotlin.compilerOptions jvmTarget block (now defaults
               from compileOptions.targetCompatibility=17 per the guide).
               :domain (plain kotlin.jvm, not Android) untouched by any of
               this. STILL NOT build-green — human needs to re-run and
               report; built-in Kotlin is new territory for this repo, more
               real errors are plausible.
iOS state:     Unchanged since last session. apps/ios/{App,AppTests,Domain}
               + project.yml written, NEVER generated or built. Not part of
               this fix round.
Vectors:       DONE (P0.1). tools/golden-vectors -> vectors/*.json, 16
               domain files, 250 vectors, >=1 per public function.
Next up:       P0.4a (Android vector runner, kotlin.test, needs P0.1+P0.2 —
               both DONE) is now unblocked. Also: human asked how to run
               the app on a device — pointed at USB debugging + `adb
               install` / Android Studio Run, not yet documented in
               README.md, consider adding a short "Run on device" section.
               iOS (P0.3) still needs its first real build attempt AND its
               own version audit (swift-tools-version 6.0, deploymentTarget
               iOS 17 in project.yml) BEFORE that first attempt — Android
               proved "ship unverified versions, fix reactively" costs real
               round trips.
Traps/notes:   **Kotlin block comments nest** — never write a literal `/*`
               inside a `/** ... */` doc comment (glob paths like
               `foo/*.json` are a classic accidental trigger). **AGP 9.0+
               built-in Kotlin**: applying the kotlin-android plugin
               alongside AGP 9.x is now a hard error — don't re-add it by
               habit when scaffolding new Android modules; use
               `libs.plugins.kotlin.jvm` for pure-JVM modules only, nothing
               extra for Android modules under AGP 9.x. CI jobs
               `android`/`ios` in .github/workflows/ci.yml (gradle-version
               now "9.4.1"). Android CI uses gradle/actions/setup-gradle
               (runs `gradle`, NOT `./gradlew`) so it doesn't need the
               human-generated wrapper jar. iOS CI runs `xcodegen generate`
               fresh every time. Neither CI job blocks `deploy-production`.
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
