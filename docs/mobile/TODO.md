# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 — P0.2 + P0.3 SCAFFOLDED (files written, NOT
               verified — see Blocked). P0.1/plan docs done earlier same
               session (commits 62fd053, 136d1e2).
Android state: apps/android/{app,domain} written. NOT yet built — no
               Gradle/JDK compiler in the agent sandbox. Wrapper jar not
               committed either (can't fabricate a binary) — see
               apps/android/README.md for the one-command bootstrap
               (`gradle wrapper --gradle-version 8.6`) a human must run once.
iOS state:     apps/ios/{App,AppTests,Domain} + project.yml written. NOT
               yet generated or built — no Xcode/Swift toolchain in the
               agent sandbox. `.xcodeproj` is generated (gitignored), not
               committed — run `xcodegen generate` first (README.md).
Vectors:       DONE (P0.1). tools/golden-vectors -> vectors/*.json, 16
               domain files, 250 vectors, >=1 per public function.
Next up:       A HUMAN needs to run the verification commands below and
               report the output back — only then can P0.2/P0.3 move
               DOING -> DONE per protocol (Done-when needs real
               build/test output, not "the files exist"):
                 Android: cd apps/android && gradle wrapper --gradle-version 8.6
                          && git add gradlew* gradle/wrapper/ && ./gradlew build test
                 iOS:     cd apps/ios && xcodegen generate
                          && swift test --package-path Domain
                          && xcodebuild test -project PocketCare.xcodeproj
                             -scheme PocketCare
                             -destination 'platform=iOS Simulator,name=iPhone 16'
               If either fails, paste the error back rather than silently
               patching around it blind — these were never compiled.
Traps/notes:   CI jobs `android`/`ios` added to .github/workflows/ci.yml.
               Android CI uses gradle/actions/setup-gradle (runs `gradle`,
               NOT `./gradlew`) specifically so CI doesn't need the
               human-generated wrapper jar — fine either way once one
               exists. iOS CI runs `xcodegen generate` fresh every time
               (project.yml is the source of truth, .xcodeproj is
               gitignored). Neither CI job blocks `deploy-production`
               (same pattern as the old RN `mobile` job). versions in
               apps/android/gradle/libs.versions.toml and
               apps/ios/project.yml's deploymentTarget are proposals typed
               from training knowledge, NOT verified against what's
               actually latest-stable right now — check before trusting
               them long-term (plan §2 says to). Exporter (P0.1) imports
               packages by RELATIVE PATH to each src/index.ts, not the
               "@pocketcare/x" bare specifier — needs no new symlinks.
               Every vector-exporter call that defaults to wall-clock time
               or Math.random pins an explicit date/seed instead.
               COMMIT EVERY SESSION, even docs-only ones.
Blocked:       P0.2/P0.3 DONE status on a human running the build commands
               above and reporting results (sandbox has no JDK
               compiler/Gradle/Xcode/Swift toolchain).
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
