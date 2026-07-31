# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 — rev 3 planning recreated + committed immediately
               (a prior rev-3 attempt was lost: it sat uncommitted, then a
               full repo reset to origin/main wiped it along with the rev-2
               RN scaffold). This time the docs are committed before any
               further work happens.
Android state: does not exist (apps/android not created)
iOS state:     does not exist (apps/ios not created)
Vectors:       not exported yet (tools/golden-vectors not created)
apps/mobile:   does not exist (rev-2 RN scaffold never made it into a commit;
               a git reset to origin/main removed it from disk 2026-07-31)
Next up:       P0.1 (vector exporter, tools/golden-vectors/export.ts) — plan §4.
Traps/notes:   Sandbox has node/npm only — no pnpm (lockfile not
               regenerable; dependency changes need a human `pnpm install`),
               no JDK compiler/Gradle, no Xcode. P0.2/P0.3 (native skeletons)
               can be scaffolded here but NOT verified here — their
               Done-when needs a real machine or CI. COMMIT EVERY SESSION,
               even docs-only ones — this file exists twice now because the
               last attempt didn't.
Blocked:       nothing
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
| P0.1 | Golden-vector exporter (`tools/golden-vectors/export.ts`) | [M] | — | TODO |
| P0.2 | Android skeleton (`apps/android`, pure-Kotlin `:domain`) | [M] | — | TODO |
| P0.3 | iOS skeleton (`apps/ios`, SwiftPM `Domain`, App Group) | [M] | — | TODO |
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
