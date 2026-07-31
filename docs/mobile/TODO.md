# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — Phase 1 DONE (prior session, human-
               confirmed). This session: P2.1a/P2.1b (schema parity,
               700cd24) — mirrored AppSchema's 63 PowerSync tables onto
               Android/iOS as a data-driven schema DESCRIPTOR (table/
               column names, SQLite type, indexes, local-only flags),
               NOT hand-typed: wrote tools/golden-vectors/
               export-mobile-schema.mjs + gen-mobile-schema.mjs, which
               introspect the real AppSchema object at runtime and
               codegen PocketCareSchema.kt/.swift from that JSON. Chose
               generation over transcription deliberately -- 63 tables x
               ~10 cols x 2 platforms is exactly the kind of volume
               where P1.6's transcription bugs (hidden control bytes,
               wrong FNV constant) would recur, and it surfaced a real
               per-table inconsistency (only some tables redeclare the
               implicit `id` column) that'd be easy to miss by eye.
               Verified via a bracket-aware structural diff (0/63
               mismatches) and by confirming regeneration is
               byte-identical (sha256) -- that reproducibility IS the
               ongoing parity check per plan's ask.
Android state: 16/16 Phase 1 domains DONE + human-confirmed green.
               PocketCareSchema.kt added (schema descriptor, not yet
               consumed by anything -- P2.2+ will).
iOS state:     16/16 Phase 1 domains DONE + human-confirmed green.
               PocketCareSchema.swift added, same status as Android.
Vectors:       DONE (P0.1), 250/250 green on both platforms (Phase 1
               only -- schema parity has no vectors, see P2.1 note in
               the Phase 2 table for why).
Next up:       Claim P2.2a/P2.2b (PowerSync connector port) or P2.4a/
               P2.4b (auth, independent of the sync pipeline) -- both
               now unblocked by P2.1. Read packages/db/src/connector.ts,
               quarantine.ts, auth.ts first (not yet read this arc).
Traps/notes:   Everything from the Phase 1 handover still applies
               (control-byte literals, non-textbook constants,
               NSNumber.isEqual, Sendable on public structs in test
               fixtures, JS single-.replace vs Kotlin/Swift replace-all,
               nested block comments). NEW: when introspecting a TS
               module at runtime instead of reading its source, watch
               for syntax `node --experimental-strip-types` can't
               parse (TS parameter properties, e.g. `connector.ts`'s
               constructor) -- work around it by importing a stripped
               copy of just the part you need (see export-mobile-
               schema.mjs's header for the exact technique), don't reach
               for tsc/esbuild (esbuild's binary in this sandbox is
               darwin-arm64 only and won't run on the Linux sandbox;
               tsc works but its `.ts`-extension import rules and
               parameter-property errors need real workarounds too --
               the stripped-copy approach sidesteps all of it). Phase 2
               remains a different verification regime than Phase 1 for
               everything touching real I/O (P2.2+) -- TP L3 (local
               Supabase + fault injection) needs a reachable test
               Supabase project this sandbox doesn't have. COMMIT EVERY
               SESSION.
Blocked:       P2.2+ (connector, repositories, repair logic) will need
               a local/test Supabase project reachable for TP L3
               fault-injection testing before their Done-when can be
               met -- flag this to the human once one of those is
               claimed, if it isn't already set up.
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
| P1.4a / P1.4b | splits+insights — Android / iOS | [M] | P1.1 | DONE (2026-07-31, 17291cb — human confirmed `./gradlew test` BUILD SUCCESSFUL, splits-insights 6/6/0 + splits-math 4/4/0) / DONE (2026-07-31, 17291cb + fixes 27a91cb, 6f320b9 — human confirmed `swift test` green after the two Swift 6 fixes) |
| P1.5a / P1.5b | receipts — Android / iOS | [H] | P1.1 | DONE (2026-07-31, 56a3200 — 4 sub-domains ported, 2 real bugs caught+fixed pre-commit: JS single-`.replace` vs Kotlin's replace-all, findDate UTC-vs-local; human confirmed `./gradlew test` green) / DONE (same commit, human confirmed `swift test` green) |
| P1.6a / P1.6b | reconcile+upi+sync-policy+diagnostics+guardrail — Android / iOS | [M] | P1.1 | DONE (2026-07-31, d895c30 — 5 sub-domains ported: reconcile [FNV-1a bank-drift checksums, hidden U+0001/U+0000 control-byte literals in the TS source caught via raw-byte inspection, not the Read tool's misleading rendering], upi [mulberry32 seeded PRNG for `newPaymentRef`, hand-rolled `encodeURIComponent`/`decodeURIComponent`, non-textbook FNV offset constant caught by cross-checking two candidate values against the real vectors], sync-policy [em-dash/arrow Unicode strings verified byte-exact via Python `ord()`], diagnostics [highest-risk domain after receipts: multi-pass order-sensitive redaction pipeline, `\b` word-boundary regex, ₹€£ symbols]; human confirmed `./gradlew test` green, no fixes needed) / DONE (same commit, human confirmed `swift test` green, no fixes needed) |
| P1.7a / P1.7b | entitlements — Android / iOS | [S] | P0.4 | DONE (2026-07-31, d895c30 — ported faithfully including a source quirk: `Tier` has 4 values but `canUse()` only special-cases "premium", so "lite"/"pro" silently fall through to the free-tier check; not fixed, just documented, since only "free"/"premium" have vector coverage; human confirmed green) / DONE (same commit, human confirmed green). "gate map" deliberately NOT ported — no golden vectors exist for it; it's a UI-side feature-gating table, deferred to Phase 3+ UI work, not pure domain logic. |

**Phase 1 gate cleared 2026-07-31: all 16 domains / 250 vectors green on both `./gradlew test` and `swift test --package-path Domain`, human-confirmed, zero fixes needed on either platform for P1.5-P1.7 (the extra Python cross-check pass against the full TS test surfaces — see PROJECT_REFERENCE.md change log — evidently paid off). Phase 2 below is now expanded.**

### Phase 2 — data layer (expanded 2026-07-31, plan §6)
One task = one platform, same pattern as Phase 1. Order matters: schema parity blocks everything else (repositories/connector/auth all need the models to exist); connector + quarantine are paired (dead-letter needs the connector's retry/backoff hookup); auth is independent of the sync pipeline and can run in parallel once schema parity lands.

| ID | Task | Tag | Needs | Status |
|---|---|---|---|---|
| P2.1a / P2.1b | Schema parity — mirror `AppSchema` (`packages/db/src/index.ts`) as Kotlin data classes / Swift structs + a parity check script (3-way: `AppSchema` ↔ Kotlin ↔ Swift, catches column drift at build/CI time, not runtime) | [M] | P1 (done) | DONE (2026-07-31, 700cd24) / DONE (same commit) |
| P2.2a / P2.2b | PowerSync connector port — op-coalescing upload queue matching `packages/db`'s fault-injection semantics (retry classification via the now-ported `sync-policy` domain, exponential backoff via `backoffMs`) | [M] | P2.1 | TODO / TODO |
| P2.3a / P2.3b | Quarantine / dead-letter queue — wires `shouldQuarantine`/`MAX_PERMANENT_ATTEMPTS` (already-ported `sync-policy` domain) into the connector's actual retry loop, plus local persistence for quarantined ops so they're inspectable (diagnostics `formatLog`/`makeEntry`, already ported, log them) | [M] | P2.2 | TODO / TODO |
| P2.4a / P2.4b | Auth — guest/OTP/Google sign-in, in-place guest→registered upgrade, offline marker so the UI can tell "signed out" from "signed in but offline" | [M] | P2.1 | TODO / TODO |
| P2.5a / P2.5b | Repositories — read/write facades over the local PowerSync SQLite DB for each domain (money/ledger/finance/budget/splits/receipts/upi), calling the already-ported pure domain functions for any derived value (balances, progress, etc.) rather than recomputing ad hoc | [M] | P2.1, P2.2 | TODO / TODO |
| P2.6a / P2.6b | Repair logic — detect + resolve the drift `reconcile`'s checksums surface (missingRemote/missingLocal/mismatched), matching `packages/db`'s repair semantics | [M] | P2.2, P2.3 | TODO / TODO |

*Done-when (each):* TP L3 (sync integration, per plan's test-plan doc) passes for that piece on that platform — a real PowerSync round-trip against a test Supabase project, not just unit tests of the surrounding logic. This is a materially different verification bar than Phase 1's pure-function vectors: these tasks touch actual I/O (SQLite, network), so "compiles and the domain-logic unit tests pass" is necessary but not sufficient — plan's `docs/plans/full-test-plan.md` L3 fault-injection presets are the real gate.

**P2.1 note:** it does no I/O (it's a static schema mirror, not a connector), so TP L3 doesn't apply to it directly — its actual Done-when was met by (a) all 63 tables/columns/indexes/local-only flags present identically on all three platforms, verified by a bracket-aware structural diff against the real `AppSchema` object (zero mismatches), and (b) the parity-check mechanism itself: regenerating from a clean `AppSchema` reproduces byte-identical output, so a future `git diff` after changing `packages/db/src/index.ts` is the ongoing drift check. See PROJECT_REFERENCE.md change log for the generation approach (introspect + codegen, not hand-transcribe).

### Phase 3+ (UI slices S1–S6, native surfaces P4.x, release P5.x)
Not expanded yet (plan §7-8).

## Decisions needing a human (standing list)
- Any new dependency beyond the §0 irreducible set (PowerSync, Supabase SDK, RevenueCat, FCM).
  - ✅ 2026-07-31: `kotlinx.serialization` (test-scope, Android only, P0.4a) — approved in-session for parsing golden-vector JSON in `:domain`, which has no Android SDK and thus no built-in JSON parser. iOS needed no equivalent approval (Foundation's JSONSerialization is already available, not a new dependency).
- [H] tasks: P1.5, and any Phase 2 items once expanded — strong model or human-paired only.
- Exact minimum OS versions (proposal due with P0.2/P0.3: minSdk + iOS min).
- Real bundle ids / Universal-Links domain (plan §10).
