# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (even later) — human ran the REAL Android build for
               the first time and hit a real Kotlin compile error; fixed it
               plus did the overdue dependency-version audit. iOS untouched
               this round (still fully unverified).
Android state: Human's `./gradlew build test` hit "Unclosed comment" in
               domain/Placeholder.kt (Kotlin nests block comments; the KDoc
               had literal /* inside glob paths) — fixed by rephrasing.
               Also bumped AGP 8.6.0->8.13.0, Kotlin 2.0.21->2.4.10, Compose
               BOM 2024.10.01->2026.06.00, Gradle wrapper+CI 8.7->8.13,
               compileSdk/targetSdk 35->36 — verified against
               developer.android.com's AGP/Gradle compat table (not just
               assumed). Deliberately stayed on AGP 8.x, not 9.x's
               built-in-Kotlin (real DSL migration, unverifiable without a
               live build) — see README "Version audit" note. Also fixed
               apps/android/.gitignore: `/build` was anchored so it missed
               apps/android/domain/build/; now unanchored `build/`.
               STILL NOT build-green — human needs to re-run and report.
iOS state:     Unchanged since last session. apps/ios/{App,AppTests,Domain}
               + project.yml written, NEVER generated or built. Not part of
               this fix round.
Vectors:       DONE (P0.1). tools/golden-vectors -> vectors/*.json, 16
               domain files, 250 vectors, >=1 per public function.
Next up:       Human re-runs `./gradlew build test` in apps/android and
               reports the result — could still surface more real errors
               the sandbox can't catch (no JDK/Gradle here). Once green,
               P0.2 -> DONE. iOS (P0.3) still needs its first real
               `xcodegen generate && swift test && xcodebuild test` pass,
               and its own version audit (swift-tools-version 6.0,
               deploymentTarget iOS 17 in project.yml) hasn't been done yet
               — do that BEFORE the first iOS build attempt, not after,
               now that Android proved the "ship unverified versions, fix
               reactively" path costs a round trip.
Traps/notes:   New trap for the list: **Kotlin block comments nest** —
               never write a literal `/*` inside a `/** ... */` doc comment
               (glob paths like `foo/*.json` are a classic accidental
               trigger); rephrase to avoid it. CI jobs `android`/`ios` in
               .github/workflows/ci.yml (gradle-version now "8.13"). Android
               CI uses gradle/actions/setup-gradle (runs `gradle`, NOT
               `./gradlew`) so it doesn't need the human-generated wrapper
               jar. iOS CI runs `xcodegen generate` fresh every time
               (project.yml is the source of truth, .xcodeproj is
               gitignored). Neither CI job blocks `deploy-production`.
               Exporter (P0.1) imports packages by RELATIVE PATH to each
               src/index.ts, not the "@pocketcare/x" bare specifier.
               COMMIT EVERY SESSION, even docs-only ones.
Blocked:       P0.2 DONE status on the human's next build attempt actually
               going green. P0.3 blocked on ever attempting a first build
               (sandbox has no JDK/Gradle/Xcode/Swift toolchain).
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
| P0.2 | Android skeleton (`apps/android`, pure-Kotlin `:domain`) | [M] | — | DOING (2026-07-31, claude-sonnet-5) |
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
