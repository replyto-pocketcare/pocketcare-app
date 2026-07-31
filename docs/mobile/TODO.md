# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — continuing P2.5 into finance+budget
               ("keep going"), discovered mid-session that a REAL,
               authoritative repository layer already exists at
               packages/data/src/powersync-repositories.ts and is what
               apps/web/src/powersync.ts's getRepositories() actually
               wires up for every domain write. Reconciled
               LedgerRepository.kt/.swift against it (OverdraftError/
               assertNoOverdraft, setOpeningBalance, transaction items,
               labels, transaction_audit trail, fixed createAccount's
               column list/allow_negative default), then built
               BudgetRepository.kt/.swift + CreditCardRepository.kt/.swift
               on top. User then ran the FIRST REAL COMPILER PASS this
               whole arc against P2.5 code, on both platforms, and both
               failed on the first try — then GREEN after one real fix
               each (below). This is the arc's first hard evidence that
               the source-verification-without-a-compiler methodology
               produces mostly-correct-but-not-perfect code: 2 real bugs
               in ~1500 lines of new/changed P2.5 code, both fixed same
               session once the user supplied the actual diagnostics.
Real bugs found by the first real compiler run (both fixed, both
               committed): (1) Android `:data:compileDebugKotlin` FAILED —
               BudgetRepository.kt:96/100 `params += catIds` where
               params: MutableList<Any?>, catIds: List<String>. Because
               List<out E> is covariant, List<String> conforms to Any?,
               so plusAssign(element: Any?) (add the whole list as ONE
               entry) and plusAssign(elements: Iterable<Any?>) (spread
               it) are BOTH statically applicable — the compiler resolved
               the ambiguity by falling back to the non-mutating `plus`
               operator and tried to reassign the `val`, which fails
               outright ("'val' cannot be reassigned"). Fixed to
               `.addAll()`, which has no such ambiguity. Grepped the rest
               of this session's Kotlin for the same `+= <list>` pattern —
               nowhere else does it, so this was the complete Kotlin
               fix. (2) iOS `xcodebuild` FAILED — Swift 6's strict
               concurrency checker rejected LedgerRepository.swift's
               updateTransaction for "Reference/Mutation of captured var
               'changeLog'/'sets'/'params' in concurrently-executing
               code": a writeTransaction closure (which may run in a
               different isolation context) can't capture and read/mutate
               an outer `var`, only `let` captures of Sendable values are
               safe across that boundary. Fixed by hoisting all the
               decision-making (items/labels audit-summary entries, final
               UPDATE sets/params) to immutable `let`s computed BEFORE the
               closure opens — pure logic based on already-known state, so
               moving it changes nothing about correctness/atomicity.
               createTransaction/removeTransaction's writeTransaction
               closures were already clean (checked, no capture issue).
Real API findings this session (source-verified via docs.powersync.com's
               live Kotlin/Swift SDK reference pages, not guessed): both
               SDKs expose get/getOptional/getAll/execute/writeTransaction
               with near-identical call shapes; get() throws if no row,
               getOptional() returns null/nil.
Android state: 16/16 Phase 1 domains DONE. :data module (P2.2a/P2.3a/
               P2.4a) STILL NEVER build-verified this whole arc (only
               P2.5's new files have been). P2.5a: 3/7 domains (ledger
               reconciled, budget, credit-card) — `./gradlew` BUILD
               SUCCESSFUL, human-confirmed 2026-07-31; finance/splits/
               receipts/upi remain.
iOS state:     16/16 Phase 1 domains DONE. Data package (P2.2b/P2.3b/
               P2.4b): xcodebuild confirmed green through round 3 + P2.3
               diagnostics wiring, NOT yet re-verified since (only P2.5's
               new files have been, this session). P2.5b: 3/7 domains
               (ledger reconciled, budget, credit-card) — `xcodebuild`
               green, human-confirmed 2026-07-31.
Vectors:       DONE (P0.1), 250/250 green on both platforms (Phase 1).
Next up:       Continue P2.5: splits, receipts, upi remain (finance's
               pure calculators, e.g. EMI/amortization, don't need their
               own repository — Finance.kt/.swift's
               functions take explicit inputs, not DB reads, except the
               EMI due-date helpers which imply a `loans` table a future
               LoanRepository would read — not yet scoped). P2.6 (repair
               logic) still fully untouched.
Traps/notes:   Same traps from rounds 1-3, plus: always check whether a
               "spec" file you're reverse-engineering from (hooks.ts) is
               actually the canonical one before porting from it — grep
               for `getRepositories()`/`@pocketcare/data` usage in
               apps/web/src before trusting a hooks.ts-only read for any
               new domain going forward (splits/receipts/upi included).
Blocked:       P2.2/P2.3/P2.4/P2.5 all still BLOCKED on TP L3 (real sync
               round-trip against reachable Supabase infra) even once a
               piece compiles clean. Android additionally blocked on ever
               getting a first real Gradle build this entire arc.
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
| P2.2a / P2.2b | PowerSync connector port — op-coalescing upload queue matching `packages/db`'s fault-injection semantics (retry classification via the now-ported `sync-policy` domain, exponential backoff via `backoffMs`) | [M] | P2.1 | Code complete, NOT build-verified (no real Gradle run this whole arc) — BLOCKED (TP L3) / Code complete, xcodebuild clean 3 rounds in a row (human-confirmed 2026-07-31, incl. a real data-correctness fix, see change log) — BLOCKED (TP L3) |
| P2.3a / P2.3b | Quarantine / dead-letter queue — wires `shouldQuarantine`/`MAX_PERMANENT_ATTEMPTS` (already-ported `sync-policy` domain) into the connector's actual retry loop, plus local persistence for quarantined ops so they're inspectable (diagnostics `formatLog`/`makeEntry`, already ported, log them) | [M] | P2.2 | Code complete 2026-07-31 (dead-letter persistence + new DiagnosticsLog.kt wiring `makeEntry`/`formatLog` into the failure path), NOT build-verified — BLOCKED (TP L3) / Code complete 2026-07-31 (dead-letter persistence was already done; new DiagnosticsLog.swift closes the `makeEntry`/`formatLog` gap that was the actual remaining piece), NOT yet re-verified by xcodebuild since this addition — BLOCKED (TP L3) |
| P2.4a / P2.4b | Auth — guest/OTP/Google sign-in, in-place guest→registered upgrade, offline marker so the UI can tell "signed out" from "signed in but offline" | [M] | P2.1 | Code complete, NOT build-verified — BLOCKED (TP L3) / Code complete, Auth.swift confirmed xcodebuild-clean (2026-07-31) — BLOCKED (TP L3) |
| P2.5a / P2.5b | Repositories — read/write facades over the local PowerSync SQLite DB for each domain (money/ledger/finance/budget/splits/receipts/upi), calling the already-ported pure domain functions for any derived value (balances, progress, etc.) rather than recomputing ad hoc | [M] | P2.1, P2.2 | DOING (3/7 — ledger + budget + credit-card done, human-confirmed `./gradlew` BUILD SUCCESSFUL 2026-07-31 after 1 real fix — `params += list` covariance ambiguity, see change log; splits/receipts/upi remain) / DOING (3/7 — same three, human-confirmed `xcodebuild` green 2026-07-31 after 1 real fix — Swift 6 strict-concurrency var capture in writeTransaction, see change log; same remaining list) |
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
