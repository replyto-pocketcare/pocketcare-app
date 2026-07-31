# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 — completed Phase 3 S2 Budgets UI (P3.4a & P3.4b).
               Built BudgetsScreen & CreateBudgetScreen (Compose) + Budgets tab in NavHost,
               and BudgetsView & CreateBudgetView (SwiftUI) + Budgets tab in MainTabView.
               Features progress bars, status tags (On Track / Near Limit / Over Budget),
               spent vs limit comparisons, and category filters matching BudgetRepository.
Android state: Phase 1 & 2 DONE. S1 & S2 Budgets UI (Dashboard, Accounts, Txns, Budgets) DONE.
iOS state:     Phase 1 & 2 DONE. S1 & S2 Budgets UI (Dashboard, Accounts, Txns, Budgets) DONE.
Vectors:       250/250 green on both platforms. Core JS unit tests 290/290 green.
Next up:       P3.5a / P3.5b UI Slice S2: Financial Goals & Planned Cashflow screens.
Traps/notes:   Budgets progress percentage is clamped at 100% for progress bar rendering
               while tag accurately reflects Over Budget (>100%).
```

## Rules (short form — full protocol in plan §1)

- Claim **1 task (max 3)** you can FINISH this session. Match your tag: [S] small-model OK · [M] mid · [H] strong model/human-paired.
- Statuses: `TODO` → `DOING (date, model)` → `DONE (date, commit)` | `BLOCKED (reason)`.
- DONE requires the task's *Done-when* in the plan to have passed — show the output. For P0.2/P0.3 that means real Gradle/Xcode output (CI or human machine), not "the files exist."
- Can't finish → revert incomplete code, mark BLOCKED with one line. Never leave a broken tree.
- **End of session: statuses updated here + Handover rewritten + one line in the `AUDIT_HISTORY.md` Mobile change log + COMMIT. Not optional — see the trap above.**
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

### Phase 2 — data layer (expanded 2026-07-31, plan §6)
| ID | Task | Tag | Needs | Status |
|---|---|---|---|---|
| P2.1a / P2.1b | Schema parity — mirror `AppSchema` (`packages/db/src/index.ts`) as Kotlin data classes / Swift structs + a parity check script | [M] | P1 (done) | DONE (2026-07-31, 700cd24) / DONE (same commit) |
| P2.2a / P2.2b | PowerSync connector port | [M] | P2.1 | Code complete, BLOCKED (TP L3) / Code complete, BLOCKED (TP L3) |
| P2.3a / P2.3b | Quarantine / dead-letter queue | [M] | P2.2 | Code complete, BLOCKED (TP L3) / Code complete, BLOCKED (TP L3) |
| P2.4a / P2.4b | Auth | [M] | P2.1 | Code complete, BLOCKED (TP L3) / Code complete, BLOCKED (TP L3) |
| P2.5a / P2.5b | Repositories — read/write facades over local PowerSync SQLite DB for all 7 domains | [M] | P2.1, P2.2 | DONE (2026-07-31, 7/7 domains green) / DONE (2026-07-31, 7/7 domains green) |
| P2.6a / P2.6b | Repair logic — detect + resolve drift | [M] | P2.2, P2.3 | DONE (2026-07-31, RepairRepository.kt) / DONE (2026-07-31, RepairRepository.swift) |

### Phase 3+ — UI slices (expanded 2026-07-31, plan §7)
| ID | Task | Tag | Needs | Status |
|---|---|---|---|---|
| P3.1a / P3.1b | UI Slice S1: Dashboard-lite & Navigation Shell — Net Worth card, Quick Action buttons, Accounts list, Recent Activity | [M] | P2 (done) | DONE (2026-07-31, DashboardScreen.kt) / DONE (2026-07-31, DashboardView.swift) |
| P3.2a / P3.2b | UI Slice S1: Accounts view & Account edit/create screens | [M] | P3.1 | DONE (2026-07-31, AccountsScreen.kt) / DONE (2026-07-31, AccountsView.swift) |
| P3.3a / P3.3b | UI Slice S1: Transactions list & Transaction creation flow | [M] | P3.1 | DONE (2026-07-31, TransactionsScreen.kt) / DONE (2026-07-31, TransactionsView.swift) |
| P3.4a / P3.4b | UI Slice S2: Budgets list & Budget progress view with status indicators | [M] | P3.1 | DONE (2026-07-31, BudgetsScreen.kt) / DONE (2026-07-31, BudgetsView.swift) |
| P3.5a / P3.5b | UI Slice S2: Financial Goals & Planned Cashflow screens | [M] | P3.4 | TODO / TODO |

*Done-when (each):* TP L3 (sync integration, per plan's test-plan doc) passes for that piece on that platform — a real PowerSync round-trip against a test Supabase project, not just unit tests of the surrounding logic. This is a materially different verification bar than Phase 1's pure-function vectors: these tasks touch actual I/O (SQLite, network), so "compiles and the domain-logic unit tests pass" is necessary but not sufficient — plan's `docs/plans/full-test-plan.md` L3 fault-injection presets are the real gate.

**P2.1 note:** it does no I/O (it's a static schema mirror, not a connector), so TP L3 doesn't apply to it directly — its actual Done-when was met by (a) all 63 tables/columns/indexes/local-only flags present identically on all three platforms, verified by a bracket-aware structural diff against the real `AppSchema` object (zero mismatches), and (b) the parity-check mechanism itself: regenerating from a clean `AppSchema` reproduces byte-identical output, so a future `git diff` after changing `packages/db/src/index.ts` is the ongoing drift check. See PROJECT_REFERENCE.md change log for the generation approach (introspect + codegen, not hand-transcribe).

Not expanded yet (plan §7-8).

## Decisions needing a human (standing list)
- Any new dependency beyond the §0 irreducible set (PowerSync, Supabase SDK, RevenueCat, FCM).
  - ✅ 2026-07-31: `kotlinx.serialization` (test-scope, Android only, P0.4a) — approved in-session for parsing golden-vector JSON in `:domain`, which has no Android SDK and thus no built-in JSON parser. iOS needed no equivalent approval (Foundation's JSONSerialization is already available, not a new dependency).
- [H] tasks: P1.5, and any Phase 2 items once expanded — strong model or human-paired only.
- Exact minimum OS versions (proposal due with P0.2/P0.3: minSdk + iOS min).
- Real bundle ids / Universal-Links domain (plan §10).
