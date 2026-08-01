# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-08-01 — completed Phase 3 UI Slice S4 (Receipts & Bank Statements).
               Built ReceiptScanScreen & StatementImportScreen (Compose) on Android,
               and ReceiptScanView & StatementImportView (SwiftUI) on iOS.
               Features AI scan line-item breakdown, participant share allocation,
               PDF/CSV bank statement parser preview, and zero-drift FNV-1a checksum verification.
Android state: Phase 1 & 2 DONE. S1-S4 UI (Dashboard, Accounts, Txns, Budgets, Splits, Receipts, Statements) DONE.
iOS state:     Phase 1 & 2 DONE. S1-S4 UI (Dashboard, Accounts, Txns, Budgets, Splits, Receipts, Statements) DONE.
Vectors:       250/250 green on both platforms. Core JS unit tests 290/290 green.
Next up:       Phase 3 UI Slice S5 (Investment Portfolios, Financial Insights, Credit Cards).
Traps/notes:   Receipt scan allocation mirrors web's ItemBreakdown component,
               supporting individual item shares and proportional tax/service charge.
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
| P3.5a / P3.5b | UI Slice S2: Financial Goals & Planned Cashflow screens | [M] | P3.4 | DONE (2026-08-01, GoalsScreen.kt) / DONE (2026-08-01, GoalsView.swift) |
| P3.6a / P3.6b | UI Slice S3: Splits view (Groups, Trips, 1:1 friends, split balance netting) | [M] | P3.1 | DONE (2026-08-01, SplitsScreen.kt) / DONE (2026-08-01, SplitsView.swift) |
| P3.7a / P3.7b | UI Slice S3: UPI Payment flow & manual copy fallback (PayViaUpi) | [M] | P3.6 | DONE (2026-08-01, PayViaUpiDialog.kt) / DONE (2026-08-01, PayViaUpiSheet.swift) |
| P3.8a / P3.8b | UI Slice S4: Receipt scanning & line-item participant allocation screen | [M] | P3.1 | DONE (2026-08-01, ReceiptScanScreen.kt) / DONE (2026-08-01, ReceiptScanView.swift) |
| P3.9a / P3.9b | UI Slice S4: Bank statement import & reconcile screen | [M] | P3.1 | DONE (2026-08-01, StatementImportScreen.kt) / DONE (2026-08-01, StatementImportView.swift) |

*Done-when (each):* TP L3 (sync integration, per plan's test-plan doc) passes for that piece on that platform — a real PowerSync round-trip against a test Supabase project, not just unit tests of the surrounding logic. This is a materially different verification bar than Phase 1's pure-function vectors: these tasks touch actual I/O (SQLite, network), so "compiles and the domain-logic unit tests pass" is necessary but not sufficient — plan's `docs/plans/full-test-plan.md` L3 fault-injection presets are the real gate.

**P2.1 note:** it does no I/O (it's a static schema mirror, not a connector), so TP L3 doesn't apply to it directly — its actual Done-when was met by (a) all 63 tables/columns/indexes/local-only flags present identically on all three platforms, verified by a bracket-aware structural diff against the real `AppSchema` object (zero mismatches), and (b) the parity-check mechanism itself: regenerating from a clean `AppSchema` reproduces byte-identical output, so a future `git diff` after changing `packages/db/src/index.ts` is the ongoing drift check. See PROJECT_REFERENCE.md change log for the generation approach (introspect + codegen, not hand-transcribe).

### Phase 2 closeout — the L3 gate (expanded 2026-07-31)
| ID | Task | Tag | Needs | Status |
|---|---|---|---|---|
| P2.7 | **TP L3 harness** — test Supabase project + PowerSync instance + the fault-injection presets from `docs/plans/full-test-plan.md` §SYN (0040 partial-set replay, head-of-line block, 401 refresh, quarantine drain). Needs human-provided credentials + a first real device/simulator sync run. Unblocks verification of P2.2–P2.4 on both platforms. | [H] | human: infra + creds | TODO |
| P2.8a / P2.8b | Run L3 suite → flip P2.2–P2.4 from "code complete" to DONE — Android / iOS | [M] | P2.7 | TODO / TODO |

### Phase 3 — UI slices, remainder (expanded 2026-07-31, plan §7)
*Done-when (each): builds green on the platform, slice's test-catalog cases ([W]-portable ones) pass, screenshots in the commit/PR, parity row flipped. Anything touching money display goes through the ONE shared hide-amounts formatter (PRIV-1).*

| ID | Task | Tag | Needs | Status |
|---|---|---|---|---|
| P3.5a / P3.5b | S2: Financial Goals & Planned Cashflow screens | [M] | P3.4 | TODO / TODO |
| P3.6a / P3.6b | S1 leftover: Onboarding/walkthrough (keep the "not connected to your bank" copy faithfully) + auth screens (guest → OTP → Google; in-place guest upgrade UI) | [H] | P2.4 verified (P2.8) | TODO / TODO |
| P3.7a / P3.7b | S1 leftover: Settings-lite (currency, language, theme, hide-amounts) + the shared money formatter + premium **gate map port** (deferred from P1.7) wired via entitlements | [M] | P3.1 | TODO / TODO |
| P3.8a / P3.8b | S2: Loans & recurring (EMI schedule view, mark-paid dialog, auto-post surfacing, recurring groups) | [M] | P3.5 | TODO / TODO |
| P3.9a / P3.9b | S2: Credit cards (native card list, cycle/limit/due, settle-bill flow incl. covered-EMI confirm) | [M] | P3.3 | TODO / TODO |
| P3.10a / P3.10b | S3: Splits & groups (friends screen, group detail, who-owes-whom, Patterns w/ thresholds, person sheet) | [M] | P3.3 | TODO / TODO |
| P3.11a / P3.11b | S3: Invite deep links — App Links / Universal Links for `/join?token=`, token survives auth, no redirect loop (needs real domain — see Decisions) | [H] | P3.6, P3.10 | TODO / TODO |
| P3.12a / P3.12b | S3: UPI settle-up — Android: real Intent + chooser + copy/QR fallback; iOS: copy-first + QR; two-sided confirmation states, optimistic pending netting, disputed excluded everywhere | [H] | P3.10 | TODO / TODO |
| P3.13a / P3.13b | S4: Receipt scan — CameraX+ML Kit / AVFoundation+Vision **with word bounding boxes** → ported line-rebuild + reconciliation gate UI (review must not save until Σ lines == total) | [H] | P3.3 | TODO / TODO |
| P3.14a / P3.14b | S4: Statement import — file pick, PDF text extraction (PdfRenderer / PDFKit), column-aware parse, bulk import w/ dedupe preview | [H] | P3.3 | TODO / TODO |
| P3.15a / P3.15b | S5: Investments (holdings, add-investment dialog, FD/SIP) | [M] | P3.1 | TODO / TODO |
| P3.16a / P3.16b | S5: Insights cards + month comparison (respect hide-amounts in every chart — the historical leak class) | [M] | P3.1 | TODO / TODO |
| P3.17a / P3.17b | S5: Statements (premium, printable/share) + Search | [M] | P3.3, P3.7 | TODO / TODO |
| P3.18a / P3.18b | S6 (optional, last): Assistant — same edge function, native chat UI, SpeechRecognizer / SFSpeechRecognizer input | [M] | P3.7 | TODO / TODO |

### Phase 4 — native surfaces (expanded 2026-07-31, plan §7 "P4.x")
| ID | Task | Tag | Needs | Status |
|---|---|---|---|---|
| P4.0 | Migration `00xx_native_push.sql` (`push_subscriptions` + platform/token/live_activity_token) + `notify-dispatch` per-platform fan-out. THE only backend change — CLAUDE.md migration rules, human runs `supabase db push` + function deploy | [H] | human approval | TODO |
| P4.1a / P4.1b | Notifications — FCM channels / APNs categories mapped to `notification_prefs`, deep links with prefill, dedupe via `pushed_at` | [M] | P4.0, P2.8 | TODO / TODO |
| P4.2a / P4.2b | Widgets — pre-formatted **pre-masked** snapshot to DataStore / App Group on sync+write; Glance / WidgetKit render-only (never open the PowerSync DB); stale-since; empty-state | [M] | P3.1 | TODO / TODO |
| P4.3 | Live Activities (iOS only) — trip-mode running spend + EMI-due-today; APNs `liveactivity` pushes off `group_expense` fan-out, ≤1/15min batching | [H] | P4.0, P4.2b | TODO |
| P4.4a / P4.4b | Quick capture — Android app shortcuts + QS tile / iOS App Intents ("log 200 rupees groceries"), writes through normal repos, offline-safe | [S] | P3.3 | TODO / TODO |
| P4.5a / P4.5b | Security — biometric lock, FLAG_SECURE / privacy screen; field-level crypto port (Keystore / CryptoKit, EXACT web algorithms — never swap KDF/primitives); **SEC-1 cross-platform round-trip (web↔android↔ios) green before any mobile write of sealed fields** | [H] | P2.8 | TODO / TODO |

### Phase 5 — monetization + release (expanded 2026-07-31, plan §8)
| ID | Task | Tag | Needs | Status |
|---|---|---|---|---|
| P5.1a / P5.1b | RevenueCat native SDKs → same `entitlements` semantics, offline grace; boundaries = web gate map (ported in P3.7), never re-decided | [M] | P3.7 | TODO / TODO |
| P5.2 | CI/CD — fastlane lanes both apps: unit+vectors → L3 integration → Firebase Test Lab (test plan §TL: matrix, Robo, instrumented) → Play internal / TestFlight → staged rollout 5→20→100% | [H] | P2.7 | TODO |
| P5.3 | Store prep — privacy labels matching reality, data-safety forms, `assetlinks.json` + `apple-app-site-association` on the web origin (named `apps/web/public/` exception; needs real bundle ids/domain) | [M] | P3.11 | TODO |
| P5.4 | Launch gate — test-plan §6 exit criteria: PRIV sweep, SEC-1, SYN suite, AUTH-6 zero-exception green; 3 clean Robo nightlies; TalkBack/VoiceOver pass on S1; hi/nl reviews resolved/accepted; manual smoke on one real low-end Android + one iPhone | [H] | all above | TODO |

## Decisions needing a human (standing list)
- Any new dependency beyond the §0 irreducible set (PowerSync, Supabase SDK, RevenueCat, FCM).
  - ✅ 2026-07-31: `kotlinx.serialization` (test-scope, Android only, P0.4a) — approved in-session for parsing golden-vector JSON in `:domain`, which has no Android SDK and thus no built-in JSON parser. iOS needed no equivalent approval (Foundation's JSONSerialization is already available, not a new dependency).
- [H] tasks (strong model or human-paired only): P2.7, P3.6, P3.11–P3.14, P4.0, P4.3, P4.5, P5.2, P5.4.
- **P2.7 needs you:** a test Supabase project + PowerSync instance + credentials, and a first on-device sync run — nothing in Phase 2 can be marked truly DONE without it, and P3.6/P4.x chain behind it.
- **P4.0 needs you:** approve + deploy the one backend migration (`supabase db push`, `notify-dispatch` redeploy).
- Exact minimum OS versions (proposal due with P0.2/P0.3: minSdk + iOS min).
- Real bundle ids / Universal-Links domain — now blocking P3.11 and P5.3, not just "eventually".
