# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — verified another agent's P2.2/P2.4
               implementation (commit 4633c6f + uncommitted working-tree
               fixes) against the REAL pinned SDK sources, since this
               sandbox has no javac/swiftc (JRE-only, no JDK; no swift;
               network allowlist blocks toolchain installs) — couldn't
               run a real compiler either. Instead fetched supabase-kt's
               actual Postgrest.kt, supabase-swift's actual
               SupabaseClient.swift/Types.swift/AuthClient.swift, and
               PowerSync's own official Kotlin Supabase connector
               example, all at pinned versions (Data/Package.resolved
               confirms 1.15.1/2.54.1 for iOS; libs.versions.toml for
               Android), and diffed our code against real signatures.
               iOS: no bugs found, high confidence (Package.resolved
               proves `swift package resolve` already ran for real on
               someone's machine). Android: found + fixed 2 real bugs
               that compile fine but are functionally wrong: (1)
               `client.postgrest[op.table]` silently drops schema-
               qualification (confirmed via source: the 1-arg subscript
               uses Postgrest.Config.defaultSchema, "public" unless
               configured — nothing configures it — a direct violation
               of CLAUDE.md golden rule #3; fixed to the real 2-arg
               `[schema, table]` overload). (2) `OtpType.Email
               .MAGIC_LINK` should be `.EMAIL` (confirmed via Supabase's
               own Kotlin docs example; also now matches iOS's `.email`
               case). Also normalized `batch.complete("")` to
               `batch.complete(null)` matching PowerSync's own official
               connector's `transaction.complete(null)`.
Android state: 16/16 Phase 1 domains DONE. :data module (P2.2a/P2.4a)
               reviewed + 2 bugs fixed (see above), NOT build-verified.
iOS state:     16/16 Phase 1 domains DONE. Data package (P2.2b/P2.4b)
               reviewed against real pinned SDK source, no bugs found,
               NOT build-verified (no swift toolchain in this sandbox).
Vectors:       DONE (P0.1), 250/250 green on both platforms (Phase 1).
Next up:       Human ran a REAL `xcodebuild test` and got real compiler
               output for Quarantine.swift (3 distinct error classes,
               fixed same session — see below); Auth.swift and
               SupabaseConnector.swift compiled clean, no changes
               needed. Re-run the real build to confirm these fixes
               land, then do the same for Android (`./gradlew build`,
               still never actually run against this code).
Traps/notes:   Same traps from Phase 1, plus, from this session's REAL
               xcodebuild output (not source-inspection guesses):
               (1) PowerSync Swift's `SqlCursor` has NO `getLong` at
               all (that's a Kotlin-ism) — the Int64 accessors are
               `getInt64(index:)`/`getInt64Optional(index:)`, confirmed
               against the SDK's DocC JSON index. (2) `Queries.execute`/
               `getOptional`'s real parameter type is `[Sendable?]?`,
               NOT `[Any]` — `Any` does not conform to `Sendable`, so
               `code as Any` in a parameters array is a real compile
               error; just pass the value directly (or `as Sendable?`
               for a non-literal like `.map { $0 as Sendable? }`) and
               let the contextual array-literal type do the coercion.
               (3) our own `shouldQuarantine(_:_:)` (SyncPolicy.swift)
               takes an unlabeled second `Int` param — calling it as
               `shouldQuarantine(classification, attempts: attempts)`
               is an "extraneous argument label" error; a same-session,
               source-inspection-only fix (before any real compiler
               output existed) had already caught and fixed this one
               correctly by matching our own Domain source, which is
               the reminder that OUR OWN previously-ported code is
               exactly as fetchable/checkable as a third-party SDK.
               Broader lesson: source-code inspection (fetching the
               real pinned SDK and reading it) caught real Kotlin bugs
               correctly last session, but still isn't equivalent to a
               real compiler — it can't see Swift-specific quirks like
               Any-vs-Sendable existential coercion rules, which only
               showed up once xcodebuild actually ran. Keep doing the
               source-inspection pass when no compiler is available,
               but don't treat it as equivalent to DONE.
Blocked:       P2.2a/b and P2.4a/b still BLOCKED pending a real,
               clean-of-errors Gradle/Xcode build (Android untested by
               any real compiler so far — Kotlin fixes from last
               session are source-inspection-verified only) and, beyond
               that, TP L3 execution against reachable Supabase infra.
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
| P2.2a / P2.2b | PowerSync connector port — op-coalescing upload queue matching `packages/db`'s fault-injection semantics (retry classification via the now-ported `sync-policy` domain, exponential backoff via `backoffMs`) | [M] | P2.1 | BLOCKED (needs L3 test infrastructure) / BLOCKED (needs L3 test infrastructure) |
| P2.3a / P2.3b | Quarantine / dead-letter queue — wires `shouldQuarantine`/`MAX_PERMANENT_ATTEMPTS` (already-ported `sync-policy` domain) into the connector's actual retry loop, plus local persistence for quarantined ops so they're inspectable (diagnostics `formatLog`/`makeEntry`, already ported, log them) | [M] | P2.2 | TODO / TODO |
| P2.4a / P2.4b | Auth — guest/OTP/Google sign-in, in-place guest→registered upgrade, offline marker so the UI can tell "signed out" from "signed in but offline" | [M] | P2.1 | BLOCKED (needs L3 test infrastructure) / BLOCKED (needs L3 test infrastructure) |
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
