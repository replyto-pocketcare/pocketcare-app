# Plan — Full test suite + Firebase Test Lab

> **Status:** PLANNED (2026-07-30). Companion to `docs/plans/native-mobile-apps.md` (referenced as "mobile plan").
> **Executor:** written for smaller LLM agents. Protocol: pick ONE unchecked case ID, implement the test at the layer stated, run it, check it off with the commit hash. Never mark a case done because "the code looks right" — only a green run counts. Never weaken an assertion to make a test pass; if the app is wrong, file it in `PROJECT_REFERENCE.md` change log and stop.

## 1. Layers (where a test lives)

| ID | Layer | Tooling | Runs |
|---|---|---|---|
| L0 | TS core unit (exists — the spec, shared by web AND mobile) | `node:test`, `pnpm test:core` (~300 tests) | every CI |
| L1 | **Hermes spec run** — the same L0 suite executed under RN's JS engine (catches `Intl`/engine differences; the RN replacement for rev-1's golden vectors) | Hermes CLI / RN test harness (mobile plan P0.2) | every CI |
| L2 | Mobile-only unit (write helpers, snapshot builder, deep-link parsing, notification mapping) | Jest + React Native Testing Library | every CI |
| L3 | Sync/data integration | local Supabase (`supabase start`) + `@powersync/react-native` + **fault injection** presets | every CI, headless |
| L4 | UI component/screen | React Native Testing Library (mobile); React Testing Library (web, targeted) | every CI |
| L5 | **Device E2E** | **Maestro** flows on CI emulators/simulators (primary scripted E2E) + **Firebase Test Lab**: Robo crawls + a thin native Espresso/XCUITest smoke suite on the real-device matrix for hardware-bound cases (camera, notifications, widgets, UPI intents, biometrics) | nightly + release |
| L6 | Web E2E | Playwright vs local Supabase | nightly + release |

Rules of placement: money/date/allocation logic → L0 only, shared code (never assert amounts in E2E — E2E asserts flows; never duplicate a money test in Jest — add it to `pnpm test:core` where web and mobile both inherit it). Sync semantics → L3. Scripted user journeys → Maestro (L5, emulators). Anything needing real hardware (camera OCR, UPI intent hand-off, notifications, widgets, biometrics, low-RAM perf) → the Test Lab part of L5.

## 2. Test ID scheme

`<FEATURE>-<n>` below. Every automated test names its case ID in the test name. The parity table in `PROJECT_REFERENCE.md` links feature → case range → layer. A case marked **[E]** is an edge case; **[TL]** requires a physical/virtual device (Test Lab); **[W]** web-applicable too.

## 3. Case catalog

### ACC — Accounts
- ACC-1 [W] Create each account type (savings/current/credit_card/cash/mutual_funds/stocks); type-appropriate payment methods offered (from `account_type_payment_methods`, not hardcoded).
- ACC-2 [W] Opening balance creates an `opening_balance` ledger entry; editing initial balance creates an `adjustment` entry, never mutates. (L3)
- ACC-3 [W] Archive account: hidden from pickers, history retained, net-worth toggle respected.
- ACC-4 [E][W] Account in JPY (0-decimal currency) and BHD (3-decimal): minor-unit math and display correct end-to-end. (L0/L1 + display L4)
- ACC-5 [E][W] `allow_negative` off → overdraft guard blocks; on → negative balance allowed; bulk statement import skips the guard by design. (L3)
- ACC-6 [E][W] Delete/soft-delete account with existing transactions: rows survive with `deleted_at`, balances of other accounts unaffected.

### TXN — Transactions + breakdown
- TXN-1 [W] Income/expense/transfer create → correct ledger postings, atomic with items. (L3)
- TXN-2 [W] Breakdown items must sum to total; client blocks save otherwise (server has NO such constraint — by design, see CLAUDE.md; audit fn `audit_expense_item_sums` is the observability path). (L2/L3)
- TXN-3 [E][W] Item sum off by 1 minor unit → blocked; exactly equal → passes. Largest-remainder allocation of ₹100.00 across 3 = 3334+3333+3333, order-stable. (L1)
- TXN-4 [W] Edit transaction → compensating/updated postings keep derived balance correct; audit/edit-history fields recorded.
- TXN-5 [E][W] Transfer between same-currency accounts vs **cross-currency** (captures `fx_rate` + `to_amount`; neither side converted in place). (L1/L3)
- TXN-6 [E][W] Labels: find-or-create by name → junction rows; renaming a label reflects everywhere; no `label` text column reads anywhere. (L3)
- TXN-7 [E][W] Zero-amount and max-plausible (₹99,99,99,999.99) amounts; negative input rejected at UI. (L2/L4)
- TXN-8 [E][W] Date on month/FY boundary + device timezone ≠ IST: lands in correct budget period and statement month. (L1 period math; L5 device-tz run) [TL]
- TXN-9 [TL] Quick capture: Android shortcut/QS tile and iOS App Intent create a valid expense **offline**.

### CUR — Multi-currency / FX
- CUR-1 [W] Net worth aggregates via `exchange_rates` at as-of date; historical view uses historical rate. (L0/L3)
- CUR-2 [E][W] Missing FX rate for a currency/date → defined fallback behavior, never a crash or silent 1:1. (L2)
- CUR-3 [E][W] `base_currency` change re-renders aggregates only; stored rows untouched. (L3)

### BUD — Budgets
- BUD-1 [W] Category-scope and label-scope budgets (via junctions) count the right transactions and only those. (L3)
- BUD-2 [W] Period bounds: weekly/monthly/custom-range; **credit-card cycle** budget follows statement cycle not calendar month. (L0/L1)
- BUD-3 [E][W] Threshold notifications at 80/100% fire once (dedupe key), not per sync. (L3)
- BUD-4 [E][W] Refund (negative expense) inside a budget period reduces spent.

### CC — Credit cards
- CC-1 [W] Cycle/limit/due math; settle-bill flow posts correct transfer. (L0/L3)
- CC-2 [E][W] Purchase after cycle close lands in next statement; due-date display around month ends (31st → Feb). (L1)

### GOL — Goals / emergency fund
- GOL-1 [W] Allocate/block: blocked balance excluded from spendable, shown in net worth ± blocked. (L3)
- GOL-2 [E][W] Over-allocation beyond account balance blocked; funded/locked states transition correctly.

### LON — Loans / EMI / recurring / cashflow
- LON-1 [W] Fixed-rate amortization schedule totals = principal + interest exactly, in minor units (no drift on last EMI). (L0/L1)
- LON-2 [W] Variable-rate month list; EMI auto-calc hint. Mark-paid posts optional expense; auto-mark policy honored. (L3)
- LON-3 [E][W] Recurring auto-post while device offline for N days → catch-up posts exactly once each on reopen (no dupes across two devices — server dedupe). (L3)
- LON-4 [E][W] Subscription billing-cycle on 29/30/31-day months.

### SPL — Splits & groups
- SPL-1 [W] Equal/percent/exact/multi-payer splits: participant shares sum to bill exactly. (L1)
- SPL-2 [W] Covered-portion books as expense (not transfer); repayment inflow; net worth invariant over settle lifecycle. (L3)
- SPL-3 [W] Collapsed single tile in all lists; detail shows total/your share/paid/owed.
- SPL-4 [E][W] Patterns thresholds: <2 groups → no "always" claim; no settlements → `null` speed not 0; section absent on thin ledger. (L0)
- SPL-5 [E][W] Disputed settlements excluded in **all five** query sites (4 hooks + assistant summary). (L3 — one test per site)
- SPL-6 [W] Invite deep link: logged-out → auth → auto-join lands on group; token cleared after first consume (no redirect loop); expired token → friendly error. [TL for Universal/App Link path]
- SPL-7 [E] Member with zero balance appears in Friends directory (settled ≠ hidden).

### UPI — Settle-up
- UPI-1 Intent URL: `am=`/`pa=` unforgeable via note injection; no thousand-grouping; spaces `%20`. (L0/L1 — exists, port)
- UPI-2 [TL] Android: intent opens chooser with real UPI apps; no handler → fallback sheet (copy-first + QR) appears.
- UPI-3 [W] Two-sided confirmation: pending counts optimistically in netting; payee confirm → both legs; dispute → no reversal, debt un-settled. (L3)
- UPI-4 [E] Auto-confirm sweep at 14 days; nudge at 3. (L3, clock-injected)
- UPI-5 [E] Handle disclosure gates: non-member blocked, no-activity blocked, rate-limit 21st call/hr blocked, audit row per disclosure. (L3 vs local Supabase)
- UPI-6 [E] Guest (anonymous) blocked from payment handles by trigger even after… guest→registered upgrade unblocks.

### RCP — Receipts / OCR
- RCP-1 [W] Reconciliation gate: draft saves only when `Σ lines == printed total` exactly; both one-tap fixes work. (L0/L2)
- RCP-2 [E][W] 0.5 kg × unit price (milli-quantities) exact; discount + tip + service charge lines; proportional charge allocation overridable; `proportional` blocked on item lines. (L1)
- RCP-3 [TL] Camera → ML Kit/Vision on the 10 existing receipt fixtures printed and re-photographed: parse produces a reconcilable draft (accuracy floor: total detected on ≥8/10).
- RCP-4 [E][W] Draft survives process kill (persisted to `receipt_scans`); image never persisted (assert `image_path` NULL and no file on disk).
- RCP-5 [W] Per-item split rolls into `expense_participants`; group balance math unchanged (compare vs plain split of same totals). (L3)

### STM — Statement import / analyze
- STM-1 [W] Column-aware PDF parse: ICICI-style separate Dr/Cr columns signed correctly; fallback heuristic when headerless. (L0 — exists; port)
- STM-2 [W] Password-protected PDF prompt; wrong password → retry not crash.
- STM-3 [E][W] 200-row import: one write transaction, batched upload (assert ≤ handful of HTTP calls via fault-injection counter), dedupe/skip-duplicates on re-import of same file. (L3)
- STM-4 [E][W] Auto-categorize job previews count, applies once, leaves unknown merchants uncategorized (never guesses to a wrong category silently).

### INV — Investments
- INV-1 [W] Holdings CRUD; FD maturity + rate math; SIP schedule rows. (L0/L3)
- INV-2 [E][W] Non-investor: dividend/projection insight cards absent (return `[]`), not empty cards.

### NOT — Notifications
- NOT-1 [TL] FCM/APNs token registered → row in `push_subscriptions` with platform; token rotation replaces not duplicates. (L3 + device)
- NOT-2 [TL] Each trigger (EMI due, budget 80/100, low balance, outlier, group invite/expense, settlement confirm) delivers per prefs; pref off → inbox row still per design, no push; dedupe key prevents double push after `pushed_at`.
- NOT-3 [TL] Notification deep links land on the right screen with prefill (settle-record → prefilled txn form) — cold start AND warm.
- NOT-4 [E][TL] Notifications blocked at OS level → in-app inbox still complete; no crash on send.

### WID — Widgets & Live Activities
- WID-1 [TL] Widgets render from snapshot after first sync; correct after adding a transaction; show stale-since when app hasn't synced.
- WID-2 [E][TL] Hide-amounts ON → widgets mask amounts (snapshot is pre-masked — verify no raw amount in App Group/DataStore file).
- WID-3 [E][TL] Widget with zero accounts (fresh install) → setup state, not crash/blank.
- WID-4 [TL] Live Activity trip mode: starts on trip activity, updates on member expense (≤15min batching), ends correctly; EMI LA ends on mark-paid.
- WID-5 [E][TL] LA push token refresh mid-activity; device reboot → widgets still render (snapshot persisted).

### AUTH — Onboarding / auth / guest
- AUTH-1 [W] Walkthrough Part A completes; step-2 mini account form writes via normal repo; Part B optional; trial modal doesn't stack.
- AUTH-2 [W] Guest → registered: same UID, local data kept, no re-key; Google-link keeps chosen username. (L3)
- AUTH-3 [E][W] Token expires while offline → stays logged in (marker), syncs on reconnect; genuine online SIGNED_OUT clears. (L3, clock/network-injected)
- AUTH-4 [E][W] Re-key on different-user login clears prior user's local data completely (privacy). (L3)
- AUTH-5 [W] OTP reset flow; reset touches sign-in password only — encryption passphrase untouched (assert sealed fields still decrypt).
- AUTH-6 [E][W] Account deletion → single cascade; verify zero orphan rows across all FK'd tables incl. junctions, `payment_handle_disclosures`, split memberships (the 0031 class of bug). (L3)

### ENT — Entitlements / freemium
- ENT-1 [W] Each premium feature gated identically to the web gate map; gate works **offline**. (L2/L4)
- ENT-2 [E][W] Expiry mid-session degrades gracefully (no crash, data intact, gate re-locks).
- ENT-3 [TL] RevenueCat purchase/restore sandbox flow → entitlements row updated; refund revokes.

### I18N — i18n / l10n
- I18N-1 [W] en/hi/nl catalogs key-identical (script assert — L2); language switch live-updates without restart.
- I18N-2 [E][W] ICU plurals (hi rules differ), ordinal handling (`{{ord}}` vs `{{n}}`), long German-style strings don't truncate critical numbers. (L4 screenshot)
- I18N-3 [E][TL] Device locale `hi-IN` fresh install: Indian digit grouping (1,00,000), ₹ position, dates.
- I18N-4 [E][W] Persisted ledger descriptions stay English by design — language switch doesn't rewrite data.

### PRIV — Privacy (hide-amounts) — regression-critical: 3 historical leaks
- PRIV-1 [W] With toggle ON, snapshot-test EVERY money surface: dashboard tiles, all charts (HBar, MonthCompare — the two past leaks), statements (past leak), lists, detail pages, widgets (WID-2), notifications (amounts in push payloads must respect it or be design-excepted explicitly). (L4 sweep, one test per surface, enumerated)
- PRIV-2 [E][W] Toggle mid-session propagates everywhere without reload.

### SEC — Security / crypto
- SEC-1 Cross-platform round trip: field encrypted on web decrypts on Android + iOS and every other direction (9 combos). (L3) — **mandatory before any mobile write of sealed fields**
- SEC-2 [E][W] Wrong passphrase → clean failure; recovery code path; losing both = only sealed fields lost (amounts/dates export fine).
- SEC-3 [TL] Biometric app lock: gate on cold/warm start, bypass impossible via task switcher screenshot (FLAG_SECURE / privacy screen).
- SEC-4 [E][W] Diagnostics redaction on real error corpus: amounts/emails/VPAs/tokens stripped; SQLSTATE + UUIDs survive (L0 — exists; port + extend with mobile paths).

### SYN — Sync fault tolerance (the incident suite — fault injection presets)
- SYN-1 [W] Transient failure (offline, 429, 408, 401): backoff + retry forever, queue order preserved; 401 heals via token refresh. (L3)
- SYN-2 [W] Permanent failure: 3 attempts → quarantined to `failed_writes`, queue drains, unrelated writes behind it upload. (L3)
- SYN-3 [E][W] Kill process between quarantine-write and op-delete → op re-quarantined, not lost. (L3)
- SYN-4 [E][W] Partial multi-row action (0040 replay): subset lands, remainder recoverable via repair; repair re-uploads parents-first, is re-runnable (upsert). (L3)
- SYN-5 [W] Problems panel: row named humanly, retry sequential + direct, discard exports first — always. Banner appears; panel absent when healthy. (L4)
- SYN-6 [E][W] Retry-loop error reporting: one fingerprint row with count, rate limits hold (20/session, 50/hr server). (L3)
- SYN-7 [E][TL] Airplane-mode day-long usage → reconnect: full queue uploads, balances match a server-side recompute exactly.
- SYN-8 [E][W] Two devices editing same rows offline → server-authoritative convergence, no lost ledger entries (last-write-wins on fields is acceptable; postings never dropped).

### A11Y / PERF
- A11Y-1 [TL] TalkBack/VoiceOver traversal of S1 screens; touch targets ≥48dp/44pt; dialogs trap focus (web fixed this — parity).
- A11Y-2 [W] Dynamic type / font-scale 200%: no clipped amounts (the digits that matter — see statements bug).
- PERF-1 [TL] Cold start < 2s on low-end device (Test Lab: 2GB RAM class); dashboard with 10k transactions scrolls at 60fps (macrobenchmark / XCTest metrics).
- PERF-2 [E][TL] 10k-transaction fixture DB: search, statement gen, budget calc within budgeted time; no OOM on 2GB device.

## 4. Firebase Test Lab (layer L5) — operations

- [ ] **TL.1 — Project setup.** Firebase project (Test Lab only — the app backend stays Supabase; do not add Firebase SDKs beyond what FCM already requires on Android; iOS Test Lab needs no Firebase SDK). Service account + `gcloud` in CI. Results bucket with 90-day lifecycle.
Division of labor: **Maestro** (not a Test Lab product) runs the scripted journeys on CI emulators/simulators; **Test Lab** contributes what emulators can't — real-device matrix, Robo crash crawls, hardware-bound smoke. The instrumented suites below are a *thin* native smoke layer (Espresso/UIAutomator + XCUITest driving the RN app — an RN app is a normal app to these tools), covering only the [TL]-marked hardware cases plus install→guest→first-transaction.

- [ ] **TL.2 — Android instrumented smoke matrix.**
  ```bash
  gcloud firebase test android run \
    --type instrumentation \
    --app app-debug.apk --test app-debug-androidTest.apk \
    --device model=<budget-2GB>,version=30 \
    --device model=<mid-samsung-a>,version=33 \
    --device model=<pixel>,version=35 \
    --locales en_IN,hi_IN --orientations portrait \
    --num-flaky-test-attempts 1 --use-orchestrator --shards 4 \
    --environment-variables clearPackageData=true
  ```
  Device policy: India-weighted — one 2GB/Android 11 budget device, one Samsung A-series, one Pixel latest; refresh the exact models quarterly from Test Lab's catalog (`gcloud firebase test android models list`). Hermetic backend: instrumented tests hit a **seeded staging Supabase project**, credentials via `--environment-variables`; every test namespaces its data by fresh user (anonymous auth) so runs don't collide.
- [ ] **TL.3 — Robo crawls** (nightly): `--type robo` on the same matrix + `--robo-directives` to get past onboarding (script the guest path), login-screen credentials via robo script. Purpose: crash discovery outside scripted flows. Any crash = P1 bug with the Test Lab video/logcat attached.
- [ ] **TL.4 — iOS matrix.** Build `xcodebuild build-for-testing` → zip → `gcloud firebase test ios run --test Tests.zip --device model=iphone8,version=<min-supported> --device model=<current-iphone>,version=<latest>` — one oldest-supported, one current. XCUITest covers the [TL] iOS cases; Robo is Android-only.
- [ ] **TL.5 — Special runs.** (a) Network-degraded profile run (Test Lab traffic shaping on physical devices) for SYN-7 class flows; (b) locale run `hi_IN` for I18N-3; (c) pre-release **full matrix** = every [TL] case × full device set; nightly = smoke subset (S1 flows + SYN + WID smoke).
- [ ] **TL.6 — CI wiring & policy.** Nightly + on release branches; PRs run L0–L4 only (Test Lab too slow/costly per-PR). Flake policy: 1 auto-retry (`--num-flaky-test-attempts`); a test that flakes twice in a week is quarantined to a non-blocking job and a fix task is filed — the blocking suite stays trustworthy. Track pass-rate per case ID.

## 5. Execution order for the executor

1. TL.1 + the L3 harness (local Supabase + fault-injection presets) — everything else depends on these.
2. L1 Hermes spec run green (mobile plan P0.2 owns the job; this plan owns the pass/fail policy: failures are fixed by polyfill/adapter, never by forking or weakening a core test).
3. Implement catalog cases **in the order features ship** (mobile plan slices S1→S6): a slice's cases are its exit gate.
4. [TL] cases become implementable per slice; wire into nightly as they land.
5. Web-marked [W] cases missing from Playwright today: backfill during S1–S3 period (the web app is the reference implementation — its E2E suite catches spec drift that would otherwise be ported into mobile).

## 6. Release exit criteria (per store submission)

- L0–L4: 100% green. L5 full matrix: 100% of non-quarantined; quarantine list reviewed, each item has an owner.
- PRIV sweep, SEC-1, SYN suite, AUTH-6: green with **zero** exceptions — these guard money, privacy, and data loss.
- No Robo crash on the full device set for 3 consecutive nightlies.
- Manual smoke on one real low-end Android + one real iPhone: install → guest → add account → txn → offline txn → reconnect → widget shows it.
