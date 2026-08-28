# PARITY_AUDIT.md — native ⇄ web parity reference (LLM boot file)

> **Read this INSTEAD of scanning `apps/web`, `apps/android`, `apps/ios`.** It is the single map of
> what web has, what each native app has, and what is actually missing. Companion files:
> `PROJECT_REFERENCE.md` (architecture), `CLAUDE.md` (rules), `docs/mobile/TODO.md` (task queue +
> handover), `docs/plans/mobile-pixel-parity-plan.md` (the method), `AUDIT_HISTORY.md` (dated log).
>
> **Goal of record (owner, 2026-08-23):** iOS and Android are exact replicas of the web app's mobile
> layout — pixel-for-pixel UI and identical functionality — implemented with each platform's best
> practices underneath. No approximations, no "close enough", no patch work.
>
> Generated 2026-08-23 by direct file inspection. Update the tables in place whenever a row's real
> status changes; put dated narrative in `AUDIT_HISTORY.md`, never here.

> **Deliberate gaps live in [`ABSENT-BY-DECISION.md`](ABSENT-BY-DECISION.md)** — every native
> gap that is a decision rather than an oversight, with the reason and what would close it.
> Adding a row there is part of the change that creates the gap, not a follow-up.

## 0. Size of the job (measured, not estimated)

| Surface | Lines | Note |
|---|---|---|
| `apps/web/app/**` pages | 10,754 | 48 route files incl. admin |
| `apps/web/app/AppShell.tsx` | 693 | the mobile shell — see §3 |
| `apps/web/src/**` | 22,529 | feature logic + shared UI |
| `apps/android/**/ui/**` | 12,133 | screens **and** ViewModels |
| `apps/ios/App/**` | 7,815 | views **and** ViewModels |

Native is roughly half of web's surface today, and the half that exists was largely written without a
source spec. Treat every ⚠️ row below as "needs re-derivation", not "done".

## 1. Rules that govern this work

1. **`apps/web` is ground truth and is never edited** to make a port easier.
2. **Visual values come from tokens**, generated from `apps/web/app/globals.css` by
   `tools/parity/generate-tokens.mjs`. Never eyeball a hex, size, radius or duration.
3. **Behaviour comes from `packages/core` golden vectors and the web source**, never from judgment.
   Money is integer minor units. Never edit a vector to make a port pass.
4. **Every screen is ported from a written spec** in `docs/mobile/screen-specs/<screen>.md`, derived
   from today's `.tsx` — not from memory, not from a screenshot.
5. **Nothing is marked DONE without a green compiler.** See §2.
6. **Platform chrome is the one licensed divergence**: safe areas, home indicator, status bar,
   predictive back, haptics, keyboard avoidance, dynamic type. Everything inside the content area
   follows the spec exactly.
7. No new third-party dependency without a human yes. Allowed set: PowerSync, Supabase, RevenueCat,
   FCM (+ platform-native camera/OCR/BLE frameworks).

## 2. Verification loop (the thing that was always missing)

No Gradle/Xcode toolchain exists in the agent sandbox, and `maven.google.com`, Maven Central and
`download.swift.org` are all blocked by egress policy — so **local compilation is impossible** and
always has been. That is how ~18 tasks were once marked DONE against files that did not exist.

**The compiler of record is GitHub Actions**, in `.github/workflows/mobile.yml`:

- **Android** (`ubuntu-latest`) — `./gradlew build test` against a real Android SDK.
- **iOS** (`macos-latest`) — `xcodegen generate` → `swift test` on the `Domain` package →
  `xcodebuild build test` on the app scheme. macOS runners are the **only** place SwiftUI is
  actually type-checked; Linux `swift build` reaches the SwiftPM packages and nothing else.
- **Parity** (`ubuntu-latest`) — regenerates every generated artifact and fails on any diff, so
  hand-edited generated output cannot survive a PR.

**Results come back over git, not the API.** The agent sandbox proxies `api.github.com` and
refuses `/repos/...` for this repository, so run status and logs cannot be polled the usual way —
but plain git (clone, fetch, push) works. So the workflow's final job writes each run's outcome and
captured compiler output to the orphan **`ci-logs`** branch under `runs/<run>-<sha>/`, and the
agent reads them with `git fetch origin ci-logs`. Pushing a commit is the trigger; fetching the
branch is the read. No API access required at any point.

- **`xcodegen` from `apps/ios/project.yml` is the source of truth for the Xcode project.** The
  `.xcodeproj` is no longer committed (untracked 2026-08-23). This permanently kills the "new
  `.swift` file was never added to `project.pbxproj`, so the app doesn't compile" bug class that
  bit on 2026-08-07 — there is no `pbxproj` left to forget to edit.
- Removed 2026-08-23: `ci.yml`'s `ios` job still referenced `PocketCare.xcodeproj` / scheme
  `PocketCare`; both were renamed to `Sanvya`, so it cannot have passed since the rename.

## 3. The app shell — largest single divergence

Web's mobile chrome (`apps/web/app/AppShell.tsx`, `src/navPrefs.ts`, `src/ui/BottomNavCustomizer.tsx`):

- **Floating bottom bar**, balanced 3-and-3: `Home` · slot1 · slot2 · **center "+"** · slot3 · slot4 ·
  `More`. Icons-only on phones. Active item tinted `--accent` on `--accent-ghost`.
- **4 customizable slots** persisted at `localStorage["pc_bottomNav"]`, catalog of 14 destinations,
  defaults `["transactions","accounts","friends","insights"]`, sanitised + topped-up on read
  (`navPrefs.ts` — port `sanitize()` exactly, including the short-list top-up).
- **"More" sheet** — grouped nav (Money / Planning / Growth / unlabelled), notifications row with
  unread pill, customize + close buttons, guest strip with days-left, Feedback, Install app, version.
- **Contextual "+"**: pages register their own add action (`useRegisterAddAction`); the default is a
  2-item menu (Add transaction · Scan bill/receipt, the latter lock-badged below Lite/Pro/trial).
- **Banners, in z-order**: `OfflineBanner` (sticky, `--warning`), `SyncProblemsBanner` (sticky,
  `--negative`, polls `failed_writes` every 30s, taps through to `/settings#problems`), sync-status
  message strip with Force Sync / Report Issue, `TrialNotice`, `GlobalLoader`.
- **Utility row** (every screen except the dashboard): single Back affordance + notification bell with
  unread badge. Exactly one back affordance per screen, in normal flow, never fixed.
- **Per-route scroll restoration** keyed `pc_scroll:<path>`, retried up to 20× as async content grows.
- Bare routes with no chrome: `/onboarding`, `/login`, `/join`, `/admin/*`.
- Auth gate: no session → replace to `/onboarding`. Pending invite token → replace to `/join`.
- On open (2.5s after auth): `runRecurring()` then `runLoanAutoPost()`, once per launch.

**Android: built 2026-08-23.** `ui/shell/` — bottom bar with the four customizable slots and the
raised centre "+", More sheet, customizer, all three banners, utility row, contextual add action,
`NotificationsRepository` for the bell badge. `NavDrawer.kt` deleted; the Dashboard's own speed-dial
FAB removed, since the shell's "+" is now the app's single add affordance. Still missing: per-route
scroll restoration and the launch-time recurring/auto-post pass.

**iOS: built 2026-08-23.** `App/Shell/` — the same seven pieces as Android.
`MainTabView.swift` and `DrawerMenuView.swift` **deleted** (both were a drawer, despite the
name). `ContentView.swift` is now the single `NavTab` → screen switch and is the app's root;
`NavTab` lost `.templates`/`.cashflow` (no such web routes) along with their placeholder views;
`NavModels.swift` lost the drawer's `NavGroup`/`NavItem`/`navGroups`, which also removes a name
collision with `BottomNav.swift`'s private `NavItem`. Screens that navigate
(`InsightsView`, `CreditCardsView`) get a `Binding<NavTab>` from the shell — writing through it
routes via `select()`, so a screen cannot navigate and leave the More sheet open.
Still missing on **both**: per-route scroll restoration, the launch-time recurring/auto-post
pass, the in-flow sync-status strip (`syncMessage()` + Force Sync / Report Issue),
`TrialNotice`, and `GlobalLoader`.

**Residual on both: every top-level screen still wraps itself in its own
`NavigationView`/`Scaffold` with a `navigationTitle`/`TopAppBar`.** Web's shell has no title bar
at any width below 1024 — the util row is the top of the page. So each ported screen currently
renders a system nav bar the web app does not have. Not a shell bug and not fixable at the shell:
it is one line per screen and belongs to that screen's W2 pass, where the title becomes the page's
own heading. Tracked here so it is not mistaken for done.

## 3a. Facade sweep, 2026-08-24 — how to re-run it

Three dead controls and three mock-data screens were all in places §4 marked as built. They were
marked built because they **render**, and rendering was never the question.

`/tmp` scripts are not the answer; the checks are recorded here so they can be repeated:

1. **Dead controls** — every `Button(action:)` / `onClick = {}` whose body reaches no view model,
   repository, callback, navigation or `Task`/`launch`. Local UI state (`showSheet = true`) is
   legitimate; nothing at all is not. Beware two *correct* empty handlers on Android: the one
   swallowing taps on a modal panel, and an `AssistChip(enabled = false)`.
2. **Mock data** — any `*UiModel(` / `*UiItem(` literal constructed inside a View or Screen file.
   A screen that builds its own rows is showing fiction.
3. **No data layer** — a `*Screen.kt` / `*View.swift` matching neither `viewModel.` nor
   `repository.`. Expect legitimate hits: pure components, the router, onboarding copy,
   `ComingSoonScreen`.

**And the check that caught my own error:** before concluding a feature is absent from web, look
at what the route file *renders*, not just the route file. `apps/web/app/assistant/page.tsx` is
nine lines. The assistant is 1,669 lines in `apps/web/src/assistant/`. I declared voice input
non-existent on the strength of the nine.

## 4. Route → platform map

**Re-verified 2026-08-25** by enumerating every `apps/web/app/**/page.tsx`, every file under
`apps/android/.../ui/` and `apps/ios/App/`, and both nav graphs. Line counts are `wc -l` on that
date. What this pass verified: *does a real screen exist and is it reachable*. What it did **not**
re-verify: field-level parity inside a screen — those notes are carried forward from the pass that
wrote them, and each is dated in its own section below.

Legend: ✅ ported, no known gap · 🔶 ported with recorded gaps · ❌ not built (placeholder) ·
🚫 n/a on native

| Web route | Web source (lines) | Android | iOS | Status |
|---|---|---|---|---|
| `/` dashboard | `app/page.tsx` (634) + `src/dashboard/*` (1320) | `dashboard/` (grid + 14 tiles) | `DashboardTileGrid` + `TileViews` | 🔶 **All fourteen tiles render** (2026-08-26), with the customisable grid, edit mode and the Add-a-widget picker. Absent: drag-to-reorder (move buttons instead), `grid-auto-flow: dense`, and web's measured row heights — all three recorded with reasons |
| `/accounts` | (126) | `accounts/AccountsScreen.kt` (148) | `AccountsView.swift` (119) | 🔶 |
| `/accounts/new` | (165) | `CreateAccountScreen.kt` (176) | `CreateAccountView.swift` (128) | 🔶 credit-card/demat branches + `MultiCurrencyCard` deferred |
| `/accounts/[id]/edit` | (189) | `EditAccountScreen.kt` (203) | `EditAccountView.swift` (261) | 🔶 |
| `/transactions` | (92) + `TransactionTile.tsx` (273) | `TransactionsScreen.kt` (148) | `TransactionsView.swift` (124) | 🔶 Split-row collapsing added 2026-08-26 (it was showing one dinner as three rows). Absent: the "Scanned" chip |
| `/transactions/new` | (674) | `CreateTransactionScreen.kt` (258) + `SplitEditor.kt` (408) | `CreateTransactionView.swift` (568) + `SplitEditorView.swift` (307) | 🔶 **Split editor built 2026-08-28** (both cards, all three modes, multi-payer, auto-split). Auto-categorise is built. Remaining: templates |
| `/transactions/[id]/edit` | (449) | `EditTransactionScreen.kt` (211) | `EditTransactionView.swift` (315) | 🔶 edit-history audit modal missing |
| `/cards` | (352) + `src/cards` (75) | `creditcards/CreditCardsScreen.kt` (307) | `CreditCardsView.swift` (282) | 🔶 |
| `/friends` (shared & owed) | (493) + `src/splits/*` (1432) | `splits/SplitsScreen.kt` (226) | `SplitsView.swift` (144) | 🔶 FriendInsights/Patterns panel not rendered; 2026-08-12 tiles redesign not ported |
| `/groups/[id]` | (364) | `splits/GroupDetailScreen.kt` (275) | `GroupDetailView.swift` (313) | 🔶 equal-split only; percent/exact/itemised and group edit/delete missing |
| `/budgets` (+ new/edit) | (410) | `budgets/*` (650) | `BudgetsView` + Create/Edit (531) | 🔶 |
| `/goals` (+ new/edit/allocate) | (304) + `GoalCelebration.tsx` (222) | `goals/*` (557) | `GoalsView` + Create/Edit/Allocate (475) | 🔶 GoalCelebration not ported |
| `/recurring` | (218) + `src/recurring` (334) | `recurring/RecurringScreen.kt` (257) | `RecurringView.swift` (217) | 🔶 no shell "+" — web registers it via `useRegisterAddAction`; no native screen registers into `AddAction` yet |
| `/recurring/[direction]` | (157) | `RecurringDirectionScreen.kt` (205) | `RecurringDirectionView.swift` (182) | 🔶 category donut absent (shared `DonutChart` is a refactor of two working screens) |
| `src/cashflow/RecurringModal.tsx` | (155) | `RecurringFormScreen.kt` (316) | `RecurringFormView.swift` (202) | 🔶 preset name chips + alert time absent by decision (2026-08-25) |
| `/loans` (+ new/edit) | (249) | `loans/LoansScreen.kt` (151) + Add/Edit | `LoansView.swift` (447) + Add/Edit | 🔶 |
| `/loans/[id]` | (484) + `src/loans` (368) | `loans/LoanDetailScreen.kt` (359) | inside `LoansView.swift` | 🔶 auto-post surfacing + recurring groups missing |
| `/investments` | (370) + `src/investments` (1787) | `investments/*` (850) | `InvestmentsView` + AddHolding (414) | 🔶 live catalog picker, SIP recurring transfer, CSV/XLSX import deferred |
| `/insights` | (60) + `src/insights` (789) | `insights/InsightsScreen.kt` (378) | `InsightsView.swift` (505) | 🔶 18 generators ported; full-bleed feed layout + entitlement CTA need re-check |
| `/statements` | (145) + `src/statements` (781) | `statements/StatementsScreen.kt` (193) | `StatementsView.swift` (143) | 🔶 real on both since 2026-08-24. Print, Analyze link and Go-Premium absent by decision |
| `/login` | (334) | `auth/LoginScreen.kt` (430) | `LoginView.swift` (427) | 🔶 all four methods on both; **no live Google sign-in has ever completed**, guest upgrade unverified |
| `/receipts/new` | (339) + `src/receipts` (860) | `receipts/ReceiptCaptureScreen.kt` (274) | `ReceiptCaptureView.swift` (207) | 🔶 camera only; no PDF/gallery, no AI escalation |
| `/receipts/review` | (501) | `receipts/ReceiptReviewScreen.kt` (283) | `ReceiptReviewView.swift` (259) | 🔶 text-only OCR path (no word boxes) |
| `/settings` | (272) | `SettingsScreen.kt` (527) | `SettingsView.swift` (400) | 🔶 Categories/Labels and Import-Export sections added 2026-08-26. Absent: Security/crypto, Language |
| `/receipts/split` | (522) | ✅ `ui/receipts/SplitReceiptScreen.kt` + `SplitReceiptViewModel.kt`, routed from review | ✅ `SplitReceiptView.swift` + `ViewModels/SplitReceiptViewModel.swift`, covered from review | ✅ **done 2026-08-27.** Itemized write path (`createSplitExpenseItemized`) on both repositories; the screen's own arithmetic is `SplitAssign` in Domain under 79 vectors. Both review screens' dead "Split this bill — coming soon" chips are the real toggle now |
| `/settings/categories` | (157) | `taxonomy/CategoriesScreen.kt` (280) | `TaxonomyViews.swift` (CategoriesView) | 🔶 **Built 2026-08-26.** Tree with search, expand/collapse, inline rename, add with kind + parent, soft delete. Absent: the Auto-categorize card — it drives `src/categorize/` (905 lines), which is its own port |
| `/settings/labels` | (89) | `taxonomy/LabelsScreen.kt` (185) | `TaxonomyViews.swift` (LabelsView) | 🔶 **Built 2026-08-26.** Search, add, inline rename + recolour, soft delete. Colour is the app's 18-swatch palette, not web's free `<input type="color">` — see the divergence note |
| `/data` (import/export) | (154) + `src/data` (509) | `data/DataScreen.kt` (250) | `DataView.swift` (240) | 🔶 **Built 2026-08-26.** CSV export and import (PocketCare + Wallet formats), format picker, skip-duplicates, six-row preview, result line, premium gate. File IO is SAF on Android and `.fileExporter`/`.fileImporter` on iOS — no shared shape to port |
| `/statements/analyze` | (329) + (419 in `src/statements`) | ✅ `ui/statements/StatementAnalyzeScreen.kt` + view model | ✅ `StatementAnalyzeView.swift` + `ViewModels/StatementAnalyzeViewModel.swift` | ✅ **done 2026-08-27, CSV *and* PDF.** Parse, on-device categorise, summary, donut + daily bars, outliers, recurring detection with add-as-recurring, reconcile, import-missing. Domain under **89 vectors** (61 CSV/analysis/reconcile + 28 PDF) |
| `/assistant` | (9) + `src/assistant` (1669) | ❌ `ComingSoonScreen` | ❌ `AssistantView` (27) placeholder | ❌ biggest single unbuilt feature |
| `/search` | (148) | `search/SearchScreen.kt` (232) | `SearchView.swift` (145) | 🔶 **Built 2026-08-26.** Query, type/account/date/amount filters, result count, collapsed split rows. Absent: the `?q=&type=&account=…` deep-link prefill — it exists so the assistant can hand over a pre-filtered search, and there is no native assistant to hand one over |
| `/reflect` | (97) + `src/reflect` (160) | `reflect/ReflectScreen.kt` (300) | `ReflectView.swift` (200) | ✅ **Built 2026-08-26.** Swipeable card stack, need/greed buttons, undo, skip, counter, empty state. Two deliberate divergences away from web — see the session note |
| `/help` | (152) | `help/HelpScreen.kt` (190) | `HelpView.swift` (110) | ✅ **Built 2026-08-26.** All 11 sections and 33 Q&A pairs, GENERATED from web's own `SECTIONS` by `tools/parity/generate-help.mjs`, plus search and expand/collapse. The one gap is web's too: the FAQ copy is English on all three |
| `/notifications` | (75) + `src/notifications` (350) | `notifications/NotificationsScreen.kt` (215) | `NotificationsView.swift` (145) | 🔶 **Built 2026-08-26.** Inbox, unread tint, severity dot, mark-read, mark-all-read, dismiss, empty state. Absent: the row's `href` deep link — there is no web-path → native-route map yet |
| `/onboarding` + `src/onboarding/Walkthrough.tsx` | (119) + (446) | ✅ `ui/onboarding/WalkthroughScreen.kt` + `WalkthroughViewModel.kt` (gate + steps), mounted by `DashboardScreen` | ✅ `WalkthroughView.swift` (rewritten) + `ViewModels/WalkthroughViewModel.swift` (`WalkthroughGate` + `WalkthroughViewModel`), mounted by `DashboardView` | ✅ **done 2026-08-23.** All 7 steps, both writes, the `done`/`skipped` split, and `shouldShowWalkthrough()` in Domain under 103 vectors. The `/onboarding` **slide deck** (119) is a separate pre-auth screen and is still unported — see the auth-gate row |
| `/groups` | (19) redirect → `/friends` | 🚫 | 🚫 | 🚫 |
| `/subscriptions` | (8) redirect → `/recurring` | 🚫 | 🚫 | 🚫 |
| `/join?token=` | (53) | ✅ `ui/join/JoinScreen.kt` + view model | ✅ `Join/JoinView.swift` | 🔶 **screen done 2026-08-27, link routing blocked.** Accept, stash-through-sign-in, join, land in the group. An `https://sanvya.app/join` link still opens the browser: both `.well-known` files are placeholders. `com.sanvya.app://join?token=` works today — see ABSENT-BY-DECISION |
| `/auth/callback` | (87) | 🚫 | 🚫 | 🚫 a native app cannot host an HTTP route; both use a custom scheme |
| `/admin/*` | 7 pages (1291) | 🚫 | 🚫 | 🚫 web-only, English-only, out of scope |

### Remaining work — measured 2026-08-27, by reading web against both ports

The table above answers *does a screen exist and is it reachable*. This answers *what is still
missing inside it*, and it was produced by four parallel passes that read each web page, enumerated
its user-visible controls and branches, and checked each one against both native files. A feature
counts as present only where the code that implements it can be pointed at.

**91 distinct gaps.** Sizes are for ONE platform: **S** < 50 lines, **M** 50-200, **L** 200+.

| Slice | Gaps | L | M | S |
|---|---|---|---|---|
| Transactions · accounts · receipts | 25 | 3 | 7 | 15 |
| Splits · groups · friends | 25 | 1 | 7 | 17 |
| Budgets · goals · loans · investments · recurring | 17 | 2 | 8 | 7 |
| Shell · settings · insights · dashboard · components | 24 | 2 | 7 | 15 |
| **Total** | **91** | **8** | **29** | **54** |

Doubling for two platforms and costing the buckets at 300 / 120 / 30 lines gives roughly
**15,000-20,000 lines** of native code, before the Domain ports and golden vectors that anything
with real rules needs. At the rate this work has actually landed — about 1,500-2,000 lines a cycle
including docs and vectors — that is **ten to fifteen more cycles**, not one or two.

#### The seven that make a feature unusable end to end

Ranked by whether a native-only user can complete the job at all, not by size.

| # | Gap | Platforms | Size | Why it is first |
|---|---|---|---|---|
| ~~1~~ | ~~**Group invites**~~ | both | L | ✅ **2026-08-27.** Connection search, typed-email chips, one call per chip, and the share link. The selection rules are Domain's under 30 vectors; the link is the SERVER's, because a phone has no origin to build one from |
| 2 | **Split expense on New transaction** | both | L | ✅ **Done 2026-08-28.** Domain (`splitPlan`, `splitActive`, `forOtherActive`, `autoSplitGroupFor`, `jsNumber`) under 35 vectors landed 2026-08-27; the editor followed — `SplitEditor.kt` / `SplitEditorView.swift`, both save() branches (split + "paid for someone else"), `watchAllGroupMembers()` on both repositories, and the auto-split preselection with web's `splitTouched` guard. Nothing in the UI computes: every number and the Save gate come from Domain |
| 3 | **Android: Add-expense in a group is unreachable** | Android | S | The sheet is fully implemented; nothing sets `showAddExpense`, and the page action is an empty lambda. A group is read-only on Android |
| 4 | **Credit-card branch on New account** — limit, statement day, due day, cycle-aware `pending_due` | both | L | A card created natively silently drops every field the Cards screen and its reminders are built on |
| 5 | **Receipt capture is camera-only** — no file upload, no PDF, no AI escalation, no entitlement gate | both | L | The emailed PDF bill is the feature's main input. Free-tier users meet a server rejection instead of the paywall card |
| 6 | **Pending settlements** — confirm / dispute | both | M | Both repositories already have `confirmSettlement`/`disputeSettlement`. With no UI, a UPI settlement raised natively is stuck pending until the payee opens the browser |
| 7 | **Live market quotes** | both | L | Without LTP and day-change every portfolio figure on native is whatever was last typed in. Investments is a manual ledger where web is a live portfolio |

#### Dead or lying controls — the cheapest and the most damaging

Each of these is a control the user can see and touch that does nothing, or does the wrong thing.
Per this project's own rule (`ABSENT-BY-DECISION.md`, first paragraph) these are worse than an
absence, and they are almost all `S`.

| Gap | Platforms | Size | State |
|---|---|---|---|
| ~~**Feedback** button in the More sheet and the side nav is wired to a closure that only closes the sheet~~ | both | M | ✅ 2026-08-27 — `FeedbackSheet` on both, the vocabulary generated from web's own `AREAS`/`SEVERITIES`, every string translated (web's own modal is not — defect #13) |
| ~~`include_in_net_worth` checkbox on New account is never read by `save()`~~ | both | S | ✅ 2026-08-27 — the create path now UPDATEs the flag off, as web does |
| ~~Android's group Add-expense action~~ | Android | S | ✅ 2026-08-27 — the sheet was built and unreachable; the page action opens it |
| ~~iOS dashboard renders a second FAB speed dial beside the bottom bar's "+"~~ | iOS | S | ✅ 2026-08-27 — removed; both of its actions moved into `AppShell`, where the "+" already was |
| ~~iOS shell "+" → "Scan bill / receipt" selected a nil tab and did nothing; "Add transaction" opened the transactions LIST~~ | iOS | S | ✅ 2026-08-27 — `AddAction.Item` gained a `flow` case for the two destinations that are forms rather than tabs |
| ~~Investment accounts are offered in the New-transaction account picker~~ | both | S | ✅ 2026-08-27 — web's `NOT_INVESTMENT_ACCOUNT_SQL` applied on the create form only, as web applies it |
| ~~Android's shell "+" labels ("Add", "Add transaction", "Scan bill / receipt") are hardcoded English~~ | Android | S | ✅ 2026-08-27 — the three catalogue keys existed the whole time |
| ~~The "investment accounts only support transfers" line is hardcoded English~~ | both | S | ✅ 2026-08-27 — `transactions:investmentTransferOnly` existed the whole time |
| Settle-up: no "None — mark settled" option; UPI is offered regardless of currency or sign | both | S | open |
| Android's `SyncStatusStrip` is defined and never called | Android | S | open — dead CODE, not a dead control: nothing renders, so nothing lies. Wiring it is a real port (`syncMessage` is not in Domain and the shell has no sync-status stream), not a two-line fix |
| `BlockingLoader` / `GlobalLoader` exists on both with zero call sites | both | S | open — same reasoning as above |
| Settings' "Replay intro" string exists in `S.kt` and is wired to nothing | Android | S | open |

#### Blocked on Akhilesh, not on code

Nothing below can be closed by writing native code, and three of them gate a release.

| Blocked | Gates |
|---|---|
| Release keystore SHA-256 for `assetlinks.json`; Apple Team ID for `apple-app-site-association` | `https://sanvya.app/join` links opening the app instead of a browser |
| APNs auth key + Push capability; `notify-dispatch` reading `platform`/`token` | Any push notification reaching an iOS device |
| Two Google OAuth client IDs; `com.sanvya.app://auth-callback` in the Supabase allowlist | A live Google sign-in has **never completed** on either platform |
| A test Supabase + PowerSync project | Any integration test at all — now also the assistant's SQL |
| Go-ahead on the ×100 sweep (29 Android / 20 iOS sites) and on `anchor_day` | Correct behaviour for JPY/KWD/BHD; recurring drift |
| A decision on the eight web defects | Whether native keeps reproducing them |

### Score, honestly

| | Android | iOS |
|---|---|---|
| Web routes in scope for native (44 total, less 7 `/admin`, 2 redirects, `/auth/callback`) | 35 | 35 |
| Ported and reachable | **35** | **35** |
| Not built (honest placeholder) | 0 | 0 |
| Ported with **zero** recorded gaps | 5 | 5 |

**Every in-scope route now has a real, reachable screen on both platforms** — `/assistant` was the
last placeholder and closed 2026-08-27. That is a milestone and it is also the least interesting
number here: coverage moved from 23 to 35 while the *inside* of those screens still carries the 91
gaps measured above. A route map that reads 35/35 is exactly how a port convinces itself it is
finished. Read the remaining-work tables, not this one.

The two platforms are now at the **same** coverage, screen for screen. They were not on
2026-08-24: iOS had Statements and a Walkthrough file that Android did not, and Android had a
Recurring form that iOS did not. Both of those closed this week.


## 5. Shared component inventory

Each must exist **once** natively and be reused — the recurring failure mode has been re-inlining an
approximation per screen (iOS's old credit-card face).

| Web primitive | File | Android | iOS |
|---|---|---|---|
| `.card` / `.btn` / `.chip` / `.input` / `.tap-row` / `.row-stack` / `.list-grid` | `app/globals.css` | ❌ no component layer | ❌ ad hoc per view |
| `TransactionTile` (the ONLY transaction row) | `src/ui/TransactionTile.tsx` (273) | `transactions/TransactionTileLogic.kt` (logic only) | `TransactionTileLogic.swift` (logic only) | 
| `MaterialIcon` (Material Symbols set) | `src/ui/MaterialIcon.tsx` | 🔶 `Icons.Default.*` — different glyphs | 🔶 SF Symbols — different glyphs |
| `Money` / `useMoneyFmt` / `amountFormat` | `src/ui/Money.tsx`, `amountFormat.ts` | 🔶 per-screen formatters | 🔶 per-screen formatters |
| `Modal`, `Confirm`, `KebabMenu` | `src/ui/*` | ❌ | ❌ |
| `AmountInput`, `FloatingInput`, `PasswordInput`, `SearchSelect`, `MultiSelect`, `LabelPicker` | `src/ui/*` | ❌ | ❌ |
| `ProgressBar`, `Skeleton`, `Spinner`, `GlobalLoader` | `src/ui/*` | ❌ | ❌ |
| `AddSpeedDial` / `AddAction` context | `src/ui/AddSpeedDial.tsx` (224) | 🔶 dashboard-only FAB | 🔶 dashboard-only FAB |
| `BottomNavCustomizer` | `src/ui/BottomNavCustomizer.tsx` | ❌ | ❌ |
| `TrialNotice`, `UpgradeModal`, `Billing` | `src/ui/*` | ❌ | ❌ |
| `BugReport`, `InstallGuide`, `ErrorBoundary` | `src/ui/*` | ❌ | ❌ |
| `ProblemsPanel`, `RepairPanel`, `DiagnosticsPanel` | `src/sync/*`, `src/diagnostics/*` | 🔶 inside Settings | 🔶 inside Settings |
| `PayViaUpi`, `PayAnyone`, `PendingSettlements`, `PaymentHandlePanel` | `src/payments/*` | 🔶 dialog only | 🔶 sheet only |

## 6. Cross-cutting gaps

| Gap | State | Owner task |
|---|---|---|
| **i18n** | Web: 28 namespaces, ~1,465 keys, en/hi/nl. Native: **zero** — every string hardcoded English | W0.4 |
| **Design tokens** | Generator emits colours + radii only. Typography, spacing, shadows, motion, component recipes not generated | W0.3 |
| **Icons** | Web uses Material Symbols; Android uses `Icons.Default`, iOS uses SF Symbols → different shapes on every screen | W1 |
| **Typeface** | Web is Inter throughout. Neither app bundles Inter | W0.3 |
| **Dark theme** | `globals.css` has a full `[data-theme="dark"]` block; native theming unverified against it | W0.3 |
| **State preservation (R1)** | Android partial (rememberSaveable on some screens); iOS `@SceneStorage`/draft-save **not started**; LIFE-4 process-death untested on both | per-screen |
| **Accessibility** | No TalkBack/VoiceOver pass; touch-target and contrast unaudited | pre-launch |
| **Sync L3 (P2.7)** | Blocked since 2026-07-31 — needs a test Supabase + PowerSync project and a real device round-trip | **needs Akhilesh** |
| **i18n keys web calls but never defined** | 46 keys across 8 namespaces (`tools/parity/audit-i18n-usage.mjs`). Web hides this: `t("netMonthly", "Net monthly")` falls back to its inline English default, so English looks perfect and **hi/nl silently render English**. Native has no inline default — a missing key is a missing resource — so each must be added to `packages/core/i18n` before its screen can be ported | W0.4 |
| ~~**No `RecurringRepository` on either platform**~~ | Built on both 2026-08-24/25: watch, materialize, `runRecurring`, post/skip once, remove, and `create`/`update`. **Web's `toRow` does `Math.round(amount * 100)`** — a hardcoded ×100 that is wrong for JPY (0 minor units) and BHD (3) and violates golden rule 1. Both native ports call `fromMajor(major, currency)`, which asks `minorUnits(currency)`. Web's is Akhilesh's call — not touched | ✅ |
| **iOS `AppShell.runAdd()` has `case .button: break`** | A screen registering an `AddAction.button` gets a "+" that does nothing. Android's shell dispatches `action.onClick()` correctly. No screen registers on either platform today, so nothing is broken *yet* — but the case is a live dead control waiting for its first caller | W2 |
| **No `useUnreadCount()` equivalent natively** | The shell's bell badge and the Notifications screen both need it; neither platform has the query | W1 |
| **`notifications` has no i18n namespace at all** | The web screen has zero `t()` calls. Porting it as-is would put the one hardcoded-English screen into apps that are otherwise fully localised | W4 |
| **Tablets / foldables / large windows** | Required as of 2026-08-23, spec in `screen-specs/app-shell.md` §1/§1a/§1b. **Android: done** — `WindowClass.kt` (Material 3 breakpoints, device type from `FEATURE_SENSOR_HINGE_ANGLE` + `sw600dp`, orientation policy), `SideNav.kt`, the Expanded branch of `AppShell.kt`, manifest `configChanges`. **iOS: done** — `WindowClass.swift` (size class + an 840×480 gate matching Android's, device type from `UIUserInterfaceIdiom`), `SideNav.swift`, the `.expanded` branch of `AppShell.swift`, orientation declared in `project.yml` (`UISupportedInterfaceOrientations` + `~ipad`). Still open on both: the Expanded **top bar** (web draws it alongside the util row, giving two bells — deliberately deferred, see spec §1a), every screen's own content re-checked at Medium/Expanded, and iPad Slide Over / Split View / Stage Manager | **W1.5** |
| **Bundle ids / Universal Links domain** | Still placeholders (`com.sanvya.app`, `com.sanvya.app.ios`) — blocks `/join` deep links and store prep | **needs Akhilesh** |
| **Min OS versions** | Proposed minSdk 26 / iOS target unconfirmed | **needs Akhilesh** |

## 6b. The live client is off-limits — and I crossed that line

Standing rule (Akhilesh, 2026-08-24): *"we are not supposed to touch the live client. Currently
our focus is strictly to bring ios and android up to speed with web."*

Web is the shipped app. This branch is a native port. **Native may read from web; it must not
change web.** Reverted 2026-08-24:

| File | What I had changed | Why it was wrong |
|---|---|---|
| `apps/web/src/insights/generators.ts` | `major()` currency-aware, `minor()` added, weekday `×100` fixed | Real bug, but it alters every chart value and `metric.raw` on the shipped client |
| `packages/core/mindfulness/src/index.ts` | `computeTier1Insights` took a currency + formatter | Signature change forcing a web call-site change; also alters shipped insight copy |
| `apps/web/src/colors.ts` | Re-export from `@sanvya/catalog` | Tidiness, not necessity |
| `apps/web/app/{accounts/new,budgets,goals,settings}/page.tsx` | Currency list from `@sanvya/catalog` | Same |
| `apps/web/package.json`, `pnpm-lock.yaml` | Added the `@sanvya/catalog` dependency | Follows from the above |

`packages/core/catalog` **stays**, but is now **generator-input only**: nothing in `apps/web`
imports it, and the native `FormOptions` files are generated from it. It reads web's values
without changing web's code, which is the right shape for everything on this branch.

### Still touching web, and needing a decision

Two changes predate this rule and are **not** reverted, because reverting them breaks the icon
pipeline both native platforms depend on:

- `apps/web/src/ui/MaterialIcon.tsx` — one added glyph (`lock: "\ue897"`), needed by the shell's
  add-menu lock badge. `generate-icons.mjs` parses this file as its source of truth.
- `apps/web/public/fonts/pocketcare-icons.woff2` — rebuilt to include that glyph.

Both are **purely additive**: no existing glyph moved or changed codepoint, so web renders
identically. Flagging rather than deciding — if the rule is absolute, the icon generator needs a
source that is not a web file.

### Web bugs found while porting — for Akhilesh to schedule separately

Found by reading web as the parity source. **None are fixed on web.** All but #4 are fixed
in the native ports, which deliberately diverge from their stated source; the fourth is
reproduced deliberately and pinned by a vector, because a silent divergence on an amount is
worse than a shared bug.

1. **`packages/core/mindfulness`, `small_purchase_drift`** — body built as `totalSmall / 100`.
   Hardcoded divisor (¥43,215 renders "432.15"); a `20000`-minor threshold the copy calls a bare
   "200"; sums **across currencies** without converting; bypasses the money formatter, so it has
   no symbol and **cannot be hidden by the hide-amounts toggle**.
2. **`apps/web/src/insights/generators.ts`** — `major()` is `minor / 100`, feeding every chart
   value and `metric.raw`.
3. **`generators.ts:207`** — `fmt(top.value * 100, ctx)`, converting major back to minor with the
   same constant.

All three are wrong for any currency without two minor units — JPY, KWD, BHD. For an INR-first
user base they are invisible today, which is exactly why they have survived.

4. **`apps/web/src/data/adapters.ts`, `num()` — CSV import silently divides European
   amounts by a thousand.** Found 2026-08-26 while porting the importer, and it is the
   worst of the four because it corrupts data rather than mis-formatting it.

   `"1.234,56"` — one thousand two hundred and thirty-four euros — parses as **1.23456**.
   The cleanup strips a comma only when three digits follow it (`,(?=\d{3}\b)`), so the
   decimal comma survives; the "commas but no dot means European" branch then does not fire
   because there IS a dot; and the final `replace(/,/g, "")` deletes the decimal comma,
   leaving `"1.23456"`.

   It matters here specifically: the second importer is **Wallet by BudgetBakers**, a Czech
   app whose European users' exports are exactly this format. A `€1,234.56` charge imports
   as `€1.23` and nothing warns anyone.

   Both native ports reproduce it, and a golden vector pins it — so a fix on web makes that
   vector fail rather than passing quietly on two platforms out of three. **This one is
   worth scheduling ahead of the other three.**

   **It has a second site.** `apps/web/src/statements/parseCsv.ts`'s own `num()` is a
   different implementation with the identical defect, found 2026-08-27 while porting the
   statement analyzer. Fixing `adapters.ts` alone would leave a European statement still
   importing at a thousandth of its value through the *other* door. Both are now pinned:
   `csv.json` for the first, `statements.json`'s `semi` fixture for the second — that one
   is a plain English-header CSV with semicolons and European decimals, and web's own
   output for it records `1.234,56` arriving as **1.23**.

5. **`apps/web/src/data/exportCsv.ts` — the CSV round trip loses money for any currency
   that is not two-decimal.** The exporter writes `(amount / 100).toFixed(2)` and the
   importer reads that straight back with `fromMajor`, which uses the currency's real
   minor-unit count. A ¥500 charge exports as `"5.00"` and re-imports as **¥5**.
   Both native ports use `minorUnits(currency)` in both directions, which is byte-identical
   to web's output for INR, USD and EUR and correct for the rest.

6. **`toIso` in `apps/web/src/data/importCsv.ts` reads a dateless date column in the
   DEVICE's timezone.** `new Date(yr, mm-1, dd, hh, mi)` is local, then `.toISOString()`.
   The same CSV therefore imports different `occurred_at` values in Mumbai and in London,
   and a `DD/MM/YYYY` row dated the 1st lands on the previous day for anyone east of UTC.
   Both ports read it as UTC, which is the only answer that gives every device the same
   ledger from the same file.

8. **`apps/web/src/statements/parseCsv.ts` — the same hardcoded ×100, twice more.**
   `Math.round(amount * 100)` on every transaction and `Math.round(num(row[bali]) * 100)`
   on every running balance. That makes four sites of the same constant across web
   (#2, #3, #7, #8), and this one is the most consequential yet: it is the *import*
   path, so a ¥500 row does not merely display wrong, it lands in the ledger as ¥5.
   Both ports use `fromMajor()`, which reads the currency's own minor-unit count and
   is byte-identical to web's output for INR, USD and EUR.

   Vector-pinned from both sides: the `hdfc`/`semi`/`tab` fixtures were generated by
   running web and match it exactly; the `jpy` fixture is the single hand-edited
   expectation in `statements.json`, and it is annotated in place with why.

7. **`apps/web/src/onboarding/Walkthrough.tsx`, `saveSpend()` — the same hardcoded ×100,
   on the very first amount a new user ever enters.** `Math.round((Number(spendAmount) ||
   0) * 100)`, three lines below a `saveAccount()` that correctly calls
   `fromMajor(major, base)` for the opening balance. So a walkthrough that asks for an
   opening balance and a first spend records the first correctly and the second wrong for
   any currency that is not two-decimal — a ¥500 lunch lands as ¥5, in the one flow whose
   entire purpose is to convince a nervous first-timer the app can be trusted with numbers.
   Both ports use `fromMajor` on both.

9. **The assistant persona advertises two routes web does not have.** `AssistantChat.tsx`'s
   `PERSONA` lists the pages the model may deep-link to, and two of them — `/cashflow` and
   `/templates` — have no `page.tsx` anywhere under `apps/web/app`. The model is being told, in
   its system prompt, to hand users links that 404. Found 2026-08-27 while building the
   web-path → native-route translation.

   Native cannot reproduce a 404, so `parseAppLink` **refuses** both paths and the action is
   never offered. Those two refusals are pinned as `null` in `applink.json`, so a later "fix"
   that invents a native destination for them fails loudly. The real fix is one of: build the
   two pages, or drop them from the persona text (which is generated from web's own source, so
   the edit belongs there).

10. **The out-of-quota card's free-plan branch is unreachable.** `AssistantChat.tsx` gates the
    whole screen on `isPremiumUser || hasActiveTrial`, which is exactly `useEntitlement().isPaid`
    — and then branches the out-of-quota card on `isPaid` again. Anyone who can see the card has
    already passed the same test, so `outFreeBold` / `outFreeRest` / `seePlans` can never render.
    Three translated strings in three languages, dead. Ported as-is (the branch is web's, and the
    day the gate loosens the right words are already in place), noted here rather than quietly
    dropped.

11. **`var(--negative-ghost)` is not a token.** The quota chip is written
    `background: isOutOfQuota ? "var(--negative-ghost)" : "var(--surface-2)"` in both places it
    appears, and `--negative-ghost` is defined **nowhere** in `globals.css`. An undefined custom
    property invalidates the whole declaration, so the out-of-quota chip does not turn red — it
    silently falls back to `.chip`'s own surface, and the one state the chip exists to signal is
    the one state it does not signal. `SecurityPanel.tsx` uses the same variable **with an inline
    fallback**, so this was already known somewhere.

    Both ports reproduce web's actual rendering rather than its evident intent: inventing the
    colour natively would make the phone and the browser disagree about something the user can
    see. One line in `globals.css` fixes all three sites at once.

12. **`MicButton.tsx` is hardcoded English in an otherwise translated app.** Four
    user-visible strings — "Stop recording", "Stop", "Transcribing…", "Speak" — and
    the tooltip "Speak to Sanvya", all string literals in the component. A Hindi or
    Dutch user sees them in English. Found 2026-08-27 while porting voice.

    Both native ports read from the catalogue instead: five keys (`micSpeak`,
    `micStop`, `micTranscribing`, `micHint`, `micDenied`) were added to
    `packages/core/i18n/src/locales/assistant/` in all three locales, and
    `voiceLabelKey()` in Domain returns the KEY so the choice stays vector-pinned
    while the wording stays per-locale. The keys are there for web to adopt in one
    small edit; the edit is web's to make.

    `micDenied` has no web counterpart at all — web cannot detect a permanently
    refused microphone the way a native permission API can, so it says nothing.

13. **`BugReportModal` is hardcoded English — the whole modal.** Roughly thirty
    user-visible strings, from "Send feedback" to the beta-tester reward copy, all
    string literals in `apps/web/src/ui/BugReport.tsx`. It is the app's only
    error-report channel, so a Hindi or Dutch user who hits a bug meets an English
    form. Found 2026-08-27 while porting it.

    Both native ports read from a new `feedback` namespace — 44 keys in all three
    locales — and the two lists that must NOT be translated (`AREAS` and
    `SEVERITIES`, which are written into `bug_reports` and read by whoever works
    the queue) are generated from web's source by `generate-feedback.mjs`. The
    keys are there for web to adopt.

14. **Seven invite strings are missing from the catalogue.** `groups/[id]/page.tsx`
    calls `t("invitePlaceholder", "Search people or type an email")` and six more
    with inline `defaultValue` fallbacks — so English is perfect and Hindi and
    Dutch quietly render English. This is the exact failure mode
    `audit-i18n-usage.mjs` was written to report, and it reported these.

    Added to `packages/core/i18n/src/locales/groups/` in all three locales while
    porting the invite modal: `remove`, `invitePlaceholder`, `inviteAddEmail`,
    `inviteNarrow`, `inviteCount`, `invitedAdded`, `invitedLinks`, `invitedFailed`
    — four of them as plurals, which the inline defaults were not. Web keeps
    working unchanged and picks them up the moment anyone drops the fallbacks.

15. **The split editor's `toMinor` is the ×100 again — and here it BLOCKS the
    save.** `apps/web/app/transactions/new/page.tsx`'s `splitPlan` reads every
    typed share with `Math.round(Number(v) * 100)`. In exact mode the plan is only
    valid when the shares sum to the total, so for a zero-decimal currency the
    sum comes out a hundred times too large, never balances, and the Save button
    stays disabled: a JPY user cannot record an exact-mode split **at all**.

    Every earlier site of this constant mis-*displays* or mis-*stores* an amount.
    This one removes a feature. Both ports use `fromMajor(major, currency)`; the
    `split-plan.json` fixtures for JPY and KWD are the only vectors in the corpus
    that deliberately disagree with what a browser would produce, and they are
    annotated in place so the disagreement stays deliberate.

### iOS was formatting numbers as pointers — twelve call sites, 2026-08-27

Found while building the assistant's quota chip, which needed
`S.Assistant.creditsSuffix(n:)`.

`generate-i18n.mjs` emitted every non-plural interpolation as `%@` on iOS and
typed the accessor's parameter `CVarArg`. `%@` is an **object pointer**
specifier. Passing an `Int` to it is undefined behaviour: `String(format:)`
reads the integer as an address and prints whatever it finds, silently, with no
warning at compile time and no crash at run time. Twelve call sites were doing
exactly that:

| Where | Reads |
|---|---|
| `NotificationsView` × 3 | "3 minutes ago" / hours / days on **every** notification row |
| `ReflectView` | "N left" |
| `MoreSheet` | the bottom-bar customise hint |
| `SplitReceiptView` | the percentage-mismatch error |
| `StatementAnalyzeView` × 3 | the parsed-transaction counts |
| `TileViews` × 3 | "+N more" on two dashboard tiles |
| `WalkthroughView` × 4 | "Step 1 of 7", the plan price and its quota |

Android was never affected: Java's `%s` accepts any object and calls
`toString`, so `Any` is the right parameter type there.

**Fixed by typing the parameter, not by fixing the calls.** Non-plural
arguments are now generated as `String`, so an `Int` at a call site is a
compile error rather than a garbage address — the thirteen sites above were
then found by the compiler-shaped change and stringified explicitly. `count` on
a genuine plural stays `Int`: it selects the grammatical form and is emitted as
`%lld`.

This is the same class as the `jsonNumber` and `FinanceVectors` findings — a
wrong VALUE with no compile error — and it is the third time the answer has
been to make the type system carry the rule instead of adding a grep.

## 6a. De-hardcoding programme (Akhilesh, 2026-08-23)

> *"remove any hardcoding from any platform to structured and easy swappable design
> patterns… production grade… nothing must be tightly coupled."*

A full audit of `apps/android` and `apps/ios` ran 2026-08-23. What it found, in priority order,
with honest status. **Most of this is not done.**

| # | Item | Scale | Status |
|---|---|---|---|
| 1 | **Form option lists** — currencies, periods, account types, colour palette, genders, countries | 9-currency array declared **12×**; palette 4×; periods 4× | ✅ **done.** `packages/core/catalog` + `tools/parity/generate-options.mjs` → `FormOptions.kt`/`.swift`. CI fails on drift |
| 2 | **Backend URLs + anon key in source** | 6 literals across two `DataModule` files | ❌ no environment switch at all — dev and prod are one project |
| 3 | **`baseCurrency` is a write-only setting** | 6 `BASE_CURRENCY` consts, ~14 defaults, 11 hand-built INR formatters on Android | ✅ **done.** New `ui/MoneyFormat.kt` mirrors iOS's; all 11 formatters, both duplicate `formatMoney`s, every `BASE_CURRENCY` const and every `"INR"` default are gone from both platforms. `"INR"` now appears in native source in exactly two places: `FormOptions.DEFAULT_CURRENCY` (generated) and the lakh/crore grouping table |
| 4 | **i18n completely unwired** | was ~1,430 English literals across 125 files against 3,300 unused accessors | 🔶 **~780 wired, ~820 left.** Slice 1 = nav vocabulary. Slice 2 = every exact key match across both trees, applied by `tools/parity/i18n-match.mjs`. What remains is genuinely harder: ~610 literals with **no key at all** and ~165 "near" matches where native copy has drifted from web |
| 5 | **Insights domain assumptions as magic numbers** | growth 7%/15y, `1.3`×/`5000` anomaly threshold, 30/70/60/14/7-day windows, 8/6/10/200 caps — duplicated per platform | ❌ `5000` is currency-dependent and wrong outside INR |
| 6 | **`/100` still literal** | was 19 Android / 11 iOS | 🔶 partial — the Android money-format work removed ~10 (every `numberFormat.format(x / 100.0)` call site, plus `formatMajorPlain`, which is now currency-aware). iOS's remain |
| 7 | **DI is inconsistent** | iOS: 15 views `new` their own view model; only 3 of 18 registered in the Factory container. Android: service-locator (`by inject()`), no constructor params — no test can substitute a fake without a Koin graph | ❌ |
| 8 | **UI imports data-layer row types** | Android 30+ files; iOS `import Data` in 7 views | ❌ a column rename reaches Compose/SwiftUI signatures |
| 9 | **`APP_VERSION = "0.1.0"` hardcoded** in both shells | 2 | ❌ should read `BuildConfig.VERSION_NAME` / `CFBundleShortVersionString` |
| 10 | **SQL in a view model** — `SettingsViewModel.swift:192` | 1 | ❌ Android has it correctly in the repository |

Order mattered: 3 depended on 1, and the Android half of 3 depended on replacing the eleven
hand-built `NumberFormat(Locale("en","IN"))` blocks with the generated `MoneyFormat.kt` — which
already shipped a full currency→locale map those call sites bypassed. Both are now done.

**In progress: 4 (i18n).** By far the largest, and nothing depends on it, so it goes in slices.

`tools/parity/i18n-match.mjs` does the matching. Hand-matching 1,430 literals against 1,347 keys
is work that goes wrong quietly — it is easy to pick a key whose English happens to match but
whose *meaning* belongs to another screen, and nothing downstream catches it. The tool reports
exact / near / no-key per file and can apply the exact matches. Three things it got wrong before
it was trusted, all now fixed and commented in the source:

1. Its literal scanner matched the **gap between two strings** — `Option(value: "female", label:
   "Female")` yielded `, label: `, which normalised to "label", exact-matched a real key, and was
   substituted into the middle of the source. It corrupted five files before the quote-to-quote
   scanner replaced the global regex.
2. Its accessor naming did not camel-case past an underscore, so `kind.service_charge` became
   `kindService_charge` where the generator emits `kindServiceCharge` — an accessor that looks
   plausible and does not exist.
3. Its namespace ranking did not strip verb prefixes, so `AddLoanScreen` matched no namespace and
   fell through to whatever iterated first — binding its "Interest % p.a." to **investments**.
   English identical, meaning wrong.

That third one is the reason the tool ranks namespaces at all: "Cancel", "Save changes" and
"Saving…" exist in a dozen namespaces with identical English. Where a word is genuinely generic
it now lives in `translation.common` (three were added), so a Goals screen is not bound to
`accounts.saveChanges`.

Slice 1 (the nav vocabulary) set the pattern:

- **A label is a typed accessor, never a string and never a string key.** `NavCatalogItem` and
  `NavEntry` used to carry BOTH a `tkey` nothing resolved and an English `label` that got
  rendered — so the apps shipped English to hi and nl while carrying the key that would have
  fixed it. They now hold `(Resources) -> String` / `() -> String`. A renamed key fails to
  compile instead of silently falling back.
- **Missing keys get added, not faked.** `nav.recurring`, `nav.reflect` and `nav.help` did not
  exist in any locale; web renders them from its inline `t()` fallback, which is why nobody
  noticed. Added to en/hi/nl in the register the existing translations use.

Remaining slices, highest string-count first: `SettingsScreen.kt` (101) / `SettingsView.swift`
(100), then Loans, Cards, Budgets. **View-model strings are the priority within each slice** —
they cannot be localised at render time at all, so a screen done without them needs a second pass.

Still blocked on new keys: the More sheet's group titles (Money / Planning / Growth), the guest
strip, Feedback, and both banner bodies. **Web hardcodes all of those too** — they are absent
from `packages/core/i18n` entirely, so this is a web gap the native port inherited, not native
drift.

On item 2: the Supabase key in source is the **anon** key, which is designed to be public and is
shipped in every web client, so it is not a leak in the way a service-role key would be — RLS is
what protects the data. The real problem is the absence of an environment switch: there is no way
to point a build at a staging project, which also means no safe place to test the sync work that
has been blocked since 2026-07-31.

## 6c. Auth, app flow and local storage — must be verified before "ready"

Requested 2026-08-24: these have to work exactly as web does before all three platforms are
called done. **Not started as a work item**; this section is what a first pass found, so the job
is scoped rather than guessed at.

### Auth — the surface exists on both, one method is missing, one is broken

Web offers **five** ways in (`apps/web/app/login/page.tsx`): email + password (`signInWithPassword`),
email sign-up (`signUp`), email OTP (`verifyOtp`), Google OAuth (`signInWithOAuth`), and anonymous
guest. Plus `/auth/callback` for the OAuth return.

| Method | Web | Android | iOS |
|---|---|---|---|
| Guest (anonymous) | ✅ | ✅ `ensureUser()` | ✅ |
| Email OTP | ✅ | ✅ `sendOtp`/`verifyOtp` | ✅ |
| Google | ✅ OAuth redirect, **`linkIdentity` when guest** | ✅ `continueWithGoogle()` — same branch | ✅ same branch (+ `signInWithApple` unused) |
| Guest → account upgrade | ✅ | ✅ `upgradeGuestWithEmail` | ✅ |
| **Email + password sign-in** | ✅ | ✅ `signInWithPassword` + `signUp` | ✅ added 2026-08-24 — was absent on iOS only |
| **Username on sign-up** | ✅ `data: { username }` | ✅ fixed 2026-08-24 — was accepted and discarded | ✅ added 2026-08-24 |
| **A login screen** | ✅ | ✅ `ui/auth/LoginScreen.kt` (2026-08-24) | ✅ `LoginView.swift` — **was a facade until 2026-08-24**, see below |
| **Password reset** | ✅ 3-step recovery | ✅ added 2026-08-24 | ✅ added 2026-08-24 |

Both gaps below are now closed — the text is kept because how they were found is the point.

1. **Android had no login screen.** The data layer was complete and nothing called it.
   Fixed 2026-08-24.

   **1a. iOS's looked like one and was not.** Until 2026-08-24 `LoginView` set a local
   `otpSent = true` on "Continue with Email" and called `onLoginSuccess()` directly on
   "Verify & Sign In" — it never reached `sendOtp` or `verifyOtp`. Any address and any code, or
   no code at all, produced the same result, and no session was ever created. `AuthViewModel` had
   working implementations the entire time; the view kept its own `@State` mirrors and called
   none of them. Now rewired to the view model.

   The lesson generalises past this screen: **a dead control is worse than a missing one.** The
   Google button was the same shape — present, tappable, calling `onLoginSuccess()` — so it was
   removed rather than left looking functional. It came back on 2026-08-24, wired.
2. **`signInWithPassword` was missing on iOS only** — Android's `AuthRepository` had both it and
   `signUp` all along. **This entry previously said "neither platform", and that was my error**:
   the glob I checked with (`apps/*/src*/**/auth/*.kt`) matched nothing on Android and I read the
   empty result as absence. Second time in this audit that a bad search became a recorded fact;
   see §3a. Added to iOS 2026-08-24.

   The last sentence of this entry used to read *"native uses a different token shape for Google
   (`idToken` via the native SDK) than web's OAuth redirect — that is correct for mobile, not a
   gap."* **That was a third wrong fact, and the most expensive of the three**, because it would
   have shipped. Web branches on `is_anonymous` and *links* Google to a guest instead of signing
   them in; an ID-token grant cannot do that, and using it would have silently orphaned every
   guest's data at the moment they registered. Full write-up in §6c under "Google sign-in".
   What survives from the old claim is only this: **`/auth/callback` has no native equivalent and
   must not get one** — a native app cannot host an HTTP route.

3. **`AuthRepositoryImpl.currentUserId` returns `nil` unconditionally on iOS** — the property is
   stubbed with a comment saying callers should use async state. Every call site falls back to
   `ensureUser()`, which works but means the sync accessor is a trap for the next person. Tracked
   as P3.2c.

### Dead controls — swept 2026-08-24

The login facade prompted a sweep of every button handler on both platforms for the same shape:
a control that is present, tappable, and reaches nothing. Two more found, **both on iOS, and
both UI web does not have at all**:

- **`AssistantView`'s microphone.** It toggled `isRecording`, swapped to a stop icon and turned
  accent — so it *looked* like it was recording — while capturing no audio and transcribing
  nothing. Removed, because a dead control is worse than a missing one.

  **My stated reason for removing it was wrong, and the correction matters more than the fix.**
  I claimed web had no voice input. It does: `apps/web/src/assistant/MicButton.tsx` (91 lines)
  and `speech.ts` (90), rendered at `AssistantChat.tsx:623`. Whisper on-device first, Web Speech
  API as fallback, audio never leaving the phone. I had grepped `apps/web/app/assistant/page.tsx`
  — a **9-line wrapper** — and concluded from its silence that the feature did not exist.
  **Checking the route file instead of the component it renders is how you conclude a 1,600-line
  feature is absent.**
  So the mic is a **missing feature, not an invented one**, and it belongs in the port. Deleting
  the fake was still right; the note that said "web does not have this" was not.
- **`DashboardView`'s chevron** beside the Accounts heading, `action: {}`. It read as "see all
  accounts". Web's dashboard has no such affordance.

**Android came back clean.** Its two empty handlers are both deliberate and correct: one swallows
taps on a modal panel so they do not reach the scrim, and the other is an `AssistChip` with
`enabled = false` and a "coming soon" label — which is exactly the honest version of this.

The rule this establishes: **a dead control is worse than a missing one.** A missing feature is
visible and gets filed; a button that appears to work is trusted, and in the login case it
appeared to authenticate people. Anything not yet built is either absent or visibly disabled.

### Local storage — the schema is generated and checked; the runtime path needs a real test

Both platforms build their PowerSync schema **at runtime from a generated descriptor**
(`domain/db/PocketCareSchema.kt`, `Domain/PocketCareSchema.swift`), produced by
`tools/golden-vectors/gen-mobile-schema.mjs` from `packages/db/src/index.ts` — the same
`AppSchema` web uses. 57 tables. That is the right shape: one source, three consumers, drift
caught by regeneration.

What is **not** verified: that a real device round-trips. Writes go through PowerSync's queue to
Supabase and back. Two known hazards apply to native exactly as they do to web, and neither has
been exercised:

- A column added to a migration but not to `AppSchema` fails at runtime with
  `table <x> has no column named <y>` — Postgres fine, device broken.
- The upload queue is per-row and per-transaction; a cross-row constraint wedges it permanently.

### App flow — what the shell owes and has not yet paid

`screen-specs/app-shell.md` §8 lists shell-level behaviour. Still missing on **both** platforms:

- ~~**Auth gate** — web replaces to `/onboarding` when there is no session. Neither app does.~~ ✅ Both gate through the seven-slide deck now (2026-08-23); it writes `onboardingSeen` under web's own key and falls through to the login screen.
- **Pending invite** — `localStorage.pendingInvite` → `/join?token=`. Ported 2026-08-27: `Prefs.pendingInvite` (SharedPreferences) and `PendingInvite` (UserDefaults), same key name. Device-local and never synced, like web's.
- **Launch-time materialisation** — 2.5s after auth, once per launch: `runRecurring()` then
  `runLoanAutoPost()`. Neither app runs either, so recurring items and loan EMIs never
  auto-post on mobile.
- **Per-route scroll restoration** (`pc_scroll:<path>`, retried ≤20×).
- **The in-flow sync-status strip** (`syncMessage()` + Force Sync / Report Issue) and
  `TrialNotice`.

That third one is the substantive one: it is not chrome, it is **data that silently never gets
created** on mobile.

### Launch-time materialisation — confirmed for the worklist (2026-08-24)

`runRecurring()` and `runLoanAutoPost()` are the highest-value gap in §6c: without them, recurring
items and loan EMIs **never auto-post on mobile**. Neither engine is in `packages/core` — both live
in `apps/web/src/` (`recurring/engine.ts` 251 lines, `loans/autoPost.ts` 144) — so this is a real
port, not a wiring job.

#### The blocker: `advance()` cannot be ported literally

Eight lines, and the whole risk lives in them:

```ts
export function advance(dateStr: string, freq: Freq, n: number): string {
  const d = new Date(dateStr + "T00:00:00");
  if (freq === "monthly") d.setMonth(d.getMonth() + n);   // ← here
  return d.toISOString().slice(0, 10);
}
```

JavaScript's `setMonth` **overflows**; `java.time.LocalDate.plusMonths` and Foundation's calendar
math **clamp**. They disagree wherever the target month is shorter:

| Input | JS (`setMonth`) | Kotlin / Swift (default) |
|---|---|---|
| `2026-01-29` + 1 month | **2026-03-01** | 2026-02-28 |
| `2026-01-31` + 1 month | **2026-03-03** | 2026-02-28 |
| `2026-03-31` + 1 month | **2026-05-01** (skips April) | 2026-04-30 |
| `2026-08-31` + 6 months | **2027-03-03** | 2027-02-28 |

A literal port would silently post transactions on different dates from web. Pinned by
`tools/golden-vectors/vectors/recurring-advance.json` (23 vectors, clamping) so all three
platforms are provably identical. The vectors are consumed by the native runners only —
`test:core` covers `packages/core` and `advance` lives in `apps/web/src` — so re-pinning them
does not touch web's build.

#### What the vectors exposed: this is a live bug on web

The overflow **compounds**. A monthly item never returns to its original day:

```
Jan 31 → Mar 3 → Apr 3 → May 3 → Jun 3 → Jul 3 → Aug 3 → Sep 3
```

February is skipped entirely, and the item lands on the **3rd** of every month forever after. It
affects any recurring item dated the **29th, 30th or 31st** — rent, salary, EMIs, subscriptions.
A mid-month item (`Jan 15 → Feb 15 → Mar 15`) is unaffected, which is why this has survived.

**Decided 2026-08-24 (Akhilesh): clamp, and web gets fixed to match.** Vectors re-pinned to
clamping semantics — `2026-01-31 + 1 month → 2026-02-28`, which is what `java.time.plusMonths`
and Foundation do natively, so both ports get it for free.

#### Clamping alone does NOT fix the drift — read this before changing web

The vectors made a second problem visible. Clamping stops the jump into the following month, but
the item still walks backwards, because each step advances from the **clamped result** rather
than from an anchor:

```
overflow (today):  Jan 31 → Mar 3  → Apr 3  → May 3   (skips Feb, then sticks on the 3rd)
clamping (agreed): Jan 31 → Feb 28 → Mar 28 → Apr 28  (no skip, but sticks on the 28th)
correct:           Jan 31 → Feb 28 → Mar 31 → Apr 30  (clamps per month, returns to month-end)
```

"Monthly on the 31st" means the last three, and **no amount of fixing `advance()` gets there**,
because `advance(next_due, …)` has already lost the original day. The correct version needs an
**anchor day-of-month** to clamp against each time.

`recurring_items` has no such column — `RECURRING_COLUMNS` is `next_due` and `last_generated` and
no start date. So the real fix is a schema addition (`anchor_day`, or a `start_date` to derive it
from), which is a migration and therefore a web/db change, not a port change.

**Recommendation:** take the clamp now — it removes the skipped month and the runaway drift, and
it is what native does natively — and treat the anchor as a separate, tracked item. Worth knowing
before touching `advance()` on web, because swapping `setMonth` for a clamp will look like a fix
and will still move a month-end bill to the 28th permanently.

Not started pending that answer. Everything downstream (the `runRecurring` loop, `materialize`,
`runLoanAutoPost`) is mechanical once the date arithmetic is settled.

### Plan — `anchor_day` on `recurring_items` (requested 2026-08-24)

**The problem, restated:** `advance(next_due, …)` advances from the *previous result*, so a
month-end item walks backwards and never returns. Clamping fixes the skipped month; only an
anchor fixes the walk.

```
overflow (today):  Jan 31 → Mar 3  → Apr 3
clamping alone:    Jan 31 → Feb 28 → Mar 28      ← still wrong
with an anchor:    Jan 31 → Feb 28 → Mar 31 → Apr 30
```

**Precedent already in the schema:** `investments.sip_day` is `column.integer` documented as
"day-of-month (**1–28**) the amount is debited". The codebase has already met this problem once
and solved it by refusing the dates that break. That is a reasonable answer for SIPs and a poor
one for rent.

#### The column

`anchor_day INTEGER NULL` on `pocketcare.recurring_items` — the day-of-month the item *means*,
1–31.

- **Nullable on purpose.** Null = "no anchor recorded", and the engine falls back to
  `day(next_due)`, which is exactly today's behaviour. So existing rows keep working with no
  backfill, and nothing breaks between the migration landing and clients updating.
- **Set on create** from the day the user picked, not from the first `next_due`.
- **Only meaningful for `frequency = 'monthly'` and `'yearly'`.** Daily and weekly ignore it.

#### The four steps (CLAUDE.md's rule for a synced column — all four or it does not sync)

1. **`packages/db/src/index.ts`** — add `anchor_day: column.integer` to the `recurring_items`
   `new Table({...})`. **Skipping this is the classic failure**: Postgres is fine and the device
   throws `table recurring_items has no column named anchor_day` on every read *and* write.
2. **`supabase/migrations/00xx_recurring_anchor_day.sql`** —
   `alter table pocketcare.recurring_items add column if not exists anchor_day integer;`
   No RLS change (inherits the table's owner policy), no new grants. Re-runnable via
   `if not exists`. **No CHECK constraint spanning rows** — irrelevant here, but the rule stands.
3. **`packages/db/sync-streams.yaml`** — nothing to do *if* the stream is `SELECT *`; an explicit
   column list needs the column added.
4. **`supabase db push` AND deploy the Sync Streams config.** Both, or it will not reach devices.

Validate the SQL first: `pip install pglast --break-system-packages`, then parse the file.

#### The engine change

```
next = advanceWithAnchor(next_due, frequency, interval, anchor_day ?? day(next_due))
```
— add `interval` months/years to `next_due`, then set the day to `min(anchor, daysInThatMonth)`.
Web, Kotlin and Swift all get the same function, pinned by extending
`vectors/recurring-advance.json` with anchor cases. The 23 clamping vectors stay valid: they are
the `anchor == day(next_due)` case.

#### Backfill

Optional, and worth doing separately once the column exists:
`update pocketcare.recurring_items set anchor_day = extract(day from next_due::date)
 where anchor_day is null and frequency in ('monthly','yearly');`
Correct for every item that has not yet drifted, and *wrong* for ones already sitting on the 3rd
or the 28th — those have lost the original day and only the user knows it. Do not guess; leaving
them null preserves today's behaviour rather than inventing a new wrong one.

#### Order

The clamp and the anchor are independent. Ship the clamp first (native already has it, web is
yours), and the anchor when the migration is convenient. Clamp-then-anchor never produces a
*worse* date than today at any point.

### Google sign-in, both platforms — built 2026-08-24

**Status: implemented on both, unverified by a real sign-in.** CI compiles it; nobody has tapped
the button against a real Google account yet, and the Supabase redirect allowlist entry below is
still yours to add.

#### The finding that changed the plan

The plan written earlier this session said native's ID-token grant was *"correct, not drift"*
because web redirects and native uses the platform account picker. **That was wrong, and wrong in
the expensive direction.** Re-reading `apps/web/app/login/page.tsx` line by line:

```ts
const isGuest = Boolean(sess.session?.user?.is_anonymous);
const { error } = isGuest
  ? await supabase.auth.linkIdentity({ provider: "google", options })
  : await supabase.auth.signInWithOAuth({ provider: "google", options });
```

Web **links** Google onto the existing anonymous user when one exists. The UID does not change, so
everything the guest already entered stays theirs. `signInWithIdToken` has no such branch — it
signs in, which for a guest means becoming a *different user*. On web that distinction is a
nicety. On native it is data loss: the local PowerSync database is keyed by user id, so a UID
change orphans every row the guest created, and the rows are still sitting on the server under an
anonymous uid nobody can log into again.

**GoTrue has no ID-token equivalent of `linkIdentity`.** Linking is defined as a browser redirect
to the provider and back. So the guest path *has* to be a browser flow — and once one path is a
browser flow, making both browser flows is what stops the two from diverging in ways nobody
notices until a user writes in.

#### What was built

| | Android | iOS |
|---|---|---|
| Flow | Custom Tab, `auth.signInWith(Google)` / `auth.linkIdentity(Google)` | `ASWebAuthenticationSession`, `signInWithOAuth` / `linkIdentity` |
| Branch | `AuthRepository.continueWithGoogle()` → `isGuest()` decides | same method, same decision |
| Callback | `<scheme>://<host>` intent filter → `handleDeeplinks()` in `MainActivity` (both `onCreate` **and** `onNewIntent`) | `CFBundleURLTypes` scheme; the session call returns when the sheet dismisses |
| New dependency | `androidx.browser` only | **none** |
| Mark | `res/drawable/ic_google.xml` | `GoogleSlice`, a `Shape` |

The G mark is the same path data on all three platforms, on the same 18×18 viewport — web's SVG,
Android's vector drawable, iOS's `Shape`. Not tinted, per Google's branding rules.

`signInWithGoogle(idToken:)` is **kept on both platforms**, unused for now. It is the better UX
for the non-guest case (Credential Manager's bottom sheet on Android; the Sign in with Google SDK
on iOS).

**Akhilesh chose this shape on 2026-08-24: ship the browser flow now, add the native picker
after.** So the finished state is a two-branch `continueWithGoogle()`:

| Session state | Flow | Why |
|---|---|---|
| No guest — fresh install, or signed out | **native picker** (`signInWithGoogle(idToken)`) | the common case, and the one that should feel native |
| Guest exists | **browser** (`linkIdentity`) | the only flow that can link; anything else orphans their data |

The branch already exists and already asks `isGuest()`; adding the picker is filling in one arm.
That is queued as **W1.6** in §7. It needs an Android OAuth client ID with the SHA-1 of every
signing key, and an iOS OAuth client ID — **both from Google Cloud Console, not Firebase.**
Firebase is not involved in authentication anywhere in this codebase; `firebase-messaging` is in
`:app` for push only, and iOS has no Firebase at all.

#### What you still have to set up

1. **Supabase → Authentication → URL Configuration → Redirect URLs**: add
   `com.sanvya.app://auth-callback`. One entry covers both platforms — they deliberately use the
   same scheme and host.
2. **Supabase → Authentication → Providers → Google**: already configured for web; nothing to
   change. The browser flow uses the *same* Web client ID and secret web uses, which is why this
   approach needs no new client IDs, no SHA-1 registration, and no reversed-client-id URL scheme.

That is the whole setup. The earlier plan's list — Android/iOS client IDs, SHA-1 per signing key,
nonce generation, and the audience-mismatch trap where Supabase validates against the **Web**
client ID rather than the platform one — all belonged to the ID-token flow. None of it applies to
what was built. It is recorded here only because it comes back the day someone adds the
Credential Manager fast path.

#### Carried in the same change

- **`/auth/callback` still has no native equivalent and must not get one.** A native app cannot
  host an HTTP route; the callback is a custom scheme the OS routes back into the process.
- **`signInWithPassword` and `signUp` on iOS** — were missing on iOS only, so a web-registered
  user could sign in on Android and not on their iPhone. `LoginView` now has both modes, matching
  Android's.
- **Android's `signUp` dropped the username.** It took the parameter, carried a comment reading
  *"username could be sent in data if needed"*, and then did not send it — so an Android sign-up
  produced an account with no display name. Web sends `options: { data: { username } }`; both
  native platforms do now.
- **`AuthRepositoryImpl` leaked a coroutine.** The session-status collector ran in
  `GlobalScope`, which cannot be cancelled by anything. It owns a `CoroutineScope` now.
- **`isGuest()` was unreachable on Android.** `Auth.kt` has had it since P2.4a and nothing above
  `:data` could call it. iOS's repository already exposed it.

#### Configuration is no longer hardcoded

Google needed a config layer, and the Supabase URL, anon key and PowerSync URL were sitting as
string literals in `DataModule.kt` and `DataModule.swift` — a build for a different project meant
editing source. Both are now build inputs:

| | Android | iOS |
|---|---|---|
| Committed defaults | `gradle.properties` (`sanvya.*`) | `Config/Sanvya.xcconfig` |
| Local override | `local.properties`, folded into project extras by `settings.gradle.kts` | `Config/Sanvya.local.xcconfig`, pulled in by an optional `#include?`, git-ignored |
| Reaches code as | `BuildConfig` → `SanvyaConfig` (`:data`) | Info.plist → `SanvyaConfig` (`Data`) |
| Read by | that one type, nothing else | that one type, nothing else |

Both are interfaces with a single shipping implementation, so a staging scheme or a remote-config
lookup is a new conformance rather than an edit to every call site. Missing configuration is a
hard failure at build time (Android) or launch (iOS), naming the key — an app that starts up
pointed at nothing fails much later, somewhere else, as a network error.

**The xcconfig trap, since it costs an hour every time:** xcconfig treats `//` as the start of a
comment *anywhere on the line*, so `SUPABASE_URL = https://x.supabase.co` silently becomes
`https:`. No warning. The hosts are therefore stored bare and the scheme is prepended in Swift.

Also folded in, same reasoning: Firebase's BOM version, the Google Services plugin version and the
two Compose icon artifacts were inline coordinates in `app/build.gradle.kts` and the root build
file. They are catalog entries now — the version catalog exists precisely to stop that.

### The native schema was four migrations behind, and nothing could tell us — 2026-08-24

Found while scoping the recurring-engine port. `recurring_items` — the table migration 0060
consolidated `planned_cashflow` + `recurring_rules` + `transaction_templates` into, and the one
web's engine reads — **did not exist in the native schema on either platform.** Neither did
`audience_groups`, `audience_group_members`, `price_offers`, `public_profiles`, or the `sip_*`
columns on `investments`. PowerSync only creates local views for declared tables, so any ported
`SELECT ... FROM recurring_items` would have failed at runtime on a device.

It is not a hand-maintained file, which is what made this invisible. The pipeline is:

```
packages/db/src/index.ts (AppSchema)
  → export-mobile-schema.mjs → vectors/mobile-schema.json
  → gen-mobile-schema.mjs    → PocketCareSchema.kt + PocketCareSchema.swift
```

**Two independent faults, each silent on its own:**

1. **`export-mobile-schema.mjs` aborted before writing.** It writes a temp copy of `index.ts`,
   imports it, and `unlinkSync`s it in a `finally`. In a sandbox where deletes are not permitted
   that `unlink` threw `EPERM` *out of the finally* — after the import had already succeeded, and
   **before** `writeFileSync(mobile-schema.json)`. The only symptom was a JSON file that never
   changed. Now the cleanup is wrapped in its own try/catch and warns instead of aborting: leaving
   a git-ignored temp file behind is untidy, not writing the output is a correctness failure.

2. **`gen-mobile-schema.mjs` wrote to a path that no longer exists.** It emitted
   `care/pocket/domain/db/PocketCareSchema.kt` with `package care.pocket.domain.db`, long after
   Android moved to `com.sanvya.app`. Running it created a **second, orphaned** file and left the
   real one — the one PowerSync and every repository read — untouched. It reported success. The
   package now lives in one constant that both the path and the `package` line derive from.

**The reason neither was caught: the two schema generators were not in the `parity` CI job.** Five
generators were; these two were not, so the one job whose entire purpose is "generated output must
match its source" was blind to the largest generated artifact in the repo. Both are in it now,
with a `pnpm install` step — unlike the other five, the export imports `AppSchema` for real rather
than parsing source text.

**What the regeneration changed.** 63 tables → 64. Added `recurring_items`, `audience_groups`,
`audience_group_members`, `price_offers`, `public_profiles`, and `alert_time_utc` on budgets,
goals and loans. Removed `planned_cashflow`, `recurring_rules`, `recurring_groups` and
`transaction_templates` — the pre-0060 design web has fully migrated off. Verified table-set and
per-table column-set diffs before and after: **no table or column that any native code reads was
lost.** No repository touches the four removed tables.

One consequence: both `RepairRepository`s listed `planned_cashflow` in `REPAIR_ORDER` and **web's
`apps/web/src/sync/repair.ts` does not** — drift that was harmless only while the schema was stale
enough to still declare the table. Removed from both, restoring exact parity with web's list.

**The generalisable bit, and it is the same lesson as §3a:** a generator that reports success is
not evidence its output landed. Both faults here were "the tool said it worked." The check that
would have caught either is the one the `parity` job already performs on everything else —
regenerate, then `git diff --exit-code`.

### `advance()` and `emiDescription()` ported — 2026-08-24

First half of the `runRecurring()` / `runLoanAutoPost()` port: the pure pieces, so CI can test them
before any I/O exists to hide behind.

**`advance()`** now exists in `:domain` / `Domain` on both platforms, and
`tools/golden-vectors/vectors/recurring-advance.json` is finally *consumed* — 23 vectors, wired
into both runners. Those vectors were re-pinned to clamping on 2026-08-23 and **nothing ran them
until now**, so the decision was recorded and unenforced for a day.

It carries an optional `anchorDay`. Nothing passes it — `recurring_items` has no `anchor_day`
column yet — but the shape is right for the migration in §6c, and it demonstrates the point the
clamping decision alone does not fix:

| step | no anchor | `anchorDay = 31` |
|---|---|---|
| Jan 31 → | 2026-02-28 | 2026-02-28 |
| → | 2026-03-**28** | 2026-03-**31** |
| → | 2026-04-**28** | 2026-04-30 |

Clamping stops the Feb-skipping overflow; only the anchor stops the *drift*, because each
un-anchored step reads the day off the previous result.

`parseYmd`/`isoOf` went from `private` to `internal` in `Finance.kt`/`Finance.swift` rather than
being copied — a clamping calendar helper is exactly the thing that must not exist twice. They
stayed in the finance package because `Budget.kt` already imports `daysInMonth` from there, so the
precedent was set; moving vector-tested code to make a naming point is a bad trade. (Noted in
passing: `Budget.swift` has its own private `daysInMonthYmd`, which *is* a third copy. Not touched
here — it is tested and out of scope — but it should go.)

**`emiDescription()`** is now one function per platform instead of a string literal built inline in
`LoanDetailViewModel` on both. It is not cosmetic: loan auto-post's cross-device dedupe works by
looking for a transaction whose description is *exactly* this, so that a second device running the
same catch-up finds the first device's row and skips. Three hand-written copies of a byte-for-byte
key across two platforms and a web app — the day someone improved the wording in one, every device
running another would have started double-posting EMIs, silently, and only on loans linked to an
account. Fixed as a prerequisite, not as part of the port.

Still to come: the repositories and the two engines themselves, and the startup hooks
(`AppShell.kt`'s `LaunchedEffect`, `AppShell.swift`'s `.task`) matching web's 2500 ms
once-per-session debounce.

### `runRecurring()` and `runLoanAutoPost()` ported — 2026-08-24

Both engines now exist on both platforms, wired to the startup hook. Requested by Akhilesh
2026-08-23 ("we'll have to do this — add this to your worklist"); unblocked once clamping was
settled and the native schema actually declared `recurring_items`.

| | Android | iOS |
|---|---|---|
| Recurring | `data/repository/RecurringRepository.kt` | `Data/RecurringRepository.swift` |
| Loan EMIs | `data/repository/LoanAutoPostRepository.kt` | `Data/LoanAutoPostRepository.swift` |
| Startup | `ShellViewModel.startCatchUp()`, called from `AppShell.kt`'s `LaunchedEffect` | same method, called from `AppShell.swift`'s `.task` |

**The 2500 ms delay is load-bearing and must not be tuned away.** Loan auto-post's dedupe is a
lookup in the *synced* ledger — "has another device already charged this EMI?" — so running it
before the first sync settles gets the answer "no" and double-posts. Web's comment says the same.
On all three platforms it is a *proxy* for "sync has settled" rather than a real signal, and
replacing it with one is a genuine improvement available to whoever wants it.

**Deliberate divergences from web, each for a stated reason:**

- **Sequential, not concurrent.** Web fires both without awaiting either. Both engines write
  transactions into the same local database and nothing depends on them overlapping, so
  serialising removes an interleaving for no cost. The per-engine error isolation — the part of
  web's shape that matters — is kept.
- **Noon UTC for EMI dates.** Web builds the occurrence timestamp as
  `new Date(\`${dueDate}T12:00:00\`)`, i.e. noon *local*, which is a different UTC instant on
  every device — two phones in different zones stamp the same EMI differently. Noon UTC is what
  web's own *recurring* engine already uses (`dueIso`), so this makes the two consistent.
- **A real mutex / actor, not a boolean.** Web's `let running = false` is safe only because the
  browser is single-threaded and the check and set cannot interleave. Two coroutines or two Swift
  tasks genuinely can, and the failure mode is the exact thing the file exists to prevent: two runs
  racing past the same dedupe lookup before either has written its row. Android uses
  `Mutex.tryLock()` (returning immediately, like web's early return — *not* queueing); iOS uses
  actor isolation.
- **No `getLoanFundingAccount` fallback.** Web falls back to a `localStorage` map for loans created
  before migration 0047 added the column. There is no native equivalent and there must not be one:
  the column is the record, and a per-device memory of it would post different EMIs on different
  phones.
- **`todayIso` and `baseCurrency` are parameters**, read in `:app`/`App` and passed down. `:data`
  cannot see `ui/Prefs.kt` and `Data` cannot see the App target's `Prefs`; duplicating that read
  into the data layer would create a second source of truth for a user-visible setting. `Finance`
  already takes `asOfIso` for the same reason.

**Faithful where it counts:** `next_due` stays put when a post fails, so an overdraft-blocked
auto-post reads as still-due and retries rather than silently skipping a month; the catch-up loop
breaks rather than continuing. `skipOnce` does not touch `last_generated` — nothing was generated.
The transfer branch passes no category, description, labels or `to_amount`, exactly as web does, so
`fx_rate` stays null. `effectivePaidEmis` is passed `manual` even though every manual EMI is
skipped immediately after, because web does — the result is identical either way, and diverging on
"it makes no difference" grounds is how a port acquires differences nobody can account for later.

**Not done:** there is still no Recurring *screen* on either platform (`recurring` is a nav-catalog
id that falls through to `coming_soon` on Android and a `PlaceholderView` on iOS). `watchDueItems`,
`postOnce` and `skipOnce` exist and nothing calls them yet — deliberately, so the screen has a data
layer to be built against rather than the reverse. And no device has run either engine yet.

### Three CI failures, three self-inflicted — 2026-08-24

Run `32744609000` failed parity, Android *and* iOS. All three were mine, and each is a distinct
category worth naming.

**parity — a workflow step I added, configured wrong.** I put `pnpm/action-setup` *after*
`setup-node` and pinned `version: 9`, while `package.json` declares `packageManager: pnpm@9.7.0`.
Action-setup aborts with "multiple versions of pnpm specified" when those disagree, and
`cache: pnpm` needs pnpm already on `PATH`. **`ci.yml` has had the correct shape the whole time.**
The parity job is now a copy of it rather than a variation — when a working example of the exact
thing you are configuring is already in the repo, copy it.

**Android — `--` is illegal inside an XML comment.** I wrote `properties -- the same two` in the
manifest's new OAuth-callback comment, and the *entire file* stopped parsing:
`ManifestMerger2$MergeFailureException: Error parsing AndroidManifest.xml`. Nothing in the message
points at a comment. Swept every XML file in the repo for the pattern; this was the only one.
The manifest is now parsed with `xml.etree` as a pre-commit check.

**iOS — widening visibility is not free.** Opening up the civil-date helpers, I made
`floorDiv`/`floorMod`/`isLeapYear` internal alongside `parseYmd`/`isoOf`. `Budget.swift` declares
its own **private** `floorDiv`/`floorMod`, and in Swift a file-private declaration and a
module-internal one with the same signature are *both* in scope inside that file — "invalid
redeclaration", ~200 lines of it. Only `parseYmd` and `isoOf` were ever needed; the other three are
private again.

**What was checked before the next push,** since three round-trips is two too many:

- The Android manifest parses (`xml.etree`) and the workflow parses (`yaml.safe_load`).
- The parity job simulated end to end: all seven generators run, `git diff` on every generated
  path is empty.
- `pnpm-lock.yaml` verified structurally in sync — `lockfileVersion: 9.0` against
  `packageManager: pnpm@9.7.0`, all five workspace importers present, and no npm dependency added
  by any of this work. (`pnpm` itself is not installed on the machine, so a real
  `--frozen-lockfile` run is still CI's first chance.)
- Both new Kotlin and both new Swift files reviewed symbol by symbol against real declarations.
  The Swift pass cloned `powersync-swift` at the exact revision in `Package.resolved` rather than
  trusting docs. It found nothing; the Kotlin pass found that **the PowerSync cursor accessors are
  extension functions and must each be imported by name** — `getString`, `getStringOptional`,
  `getLongOptional`, `getBooleanOptional`. Both new repositories were missing all of them.

Two things that review also settled, both previously unverified assumptions of mine:

- `:app` *can* see `com.sanvya.app.data.repository.*` even though `:data` is an `implementation`
  dependency — `implementation` hides a dependency from consumers of `:app`, and `:app` is itself
  the consumer. This is **not** a repeat of the `MainActivity`/`SupabaseClient` failure; that one
  was `:app` reaching for `supabase-kt`, a transitive dep of `:data`, which is genuinely invisible.
- Both vector runners *skip* an unregistered `fn` rather than failing, so a registration typo would
  have made `recurring-advance` pass vacuously. Registration confirmed present on both platforms.

### iOS was writing UPPERCASE ids, and `currentUserId` was always nil — 2026-08-24

Two findings, one of them systemic. Both are iOS-only and neither is visible on a single device.

#### Swift's `UUID.uuidString` is uppercase. Nothing else in this product is.

`crypto.randomUUID()` on web and `java.util.UUID.toString()` on Android both produce the lowercase
canonical form. So does Postgres when it renders a `uuid` column. **iOS was the only writer
producing `A1B2C3D4-…`** — for `newId()` (every row id it creates), for `authEnsureUser()`'s return
(the `user_id` on every iOS write), for `ReceiptsRepository`'s scan id, and in
`InvestmentsViewModel`.

That is not cosmetic, because of where those strings live:

- PowerSync's local mirror stores `id` and `user_id` as **TEXT**, and SQLite compares TEXT
  **case-sensitively**. `WHERE user_id = ?` with an uppercase id does not match a row that arrived
  from the server lowercase.
- Postgres `uuid` columns normalise on write. An iOS-created row syncs up as uppercase, is stored
  canonically, and **comes back down lowercase** — the local row's own id changes case underneath
  anything still holding the uppercase one.

Together: an iOS-written row is findable before its first sync and not after, and a parent created
on iOS does not match a child that references it via the server's lowercased copy. Fixed with one
`UUID.canonicalString` used at every persisting site (`Data/Ids.swift`). View-local `Identifiable`
keys — a draft line item in a transaction form — never reach the database and are deliberately left
alone; `TransactionItemInput` has no id field, which was checked rather than assumed.

#### `currentUserId` returned nil unconditionally

The property carried a comment claiming synchronous access was impossible in supabase-swift 2.x.
**It is not.** `auth.session` is async because it *refreshes*; `auth.currentUser` is a
`nonisolated` read off the local session store. Verified against **v2.54.1, the exact tag in
`Package.resolved`** — cloned and read, not recalled.

Most callers write `currentUserId ?? (try? await ensureUser())` and were unaffected. Four did not,
and each silently did nothing:

| Call site | What was broken |
|---|---|
| `LoanDetailViewModel` | `if let userId = …currentUserId` guarded the EMI charge — marking an EMI paid never posted it to the card |
| `CreditCardsViewModel` (×2) | both settle paths returned "Couldn't determine the current user." |
| `ReceiptReviewViewModel` | the save `guard` fell through silently |

Worse, `RepairRepository` and `ReceiptsRepository` are constructed with
`getUserId: { auth.currentUserId ?? "" }` — so they were writing rows with an **empty** `user_id`.

**Both bugs share a shape worth naming:** a comment asserting a limitation
(*"synchronous access is not directly possible"*, *"we return nil for sync access"*) that was never
re-checked against the SDK, and a platform default (`uuidString`) that looked like the obvious call
and was wrong only in comparison with the other two platforms. Neither is findable by testing iOS
on its own — the first needs a second device or a sync round trip, the second needs a code path
nobody had exercised.

### The Recurring screen — 2026-08-24

`recurring` was a nav-catalog id on both platforms with **no screen behind it on either** —
Android fell through to `coming_soon/{title}`, iOS rendered a `PlaceholderView`. Both are real
screens now, ported from `apps/web/app/recurring/page.tsx`, and they drive the engines ported
earlier today: `watchActiveItems`, `watchDueItems`, `postOnce` and `skipOnce` all had no callers
until now.

Present: net monthly cashflow, the two sides drawn to scale against each other, a row per
direction with its monthly total and item count, and "Due now" with Skip and Record wired to the
real engine.

**Everything is a monthly equivalent**, via the vector-tested `monthlyEquivalent` — a weekly bill
and a yearly subscription are only comparable once normalised, and raw amounts are never summed
across frequencies.

**Savings are excluded from the net, not merely unlisted.** A SIP is a transfer between your own
accounts: the money leaves the current account but not your net worth, so counting it as an outflow
would understate what you actually have spare. They still post through the same engine and still
appear under "Due now". Web's `summary.ts` argues this at length; the native ports carry the same
reasoning rather than the conclusion alone.

**Deliberately not built yet, and absent rather than dead:**

- **Create/edit.** Web opens `RecurringModal`. The native equivalent is W2.1's job (full page below
  600dp, dialog or side panel above; `.fullScreenCover` on iOS phones), and a "+" that opened
  nothing is exactly the dead control this audit keeps finding.
- **`/recurring/[direction]`.** The per-direction list is a separate web route. The direction rows
  are therefore **not tappable** — they read as summary rows, not as links to somewhere that does
  not exist.

#### One shared-package change, and why it was the right call

Web renders that headline as `t("netMonthly", "Net monthly cashflow")` — an **inline default**,
because the key is missing from the `recurring` namespace. So hi and nl users see English there
today. `cashflow.netMonthly` exists but says "Net monthly cashflow **(after savings)**", which is
the wrong label for a figure that *excludes* savings rather than deducting them — using it would
have been a quiet lie.

So `netMonthly` was added to `recurring/{en,hi,nl}.json`. English is byte-identical to web's inline
default, so web's rendering is unchanged in English and *fixed* in hi/nl. The hi/nl strings are not
invented: they are `cashflow.netMonthly`'s existing approved translations with the
"(after savings)" parenthetical dropped.

**This is the only change outside `apps/android`/`apps/ios`/`docs` in this pass, and it is flagged
rather than buried** — `packages/core/i18n` is shared with the live client, and the rule is that
web is off-limits. A missing key that web's own code asks for is the narrowest possible exception;
anything wider should be Akhilesh's call.

### Statements: iOS had invented a different feature — 2026-08-24

`StatementsView.swift` was not a mock of web's Statements screen. It was a **different feature that
does not exist**: a searchable list of "July 2026", "June 2026", "2025 Annual Statement" cards, the
last wearing a premium padlock. Nothing backed any of it, and there is no statement-generation
feature anywhere in the product for such a list to show. Android had no screen at all, which was at
least honest about the gap.

Web's `/statements` is a **date-ranged view of real transactions** — from/to dates, an
income/expense/net summary, the transaction list, behind the paid gate. Both platforms now have
that, sharing a new `LedgerRepository.watchTransactionsInRange`.

Two details in that query are easy to lose and are carried deliberately:

- **`type != 'opening_balance'`** — an opening balance is a bookkeeping entry, not something the
  user did. Including it puts a phantom line on the statement and inflates income.
- **`>= start AND < end`, with `end` advanced a whole day by the caller.** `occurred_at` is a
  timestamp; comparing `< end` against the bare date silently drops everything that happened after
  midnight on the final day.

**`entitlementKnown` is a third state, not defensiveness.** With `isPaid` defaulting to false and
the view rendering immediately, every cold start would flash "Go Premium" at a paying user before
the local entitlement row had been read. The screen renders neither the statement nor the upsell
until the row has been seen once; an unreadable row keeps the gate **closed** but leaves the state
unknown, so the upsell still does not flash.

**Absent rather than faked**, because web's versions do not translate:

| Web | Why not ported |
|---|---|
| Print (`window.print()`) | No phone equivalent. A share/PDF export is a feature to design, not a button to add. |
| "Analyze" → `/statements/analyze` | A separate screen that does not exist natively. `StatementImportView` is the *other* iOS fabrication — tracked separately. |
| "Go Premium" button | Web links to `/settings`; there is no native upgrade flow yet, so a button here would go nowhere. |
| `<input type="date">` | SwiftUI has `DatePicker`; Compose has no equivalent primitive. Taking it on iOS alone would put the two platforms out of step over a control neither spec has settled, so both use an ISO text field for now. |

### Two red CI jobs, and the Subscriptions tile was missing a line — 2026-08-26

**Android, `dashboard-trend` vector.** `buildTrend`'s `LocalDate.parse(todayIso)` threw where
Swift's `guard let ... else { return [] }` returned empty. iOS passed the same ten vectors, which
is what proved which side was wrong. The vector exists precisely to pin this: an unparseable
`today` is a caller bug, not a reason to crash a tile. Kotlin now `runCatching`s the parse.

**iOS, a type name collided with itself.** The Subscriptions tile's new `SubscriptionRow` in
`App/ViewModels/TileViewModels.swift` shadowed `Data.SubscriptionRow` — the `subscriptions`
TABLE's row, which `InsightsViewModel` reads — inside the App target, so an unrelated screen
stopped compiling and took the type-checker down with it. Renamed to `SubscriptionTileRow`;
Android's dashboard copy was renamed to match, even though Kotlin's packages had saved it there.
**Two types of the same name in one app is a trap even when the compiler tolerates it.**

**And the tile itself was short a line.** Web's `SubscriptionsTile` shows
`{n} active subscriptions · ~{lifetime} so far`; both ports showed neither the count nor the
estimate, because `estimatedSpentToDate`/`chargesToDate` had never been ported. They are now, with
21 + 5 golden vectors generated by running the real TS, and cross-checked against JS mirrors of
both ports over 62,060 fuzz dates before being committed.

Three smaller things the same read turned up, all fixed:

- The tile tested `rows.isEmpty()` for its empty state, but `rows` only holds subscriptions with a
  renewal date. Someone whose subscriptions were unscheduled saw "No active subscriptions" while
  paying for several. It tests `activeCount` now, as web does.
- The renewal rows showed a raw `next_due` ISO string and no amount. Web shows
  `{amount} · {12 Aug}`. `bucketLabel` was factored into `isoLabel`/`dayMonthLabel` on both
  platforms rather than growing a second date formatter.
- `watchSubscriptions` returned the generic `Item` and therefore selected `i.*`. It returns a
  purpose-built `Subscription` with web's own six columns now — `created_at` included, which
  `Item` does not carry and which the lifetime estimate needs.

**Deliberate divergence, recorded:** web's `chargesToDate` has no `default` branch, so an
unrecognised `frequency` falls out of the switch as `undefined` and renders the estimate as the
literal string "NaN". Both ports return 0 charges instead, which makes the estimate simply not
show. Unreachable on real data — `frequency` is a closed set of four — but a dashboard tile is not
the place to find out.

**Known Android/iOS divergence, NOT fixed here:** `TrendsTileViewModel` reads "today" as
`LocalDate.now()` (device-local) on Android and as UTC on iOS. Web is itself inconsistent —
`buildTrend`'s `today` is local midnight while its `dayKey` is `toISOString()` — so neither port is
simply right. The two disagree by up to a day near midnight for users away from UTC. The new
subscriptions code uses UTC on both, matching the TS default's `new Date().toISOString()`.
Fixing Trends needs a decision on which web behaviour is the intended one.

### Search, and the split rows Transactions had been showing three times — 2026-08-26

Search is built on both platforms. It is web's screen: a free-text query, four
type chips, an account filter, a date range, an amount range, a live result
count, and the same transaction row the Transactions list and the dashboard's
Recent tile already render.

Three pieces of it are shared rather than local, because they are shared on web:

- **`domain/search`** — `searchTransactions` and `activeFilterCount`, 48 golden
  vectors. Web computes this inside a `useMemo` in the page component, which
  cannot be imported, so the vectors were generated from a reference
  implementation of the port and diffed case by case against a literal
  transcription of web's component.
- **`domain/splits/Collapse`** — `splitInfoByTransaction` and
  `collapseSplitRowIds`, 18 vectors. The collapse half was generated by
  importing web's real exported `collapseSplitRows`; the aggregation half was
  transcribed, because `useSplitInfo` is a React hook.
- **`transactionListItem`** now takes an optional `SplitInfo` and applies web's
  three rules for a collapsed row: the amount is what you PAID, the sign is
  always negative and never the income green, and the account name is dropped
  because a split spans up to three accounts.

**The bug that found:** neither native Transactions list collapsed split rows.
Web has always done it. A split expense writes up to three ledger rows —
`own_share`, `lend`, `borrow` — so one dinner appeared as three lines with three
different amounts, and none of them was what you paid. Both lists collapse now,
after the 200-row cap, which is web's order.

Four smaller things the same read turned up, all fixed:

- **Android formatted every amount in the ACCOUNT's currency**, falling back to
  the base currency when the account lookup missed. Web passes the
  TRANSACTION's currency. A foreign-currency charge on a rupee card rendered
  with the wrong symbol, and the fallback hid it.
- **Both Transactions screens hardcoded English**: the search placeholder, and
  four filter chips labelled by capitalising the filter KEY (`"all"` → "All") in
  every language. The translated strings existed and were unused.
- **`RateLookup` was not `@Sendable`**, so a rate lookup could not cross an
  `AsyncStream` combinator — the iOS failure in CI run 32940348246. Every
  lookup here closes over an immutable rate table, so the annotation records a
  property they already had.

**Deliberate divergence, recorded:** web's amount filter is
`Math.round(Number(min) * 100)`, compared against `Math.abs(t.amount)` in the
row's own minor units — so on web "at least 1000" means ¥100,000 against a yen
row and excludes a ¥42,000 hotel. The ports convert per row with `fromMajor`.
Three vectors pin it. Web's search haystack has the same hardcoded two decimals
(`toFixed(2)`); the ports use the currency's own minor-unit count.

**Still open on Android, and it needs a decision.** `transactionListItem`
hardcodes three English strings — `"Uncategorised"`, `"Today"`, `"Yesterday"` —
where iOS uses `S.Transactions.uncategorised` and `S.Statements.today/yesterday`.
iOS can, because Swift's generated accessors read the bundle with no context;
Kotlin's need a `Resources`, and this codebase's own rule (I18n.kt, and my own
comments in two view models) is that **a view model must not hold one**. The
honest fix is for the builder to return structure the VIEW names — a
`categoryName: String?` and a `TxDateLabel` sealed type instead of two baked
strings — which changes `TransactionListItem` on both platforms. Not done here,
because doing it inside a Search commit would have buried it.

### Categories and Labels, and three hex parsers — 2026-08-26

Both taxonomy screens are built on both platforms, and Settings now has the
`Categories & labels` section that reaches them — neither native Settings screen
had it, so these screens would have been unreachable even once they existed.

`categoryTree` is in Domain with 15 vectors. Web computes it inline in a
component's render and it has four branches, three of which only appear while
something is typed in the search box: a parent with no matching descendant is
hidden; every surviving parent is FORCED open while searching; a parent that
matches shows all its children; a parent that does not shows only the matching
ones. That is exactly the kind of thing two ports drift on silently.

**Three components promoted, because a second copy was about to be written:**

- `ColorSwatchRow` on Android — it was inline and private in
  `CreateAccountScreen`, and Labels needed the same control. iOS already had one.
- `ConfirmDialog` on Android — web reaches its confirm through a `useConfirm()`
  hook returning a promise, which has no Compose equivalent, so this platform
  had **four** hand-rolled `AlertDialog`s and was about to get a fifth.
- `parseHexColor` — there were **three** hex parsers in the Android app module:
  one in `AccountColors.kt` and a private copy in each account form, the second
  of which had been renamed `parseHexColorEdit` purely to dodge a redeclaration
  clash with the first. Two swallowed a malformed string as grey and the third
  threw, so the same stored value could render or crash depending on which
  screen you were on. One parser now, with the safe fallback.

**Deliberate divergence, recorded:** web picks a label's colour with a free
`<input type="color">`. Compose has no equivalent control, and adopting one on
iOS alone would put the two platforms out of step over a control neither spec
has settled — the same call `RecurringFormView` made about dates. Both platforms
use the app's existing 18-swatch palette, which is web's own `ACCOUNT_COLORS`,
and which additionally cannot produce the white-on-white a free picker can.

**Not ported: the Auto-categorize card** at the top of web's Categories page. It
drives `apps/web/src/categorize/` — 905 lines of on-device merchant matching
with its own seed taxonomy, normaliser and semantic matcher. That is its own
port, not a corner of this screen, and it is the same engine `transactions/new`
already defers. Its strings are also the one place web ships **untranslated**
copy: every `t()` call in that card passes an inline English `defaultValue` and
none of the keys exist in `packages/core/i18n`.

### The notification inbox — 2026-08-26

The bell in both shells has led to a placeholder since the shell was built. The
repository, the unread-count watch and the badge all already existed; the screen
they pointed at did not. It does now: the inbox, the unread tint, the severity
dot, mark-read on tap, mark-all-read, dismiss, and web's empty state.

**`timeAgo` is in Domain with 17 vectors, and it returns a SHAPE, not a string.**
Web builds `` `${m}m ago` `` inline and then falls back to
`toLocaleDateString()` — a hardcoded language and a localised one in the same
five-line function. The port returns `justNow` / `minutes(n)` / `hours(n)` /
`days(n)` / `on(iso)` and the view names it, which is the same split
`buildTrend` already uses for its bucket labels.

`DateLabels` was promoted on both platforms — `isoLabel` and `dayMonthLabel`
were private inside the dashboard's tile views, and this screen needed the same
formatting.

**A new `notifications` i18n namespace.** Every string on web's notifications
page is a hardcoded English literal — title, "Mark all read", the empty state,
and every relative-time label. The namespace is new rather than moved, because
moving it would mean editing `apps/web`. Both native platforms are translated;
web is not, and will not be until someone wires the namespace up there.

**Repository additions:** `markAllRead` on iOS (Android had it) and `dismiss` on
both. `markAllRead` updates row by row rather than issuing one bulk
`UPDATE ... WHERE read_at IS NULL` — PowerSync records a CRUD entry per row, so
a bulk statement over rows it never saw named would sync as nothing at all.

**Not ported: the row's deep link.** Web's row navigates to `n.href`, a web path
like `/budgets`. Turning that into a native destination needs a path → route
map that does not exist, and guessing one would send someone to the wrong
screen — worse than a row that only marks itself read.

### Help — generated, not transcribed — 2026-08-26

Help is built on both platforms, and its content is **generated** from
`apps/web/app/help/page.tsx`'s `SECTIONS` by a new parity generator. 11
sections, 33 question/answer pairs. A FAQ is exactly the kind of content that
goes stale the moment it exists in three places — nobody re-reads one to check
it still matches — so the parity job now fails if web's copy has changed and the
native copies have not.

The generator also **validates every section icon** against the shared
`MATERIAL_ICON` map, so a new icon on web fails the job rather than painting
nothing on a phone. And because the generated content carries web's own
`space_dashboard`-style name, both views resolve it through the
`SanvyaIcons.byWebName` map the icon generator already emitted — no second
mapping to keep in step.

`filterHelp` is in Domain with 15 vectors. Three of them pin details that are
easy to get wrong: a **whitespace-only query returns everything** (web trims
this one, unlike the taxonomy search, which it does not — both behaviours are
now pinned on their own screens), section **titles are not searched**, and a
needle may **span the space** web inserts between a question and its answer.

**The FAQ copy is English on all three platforms, and that is web's gap, not the
port's.** All 33 questions and answers are string literals in that component
rather than keys in `packages/core/i18n` — the chrome around them (title, search
box, no-match line, footer) is translated, the content is not. Fixing it means
moving the copy into the i18n package and having web read it from there, which
is a change to the live client and therefore Akhilesh's call. Until then,
generating from web is what keeps the three copies identical rather than merely
similar.

### Reflect, and the last of the small screens — 2026-08-26

Reflect is built on both platforms: the card stack over untagged expenses,
swipe left for "need" and right for "greed", the two buttons for anyone who
would rather tap, undo, skip, the counter and the empty state. Judging writes
`transactions.intent`; skipping writes nothing and hides the card for this visit
only, which is what web does.

**Two deliberate divergences, both away from web's version:**

1. Web's buttons read **"Need (←)" and "Greed (→)"** — keyboard hints on a
   screen that, on a phone, has no keyboard. The arrows are dropped and the
   swipe is explained in a line under the stack instead.
2. Web paints the swipe tints and both buttons with **raw Material colours**
   (`#4CAF50`, `#F44336`) rather than the design tokens every other surface in
   the app uses. Both ports use `positive` and `negative`, which is what those
   two hex values were reaching for. This is the fourth palette drift found on
   web; the others are in the chart palettes.

The undo history is local on both platforms, as it is on web. An undone
judgement re-clears `intent`, which brings the row back into the query on its
own; an undone skip just stops hiding it. Persisting the history would be a
second source of truth for something the ledger already records.

A new `reflect` i18n namespace, for the same reason `notifications` needed one:
every string on web's Reflect page is a hardcoded English literal, down to
"All caught up!" and "Loading...".

**With this, the small-screens sweep is done.** Search, Categories, Labels,
Notifications, Help and Reflect are all built on both platforms. `AssistantView`
is the one nav entry still a placeholder — 1,669 lines on web, and its own
piece of work.

### A guard that reads imports, and the three bugs it found — 2026-08-26

None of the App-layer code written during the small-screens sweep had been
through a compiler: every iOS run since 0613aad died inside the `Data` module,
so the build never reached `App`. Rather than wait, `check-swift-traps.mjs`
grew a scan that would have caught the most likely class of failure.

**The scan:** collect every top-level `public` type declared in `Data` and in
`Domain`, then flag any file under `apps/ios/App` that NAMES one without
importing that module. Comments and string literals are stripped first, names
the App module also declares are excluded, and a short denylist covers names
Apple's own frameworks define (`GridItem`, `Label`, `Section`, `Item`, …) —
a file using SwiftUI's `GridItem` is not evidence that it wants Domain's.
Nested types are excluded by matching only zero-indent declarations: a file
containing the word "Item" is not naming `RecurringRepository.Item`.

Swift's error for the real thing is *"cannot find type 'LabelRow' in scope"*,
which reads like a typo rather than a missing import — and a view that got the
type by inference compiles right up until someone writes the name down.

**It found three, all mine, all from this sweep:** `SearchView.swift` and
`TaxonomyViews.swift` named `Account` and `LabelRow` with no `import Data`, and
`TransactionTileLogic.swift` named `SplitInfo` with no `import Domain`. In each
case the view model beside it had the import, so nothing looked wrong.

Two more found by reading rather than by grep, both would have been runtime
rather than compile failures:

- iOS `ReflectView` passed `.gesture(isTop ? swipe(row) : nil)`. `.gesture()`
  takes a `Gesture`, not an `Optional`, so that would not have type-checked at
  all; the stack is two branches now.
- Android `ReflectScreen` returned early past a `remember`. The Compose
  compiler says nothing, and the bug shows up later as state whose identity
  does not survive the card it belonged to. Every `remember` runs before the
  guard now.

The Kotlin guard's watch list grew too — `parseHexColor`, `ColorSwatchRow`,
`ConfirmDialog`, `isoLabel`, the split-collapse pair and the four new Domain
entry points. `parseHexColor` earned its place: it had three competing
definitions in the Android module until this sweep promoted it.

Both guards were verified against deliberately-broken probes: strip the import,
the guard names the file and exits 1; restore it, clean.

### The CSV layer, and a web bug that divides money by a thousand — 2026-08-26

`/data` (import & export) is the next unbuilt route, and its pure half is now
ported and vector-tested on both platforms: the CSV reader/writer
(`apps/web/src/data/csv.ts`) and both import adapters
(`apps/web/src/data/adapters.ts`). 25 vectors, generated by running **web's real
modules** — these are plain exports, so unlike the last four ports there was no
transcription step. (The one edit was adding a `.ts` extension to a relative
import so node could resolve it; the copy was diffed against the original.)

**A web bug worth scheduling ahead of the other three.** `num()` in
`adapters.ts` parses `"1.234,56"` as **1.23456**, not 1234.56. The cleanup only
strips a comma with three digits after it, the "European" branch does not fire
because a dot is present, and the final comma-strip then deletes the decimal
separator. It matters here specifically: the second importer is Wallet by
BudgetBakers, a Czech app, and a €1,234.56 charge imports as €1.23 with no
warning. Both ports reproduce it and a vector pins it, so a fix on web fails
that vector rather than passing quietly on two platforms out of three.

Two deliberate shape changes:

- `parseWithAdapter` takes **`nowIso`** where web reads the clock for a row with
  no date. Nothing in Domain reads a clock; it is also what makes the vector
  deterministic.
- **`jsParseFloat`.** JavaScript's `parseFloat` reads a leading numeric prefix
  and ignores the rest; Kotlin's `toDoubleOrNull` and Swift's `Double(_:)` want
  the whole string. `"1.2.3"` is 1.2 in the browser and null on both phones —
  and a real bank export does contain cells like that. Both ports match the
  browser.

`downloadText` is deliberately NOT ported: there is nothing shared between a
browser anchor click, an Android SAF intent and a `UIActivityViewController`.
The repositories and the screen are the next commit.

### Import/export, part two: the repositories — 2026-08-26

`exportTransactionsCsv` and `importTransactions` are on both platforms, plus two
more Domain pieces with 39 vectors between them: `importDate` (web's `toIso`)
and `guessAccountType`.

**One write transaction for the whole import file**, which is web's `…Bulk`
variant rather than its per-row one. PowerSync records a CRUD entry per row and
uploads a contiguous run as a single batched request; a transaction per row
means one PostgREST request per row on the next sync — for a ten-thousand-line
statement, the difference between one upload and ten thousand.

**Two more web bugs, both now #5 and #6 on the list**, both fixed in the ports:

- The CSV **round trip loses money** for any currency that is not two-decimal.
  Export writes `(amount / 100).toFixed(2)`; import reads it back with
  `fromMajor`, which uses the real minor-unit count. ¥500 exports as `"5.00"`
  and re-imports as ¥5. `majorText` uses `minorUnits(currency)` in both
  directions — byte-identical to web for INR/USD/EUR, correct for the rest.
- `toIso` reads a dateless date column in the **device's timezone**. The same
  file imports different `occurred_at` values in Mumbai and London, and a
  `DD/MM/YYYY` row dated the 1st lands a day earlier for anyone east of UTC.
  Both ports read it as UTC.

`importDate` also narrows the accepted formats deliberately: web's `new Date(s)`
takes anything the JS engine parses, including `"Aug 1, 2026"`. There is no
equivalent on either phone and no specification to port, so the ports accept
ISO-8601 and the day-first numeric forms real exports contain, and fall back to
"now" for anything else — which is what an unparseable string does on web too.

Still to come: the screen, and the platform file IO (Android SAF, iOS document
picker + share sheet), which is the part with no shared shape at all.

### Import/export, part three: the screens — 2026-08-26

`/data` is built on both platforms, and Settings has the `#data` section that
reaches it — neither native Settings screen had one, so the screen would have
been unreachable even once it existed. That is the third time this sweep that a
built screen needed a Settings entry web already had.

**The file halves have no shared shape and are not pretending to.** Android uses
the Storage Access Framework (`CreateDocument` for export, `OpenDocument` for
import); iOS uses `.fileExporter` and `.fileImporter`. Everything either side of
the picker — parsing, previewing, the write transaction — is Domain's and the
repository's, and identical.

SAF specifically, and not a `WRITE_EXTERNAL_STORAGE` path: the user picks the
destination, the app needs no storage permission at all, and the file can land
in Drive or on a USB stick as easily as in Downloads.

Two details worth keeping:

- **Both file pickers accept more than `text/csv`.** Plenty of banks hand out a
  `.csv` that the system types as `application/octet-stream` or `text/plain`,
  and a picker that greys out the file the user came to import is a dead end.
- **The premium gate is three-state, not two.** `null`/not-loaded shows neither
  the form nor the upsell — the same "keep the gate closed, but say nothing
  yet" rule the Statements screen already uses. Showing an upgrade prompt to a
  paying customer whose entitlement has not synced yet is worse than showing
  nothing for a second.

**Not ported:** web's `importTransactionsBulk` has a second entry point used by
the statement importer. The bulk *strategy* is what both ports use for the file
importer; the statement path that also calls it is a separate screen and is
still on the list.

### The first-run walkthrough — 2026-08-23

`/onboarding`'s `Walkthrough.tsx` is now on both platforms, and it is the first
screen this sweep has ported where the *reason* for every decision is written
down in the source: it exists for a real 60+ user who signed up, landed on the
dashboard, read "add an account" as "link my bank", and stopped. Three rules
follow from that and both ports keep them — say what the app IS before saying
what to tap; treat manual entry as the product rather than an apology; and do
not hand a first-timer the real new-account form, which offers Savings /
Current / Credit card / Demat and reads as bank onboarding. Step 2 asks for a
name and a number and defaults everything else.

Steps 1–4 are setup and end in a real Finish. Steps 5–7 are opt-in, because
making onboarding *longer* would be the wrong answer to "I found this
overwhelming".

**What is shared, and what is not.** The decision to show it is
`shouldShowWalkthrough(done, skipped, syncPending, accountCountLoaded,
realAccountCount, signedIn)` in Domain, pinned by the **entire 96-row truth
table** plus 7 progress cases. That is not thoroughness for its own sake: four
of the six inputs exist only to stop the dialog appearing at the wrong moment,
and "did not appear" is the failure nobody notices until a returning user is
told to set their accounts up from scratch. `syncPending` is the one that
matters most — during the first sync a returning user's accounts have not
arrived yet, so judging "you have no accounts" then is actively alarming.

**The `done`/`skipped` split is deliberate and is web's.** `done` is permanent
(`localStorage` → `Prefs`/`UserDefaults`, same `sanvya:walkthroughDone` key
string on all three clients); `skipped` is this-launch-only (`sessionStorage` →
the gate object's own memory, which is the same lifetime). Skipping is "not
now": someone who taps it while still having no account should meet the
walkthrough again next visit. A scrim tap resolves to `skip()`, never `finish()`.

**Entitlement gained a real state object.** Step 7 needs `isTrial`
specifically — "your trial is running" and "you are on a paid plan" are
different sentences and only one of them has a countdown — and both platforms
only had the `isPaid` half of `apps/web/src/entitlement.ts`. `entitlementState()`
is now the whole of it (effective tier, isPaid, isTrial, trialDaysLeft, and the
AI-quota arithmetic), `isPaid()` delegates to it so there is exactly one place
that decides what a tier means, and 31 new vectors cover the trial boundary
(day 14 in, day 15 out), the comp-tier override in both directions, and the
rule that a stale `premium_trial_start_date` on a paid tier is **not** a trial.

**Two defects found while wiring it, both fixed:**

- iOS `ShellViewModel.isGuest` and `guestDaysLeft` were **declared and never
  assigned.** `AppShell` drives its sign-in cover off `isGuest` — its own
  comment calls `.onChange(of: viewModel.isGuest)` "the only exit" — so with the
  value frozen at `false` the cover could never close itself and the guest chips
  it gates were dead. Android had it right. iOS now reads both off the auth
  session, which needed `currentUserCreatedAt` on `AuthRepository`.
- Web bug #7 (below): `saveSpend()` computes minor units as `× 100`, three lines
  below a `saveAccount()` that correctly uses `fromMajor`.

**`SanvyaCard` gained a `background` override** on both platforms, which web's
`.card` has always had. Step 5 and step 7 nest a card inside the modal's own
card, and `surface` on `surface` is two identical fills separated by a hairline.

### The pre-auth deck, and the auth gate — 2026-08-23

Ported straight after the walkthrough, because they are the two halves of the
same first run and shipping one without the other leaves the gate pointing at
the wrong screen.

Web's gate replaces to `/onboarding` when there is no session; both native gates
went straight to the login form, so the seven slides that say what Sanvya *is*
were reachable on the web client only. Both now gate deck → login, with
`onboardingSeen` written under web's own localStorage key and its own stored
value (`"1"`, not a native boolean), so the three clients agree on what the key
means.

**The visual identity is generated, not copied.** `SLIDES` in web's page holds
seven glyphs and seven gradient pairs and nothing else — the copy is already
i18n. `tools/parity/generate-onboarding-slides.mjs` emits both native files and
is in the parity job. The count is load-bearing on both platforms (page dots,
"is this the last one"), and the generator also emits the title/body lists by
name — `S.Onboarding.slides0Title` and friends are flat accessors with no way to
index them, so a hand-written switch would have been the one place an eighth
slide got forgotten. It fails if a slide has no i18n keys, if a gradient stop is
not `#rrggbb`, or if `SLIDES` cannot be found.

The gradient stops are stored as the hex strings web writes and go through each
platform's existing hex parser — the one every account and chart colour already
uses. A second colour constructor would be a second place for a bad digit to
behave differently.

**Two things deliberately not ported** (both in ABSENT-BY-DECISION): the
"Install the app" chip and its PWA `InstallGuide`, which have nothing to say on
a phone where the app is installed; and web's `?mode=signin` split between
"Create an account" and "Sign in", which neither native login screen can accept
— Android's has its own toggle and no entry parameter, and iOS's is a single
OTP-first form with no register mode at all. Both buttons land on the same
screen, said out loud rather than hidden.


### Itemized bill splitting — 2026-08-27

`/receipts/split` is on both platforms, and with it the last piece of the
receipt-scan flow: scan → review → *who had what* → a shared expense.

**The critical design point is web's and is carried over verbatim: this does
not introduce a second balance model.** Per-item shares are allocated, rolled
up per person, and written into `expense_participants` — the same table
`createSplitExpense` writes and the same table every balance, settle-up and
friend-graph query already reads. `expense_items` / `expense_item_shares` are
the BREAKDOWN, kept so a bill can be explained and re-opened later. Nothing in
the balance math on either platform knows itemized splits exist, which is why
this landed as an addition rather than a migration. Android's
`SplitsRepository` header had recorded the omission and the reason; that note
is now the history of it.

Two details worth keeping, both lifted from web's own comments because both are
real bugs waiting to happen:

- **All items are written, then all shares — never interleaved.** The sync
  connector coalesces only *consecutive* same-table ops into one request, so
  interleaving turns a 40-row bill into ~40 round-trips. It is not a style
  preference.
- **`split_mode = proportional` is only legal on a charge** (a DB check
  constraint). A proportional mode set on an item line is written as `equal`.

**What is shared.** `SplitAssign` in Domain — `lineWeight`, `validateSplitLine`,
`splitModesFor`, and the two text helpers — under **79 vectors**. This is the
part that decides whether a bill may be written at all, and "shares are off by
₹0.01" has to mean the same thing on three clients. The vectors cover the
sign rule for exactly splitting a NEGATIVE line (a discount), which is the one
place the arithmetic is easy to get subtly wrong, and the JS `Math.round`
tie-toward-+Infinity rule that both native languages disagree with by default.

`validateSplitLine` returns a **shape**, not a sentence: `LineProblem` carries
the numbers and each UI formats them through its own i18n. Same rule as
`timeAgo` — Domain never holds `Resources`.

**Divergence, recorded not hidden:** web's group picker is a `<select>` whose
empty option means "create a new group". Both native screens use a chip row and
show the new-group field when nothing is selected, because a placeholder option
inside a native picker reads as a value rather than an action.

### Push notifications — 2026-08-27

Both platforms already had the SHAPE of push — a `PushRepository`, an FCM
service, an APNs delegate, a Firebase config, a `push_enabled` toggle. None of
it worked, and each broken piece was silent in a different way.

**Five real defects, all fixed:**

1. **The upsert could never succeed, on either platform.** Both sent
   `onConflict = "user_id, token"`, but migration 0048 adds exactly one unique
   constraint for native devices — `unique (token)`. Postgres requires the ON
   CONFLICT target to match a unique index, so every registration failed with
   "there is no unique or exclusion constraint matching the ON CONFLICT
   specification". **No device token has ever been stored by either app.**
   `token` alone is also the right key on its own terms: if a phone signs in as
   somebody else, the row must MOVE, not duplicate, or the previous account
   keeps getting that device's alerts.
2. **Android's repository swallowed every failure** into `printStackTrace()`,
   which is why #1 survived the whole life of the feature. The try/catch is
   gone; callers handle it.
3. **iOS had no `aps-environment` entitlement and no `remote-notification`
   background mode.** Both absences are silent: `registerForRemoteNotifications()`
   returns happily, the delegate callback never fires, and the app waits forever
   for a token Apple was never asked to mint.
4. **There was no way to turn push OFF.** Neither platform had an
   `unregisterToken`, so the switch only flipped a local pref and the dispatcher
   kept delivering to a device whose owner had just said no.
5. **Both asked for notification permission in the first frame of the first
   launch** — before the user had seen a single screen. On iOS the prompt can be
   shown exactly once, a refusal is permanent, and asking without context is on
   App Review's own list of rejection reasons. Permission is now asked from
   Settings, when the switch is turned on.

**What replaced the toggle.** `push_enabled` used to be a plain switch that
wrote a number: no permission ask, no token, no test. It is now the real thing
on both — permission → token → register → *then* set the pref, in that order,
because the pref means "a token for this device is on the server" and setting it
first leaves someone staring at an "on" switch that will never deliver anything.
Web's per-row hints came with it; both phones had none, which turned "Upcoming
EMIs & bills" into a switch whose lead time was invisible.

**Shared, in Domain:** `pushState()` and `shouldRegisterAtLaunch()` under 30
vectors — the whole cross-product. The distinction worth pinning is **blocked vs
off**: they render identically, and only one of them can be fixed by tapping the
switch. Once the OS permission is denied neither platform will ever show the
prompt again, so a row that says "off" when it means "I can't ask again" is a
switch the user will flip forever.

**The test button is ported deliberately, not as decoration.** Web's own comment
says why: a LOCAL notification proves permission and the delivery path work on
this device, so when it shows and real alerts do not, the gap is the server
dispatch — not the phone. That is the single most useful thing a support
conversation can establish. iOS uses a 1-second trigger rather than `nil`
(a nil-triggered notification while its own app is foregrounded is suppressed,
so the button would appear to do nothing), and the delegate now returns
`.banner` for foreground presentation.

**Still not verifiable here.** None of this can be end-to-end tested without a
real device, a real APNs key and a real FCM sender — CI compiles it and the
vectors pin the state machine, and that is the honest limit. The dispatcher side
(`notify-dispatch`) is a Supabase edge function and was not touched.

### The statement analyzer, part one: the domain — 2026-08-27

`/statements/analyze` is 329 lines of screen over 419 lines of pure logic in
`apps/web/src/statements`. The pure half is ported to both platforms and pinned
by **61 vectors**; the screen is the next pass. Splitting it there is not
arbitrary — everything below the screen is deterministic and testable, and
everything in the screen is charts, a file picker and a review table.

**The vectors were generated by RUNNING web's modules, not by reading them.**
`parseCsv.ts`, `analysis.ts` and `reconcile.ts` were copied verbatim (only the
import extension changed, and diffed to prove it), driven with nine real-world
statement shapes — HDFC debit/credit columns, a semicolon export with European
decimals, a tab-separated one with a Dr/Cr indicator column, a file with five
preamble rows before the header, quoted commas, CRLF, a headerless file and an
empty one — and the output captured as-is. That is why the fixtures contain two
of web's own defects rather than what a careful reader would have written.

**Two divergences, both deliberate, opposite decisions, and both recorded:**

- `num()`'s European-decimal bug (web bug #4, second site) is **reproduced**. A
  browser importing €1.23 where the phone imports €1,234.56 from the same file
  is worse than a shared bug, and the vector fails loudly the day web is fixed.
- The hardcoded `× 100` (web bug #8) is **fixed** with `fromMajor()`. Same
  treatment as bugs #5–#7, and the `jpy` fixture is the one hand-edited
  expectation in the file, annotated in place.

**Details worth keeping:**

- **A second CSV parser, on purpose.** `domain.csv.parseCsv` is the app's own
  export format: comma-or-semicolon, delimiter read off the literal first line,
  no tabs. A bank's "CSV" is routinely tab-separated and routinely opens with a
  title block and blank lines. Web keeps two parsers for exactly that reason.
- **`stableSorted` on the Swift side.** `sorted(by:)` is not guaranteed stable
  in Swift, while `Array.prototype.sort` is stable in every engine web targets
  and Kotlin's sorts are stable too. Two categories with the same total, or two
  outliers with the same amount, would otherwise come back in a different order
  on iPhone than on Android for the same statement.
- **Date parsing is day-first**, deliberately. `03/04/2026` is the 3rd of April
  on every Indian statement this exists for, and there is no way to tell it from
  March 4th without knowing the issuer.
- **Reconciliation is greedy best-first, not optimal.** A maximum weighted
  matching would pair better, but web is greedy, and a phone that matched a
  *different* pair than the browser for the same statement would be worse than a
  slightly suboptimal one.
- `reconcileStatement`, not `reconcile`: `domain.reconcile` already owns that
  word for the receipt-vs-total check.

**PDF is now ported on both** — see "Statement PDFs" below.

### Statement PDFs — 2026-08-27

The last real gap on `/statements/analyze`, and the user's call: *"For the PDF on
android pick the most reliable between the two and keep that optional."*

**The library choice was made by the licence, not the benchmark.** iText 7 is
AGPL-3.0 unless you buy a commercial licence, and AGPL on a closed-source app
means publishing the app's source — so "most reliable" resolves to
**PDFBox-Android (Apache-2.0)**, the only one of the two that can ship at all.
It is also the only one that exposes per-glyph x/y positions, which the
column-aware parser needs. iOS uses **PDFKit**, which ships with the OS.

**Where the line between shared and platform code sits.** Web's `parsePdf.ts`
does two jobs: it drives pdf.js to get positioned text, then it parses. Only the
second job could be ported directly — extraction has no shared shape. So:

| Layer | Android | iOS | Shared? |
| --- | --- | --- | --- |
| Bytes → positioned glyphs | `PdfBoxTextExtractor` | `PDFKitTextExtractor` | no — `PdfTextExtractor` / `PdfTextExtracting` |
| Glyphs → rows of cells | `groupPdfGlyphs` | `groupPdfGlyphs` | **yes**, Domain |
| Rows → `ParsedStatement` | `parsePdfStatementFromGlyphs` | same | **yes**, Domain |

`groupPdfGlyphs` is the piece web does not have and the reason this split is
drawn where it is. pdf.js hands back text RUNS; PDFBox and PDFKit hand back
GLYPHS. Letting each app rebuild runs its own way would have meant the two
phones disagreeing about where a cell ends — and therefore, on a bank that lays
its Withdrawal and Deposit columns close together, occasionally about a whole
transaction. Both extractors now contribute nothing but ordered positioned
glyphs and Domain decides the rest, under vector test.

**28 new vectors.** 18 come from RUNNING web's real `parsePdf.ts` against
hand-built row layouts (HDFC-style debit/credit columns, an SBI-style Dr/Cr
indicator column, a bare Amount column, a Dr/Cr suffix inside the money cell,
headerless, no-numeric-column, and the line-heuristic fallback). The other 10
cover `groupPdfGlyphs` and the end-to-end glyph path; those are the one set with
**no web counterpart**, so their reference implementation was written alongside
the ports. They cannot prove fidelity to web — there is nothing to be faithful
to — but they do prove Android and iOS split cells at exactly the same points,
which is the only thing that could differ.

**Web bug #8's fifth site.** `parsePdf.ts` hardcodes `Math.round(x * 100)` in
both parsers. The ports use `fromMajor()`, so the `jpy` vectors are hand-edited
away from web's output, exactly as the CSV fixtures' `jpy` case is.

**"Optional" means the app survives the library, not that the library is
absent.** PDFBox-Android is a normal `implementation` dependency — `compileOnly`
plus reflection would mean it is never in the APK, which is not optionality, it
is removal. What is real is that every entry point goes through
`PdfTextExtractor`, every failure including `NoClassDefFoundError` and
`ExceptionInInitializerError` is caught (`Throwable`, not `Exception` — a
stripped library throws Errors, not Exceptions), and the analyzer then reports
PDFs as unavailable, offers CSV only, and keeps working. Dropping the library
entirely is one Gradle line, one file and one Koin binding.

**The honest caveat, recorded rather than buried:** ~10-16MB of PDFBox font
assets now sit in the APK. If size becomes binding the answer is Play Feature
Delivery (an on-demand dynamic feature module), not a different library — and
that is a build-system change that buys nothing for reliability, so it is not
being done pre-emptively.

### The auto-categoriser — 2026-08-27

Ported because the statement analyzer needs it, but it is a feature in its own
right and neither phone had any of it: `apps/web/src/categorize` is 905 lines,
and the pure core — `normalize.ts` (103) and `engine.ts` (186) — is now on both
platforms under **65 vectors**.

Without it the analyzer's "Where it went" donut is one slice labelled
Uncategorised, which is a worse screen than no screen.

**The tables are GENERATED, not copied.** `tools/parity/generate-category-seeds.mjs`
emits `SEED_RULES` (186 keyword → category pairs), `STOP_WORDS` (13) and
`NOISE_TOKENS` (121) into both Domains, and is in the parity job. All three are
data, and the noise set is the one that would hurt: it decides which tokens
survive normalisation at all, so one platform missing a bank code silently
changes what *every* statement row categorises as — with nothing failing. The
generator also refuses a keyword mapped to two categories, which a JS object
literal would resolve by silently keeping the last one.

**Three ordering details are load-bearing, and each would have been a
platform-specific coin flip:**

1. `normalizeText`'s token list is built through a Set and then flattened.
   Insertion order reaches scoring, and `scoreTokens` breaks a tie by keeping
   the FIRST-scored category — so a hash-ordered set would make two equal-score
   categories differ between phones *and between runs on the same phone*. Both
   ports use an insertion-ordered structure and the vectors pin the order.
2. `scoreTokens`'s score map has the same problem for the same reason. Swift
   keeps an explicit `order` array beside the dictionary.
3. `buildSeedMap` returns an ordered array on Swift rather than a `Dictionary`,
   because Swift dictionaries have no defined iteration order at all.

**What is deliberately not ported yet:** `learnFromSave` (the write half — it
teaches the engine from a saved transaction), `autoJob.ts`, `anchors.ts` and
`semantic.ts`. The classifier reads rules; nothing on either phone writes one
yet, so both apps run purely on cold-start seeds until that lands. Recorded in
ABSENT-BY-DECISION rather than left looking finished.

`listCategoryRules(userId)` is new on both repositories — a single
`ORDER BY weight DESC` read that backs the whole classifier. The ordering is
part of the contract: `BulkClassifier` keeps the first phrase rule per key,
matching web's `if (!phraseRules.has(key))`, and web's single-shot path picks
its phrase with an explicit `ORDER BY weight DESC LIMIT 1`. Ordering in the
query is what makes the two paths agree.

### The statement analyzer, part two: the screen — 2026-08-27

The screen is on both platforms and reachable from Statements, where web puts
the same link. Everything shown is Domain's — the parse, the analysis, the
reconciliation — so this pass added state and four repository calls, not
arithmetic.

**On-device categorisation is what makes it worth having.** The classifier is
built ONCE per file and run over every row in memory. A per-row query would turn
a 400-line statement into 400 round-trips against a database the UI is also
reading, and web's own comment says so. Only debits are classified: a salary
credit is not a Food & Dining row because the payer's name happens to contain a
seed keyword.

**Three repository additions**, all on both platforms:
`listCategories()` (a snapshot, not a watch — a subscription that re-fires
mid-parse would be worse than useless), `listCategoryRules(userId)`, and
`listRecordedForReconcile(accountId, from, to)`.

That last one diverges from web on purpose: web pulls the whole `transactions`
table and filters by date in JS. Same rows, but a phone reading a five-year
ledger to reconcile one month of statement is a different proposition from a
browser doing it, so the window is applied in SQL. The `to` end is padded by the
reconciler's own four-day window — a row dated the last day of the statement can
legitimately match one recorded four days later — which is exactly what web's
`addDays(to, 4)` does.

`addDaysIso` is new in Domain and does NOT reproduce web's version. Web builds a
local `Date`, mutates it, then calls `.toISOString()` — a local→UTC round trip
that can land a day off for anyone not on UTC. The only caller pads a window by
four days, so the defect's observable effect is zero, and reproducing a bug that
cannot be seen is not faithfulness, it is superstition.

**Import uses `skipDuplicates: false`, deliberately.** The reconciler has
already established that none of these rows is recorded; a second, weaker dedupe
inside the importer would silently drop two genuinely identical coffees bought
on the same day. Web passes the same flag for the same reason.

**Small platform notes worth keeping:** iOS opens the picked file inside a
security-scoped access window (without it the read fails on a real device and
works in the simulator — the worst kind of bug) and falls back to Windows-1252
when a bank export is not UTF-8. Android's picker offers `text/plain` and
`application/octet-stream` alongside `text/csv`, because plenty of banks hand
out a `.csv` the system types as neither.

**CSV and PDF on both**, as of 2026-08-27 — see the section below.

### Done-when for this section

- [x] Android has a login screen reaching every method its data layer already supports. *(2026-08-24)*
- [x] `signInWithPassword` on both. *(2026-08-24 — iOS was the gap)*
- [x] Google on both, linking rather than replacing a guest. *(2026-08-24, compiles; no live sign-in yet)*
- [x] `currentUserId` works on both platforms. *(2026-08-24 — iOS returned nil unconditionally)*
- [ ] A real device signs in, writes, force-quits, reopens, and sees its data — offline and on.
- [ ] Guest → account upgrade preserves the guest's local data on both platforms.
- [x] Auth gate on both. *(2026-08-24 — iOS's `SanvyaApp` already had one; this audit said it did
      not, which was stale. Its two callbacks were dead parameters and are gone.)*
- [ ] Pending invite and launch-time materialisation ported.
- [x] `runRecurring()` / `runLoanAutoPost()` ported to both. *(2026-08-24, compiles-only)*
- [ ] Sync L3 (P2.7) unblocked — still needs a test Supabase + PowerSync project.

## 7. Work queue (waves — supersedes the coarse phase table in TODO.md)

**W0 — foundation, no compiler needed**
- W0.1 this file ✅
- W0.2 `mobile.yml` CI + green baseline run
- W0.3 token generator → typography/spacing/shadows/motion/component recipes + Inter bundling + dark parity + drift check
- W0.4 i18n pipeline: `packages/core/i18n` → `strings.xml` (values, values-hi, values-nl) + `.xcstrings`, key-parity check in CI
- W0.5 native component layer (§5) built once per platform against generated tokens

**W1 — app shell** (§3) on both platforms; delete drawers, dead tabs and placeholder views.

**W1.5 — adaptive layout** on both platforms. The *layouts* are web's, value for value; the
*thresholds and device identification* are the platform's — Material 3's 600/840 (plus a 480
height gate on Expanded) and `FEATURE_SENSOR_HINGE_ANGLE` / `sw600dp`, **not** web's 640/860/1024
(Akhilesh, 2026-08-23). Orientation: phones portrait, tablets and foldables free. Every class
change is a resize, not a relaunch — nothing may be lost across one.
Spec: `screen-specs/app-shell.md` §1, §1a, §1b. Both platforms done 2026-08-23.

**W1.6 — native Google account picker**, as the non-guest arm of `continueWithGoogle()` on both
platforms. Credential Manager (`androidx.credentials` + `googleid`) on Android, the Sign in with
Google SDK or `ASAuthorization` on iOS. The guest arm stays the browser flow forever — it is the
only one that can `linkIdentity`. **The trap:** Supabase validates the ID token against the **Web**
client ID, not the platform one; the platform IDs exist only so Google's own picker will show up.
Passing the platform ID fails as an audience mismatch that reads like a misconfiguration. Blocked
on Akhilesh creating the two client IDs (Google Cloud Console — not Firebase).

**W2.1 — create/edit surfaces, all three platforms**: full page below 600dp, dialog or side
panel at 600dp and up. One rule, width-driven, replacing both Android's drift and web's own
route-vs-modal split. iOS uses `.fullScreenCover` on phones, not `.sheet`. Rule and the current
state in `screen-specs/app-shell.md` §8a. Touches `SanvyaNavHost`, every create/edit screen on
both native platforms, and — when the live client is next open for changes — web.

**W2 — spec re-derivation** for every ⚠️/🔶/❌ route in §4 from today's source. Each screen's spec
must state what it does at Medium and Expanded, not only on a phone, and drop the screen's own
`NavigationView`/`Scaffold` title bar (see §3).

**W3 — close Android's gap to iOS**: Login, Onboarding/Walkthrough, Statements, Statement import,
Assistant, plus anything else marked ❌/⚠️ on Android only.

**W4 — screens missing on both**: Search, Recurring (+direction), Reflect, Notifications, Help,
Categories, Labels, Data import/export, Receipts split, Join/auth callback, Dashboard tile catalog.

**W5 — parity re-check** of every ⚠️ screen against its W2 spec; delete inline approximations in
favour of the W0.5 components.

**W6 — native surfaces & release**: push/deep links, **home-screen widgets (Glance / WidgetKit)**,
**local notifications**, Live Activities, quick capture, biometric + field crypto, and the wider
"use the hardware in ways web cannot" pass Akhilesh has queued behind parity — plus RevenueCat,
store prep, launch gate. **Nothing in W6 starts until W1–W5 are green**: these are the payoff for
the parity work, and building them on top of screens that still drift would mean building twice.

Each wave item is DONE only when CI is green for it **and** its spec checklist passes.

## 8. Traps (paid for in blood — do not re-learn)

1. Marking DONE without compiler output. See §2. This is the single recurring failure of this project.
2. Adding a Swift file without regenerating the Xcode project → app silently doesn't compile. Always
   go through `xcodegen`; never hand-edit `project.pbxproj`.
3. Cross-module smart casts in Kotlin (`domain` property read from `app`) don't compile — bind to a
   local `val` first. Hit twice (Loans, Insights).
4. Swift `actor` repositories (Goals, Investments) need `await` at every call site; the others don't.
5. "Save" buttons that call `dismiss()` and persist nothing — found independently in Create Account,
   Create Transaction, Create Goal on iOS. **Assume every unaudited form has it.**
6. Duplicated domain ports (`LoansModel` vs `Finance`) — search before porting a helper.
7. Bypassing the shared money formatter leaks amounts when hide-amounts is on. Three such leaks have
   shipped on web. Charts must go through the equivalent of `chartMoney()`/`chartTooltip()`.
8. `settlements` reads must filter `status <> 'disputed'`.
9. List screens driven by one-shot `list()` instead of `db.watch()` look stale after a create/edit.
10. Never a cross-row constraint on a synced table; never `ON CONFLICT` on a PowerSync view.
11. **Major→minor unit conversion is hardcoded as `× 100` in at least two places** — `/search`'s
    amount filter and `createRecurring`'s `toRow()`. That is wrong for JPY (0 decimals) and BHD
    (3 decimals), and it contradicts golden rule 1. Invisible today only because the ledger is
    effectively all-INR. Port the *correct* behaviour (`minorUnits(currency)`), and fix web in the
    same change set rather than letting three platforms disagree.
12. Native `NotificationPrefs` defaults `low_balance_threshold` to 500 on both platforms, and iOS
    persists that 500 on first load. The server default (migration `0037_notifications.sql`) is 0.
    Pre-existing native bug, found while tracing the prefs row.
13. `subscriptions` and `recurring_items` are **unrelated tables** despite the plan doc implying a
    merge. The dashboard, insights and assistant read `subscriptions`; `/recurring` reads only
    `recurring_items`. A native Subscriptions surface is its own task.
14. `materialize()` in the recurring engine has a silent no-op path — a transfer item missing
    `to_account_id`, or any item missing `account_id`, still advances `next_due` and is counted as
    posted while writing nothing. Unreachable through the form's own validation, but undefended in
    the engine. Do not reproduce the gap on native.
15. **iOS had NINE money formatters, not one.** `formatMoneyAware`, three
    `formatMoney`s, `formatMoneyINR`, `formatMoneyGeneric`, `formatMoneyINRForCards`,
    `formatCents`, `formatMinor`, plus four copies of `formatMajorPlain` and a
    `compactMoney`. Six of them hardcoded INR, all of them hardcoded ÷100, and only
    one honoured hide-amounts. Consolidated 2026-08-23 into
    `App/Components/MoneyFormat.swift` over a generated `Domain.format`. The shared
    formatter is deliberately **non-isolated**: `Prefs` is `@MainActor`, but the
    insight generators format inside `@Sendable` closures with no actor, so a
    `@MainActor` formatter would put those call sites permanently outside the
    masking rule. It reads the same UserDefaults key directly instead.
16. `JSONSerialization` promotes a high-precision JSON literal to
    **`NSDecimalNumber`**, and `.doubleValue` on that lands one ULP away from the
    binary-nearest double. This made exactly one golden vector
    (`finance[2] periodicRateFromAnnual`) fail with a message showing two
    identical-looking numbers. Normalised at the loader
    (`VectorFixtures.normalizeDecimals`) — never by loosening the comparison.
17. `@Observable` and Factory's `@Injected` both synthesise `_x` backing storage,
    so an injected property in an `@Observable` class must carry
    `@ObservationIgnored`. 38 of 42 already did; the 4 that did not were compile
    errors. Dependencies are not observable state — always ignore them.

## 9. Known remaining `× 100` sites (tracked, not forgotten)

The display path is clean. These still hardcode the divisor and need
`minorUnits(currency)`; each populates an input field or scales a chart axis
rather than rendering a formatted amount, so none is a masking leak:

- `InsightsViewModel.swift` — chart series scaling (6 sites)
- `TransactionsViewModel`, `EditTransactionView`, `EditAccountView`,
  `AllocateGoalView`, `GroupDetailView`, `PayViaUpiSheet` — editable-field
  population and parsing
- Android has its own equivalents, not yet audited

Web shares the bug: `/search`'s amount filter and `createRecurring`'s `toRow()`.
Fix belongs in `packages/core` first so all three platforms move together.

### Fixed 2026-08-23 — three that WERE display-path leaks, on all three platforms

§9 said the display path was clean and every remaining site fed an input field or a chart
axis. Three did not.

1. **`small_purchase_drift`** built its body as `` `…totaling ${totalSmall / 100}` ``. Hardcoded
   divisor (¥43,215 rendered as "432.15"); a `20000`-minor threshold the copy described as a
   bare "200" (¥20,000 in JPY, 20 dinar in KWD); it summed **across currencies** without
   converting; and it bypassed the money formatter entirely, so it had no symbol, no locale
   grouping, and **could not be hidden by the hide-amounts toggle**. Ported verbatim to Kotlin
   and Swift, so all three were wrong identically.

2. **`major()`** in all three insight generators was `minor / 100` — feeding every chart value
   and every `metric.raw`.

3. **`fmt(top.value * 100)`** in the weekday-pattern card, converting a major-unit average back
   to minor by hardcoding the same 100.

All three now derive from `minorUnits(currency)` via `fromMajor`/`toMajor`. `computeTier1Insights`
takes the currency and the caller's formatter — which was already this codebase's convention
("domain never formats currency, screens do"); native `GenContext` carried both all along and
the mindfulness port simply never asked. Passing the formatter rather than a currency+locale
pair is what fixes the hide-amounts leak, since web hands it `useMoneyFmt()`.

Web typechecks clean; the two native halves await CI.

### Open 2026-08-23 — hardcoded `"INR"` on both native platforms

A separate family from the `×100` bugs, and a wider sweep than one commit should carry. Some of
these are legitimate (a currency picker's list, a `?? "INR"` fallback matching web's default);
these are not:

- `apps/ios/.../DashboardViewModel.swift:84` — `ledgerRepository.netWorth(base: "INR")`. Net
  worth is computed in a currency the user may not use.
- `apps/ios/.../DashboardViewModel.swift:10-11` — `Money(amount: 0, currency: "INR")` and
  `base: String = "INR"` as initial state, so the first frame is wrong before data lands.
- `apps/android/.../loans/LoansViewModel.kt:181` — `formatMoney(minor, currency: String = "INR")`.
  A **default parameter** for a currency: every call site that omits it is silently INR, and the
  compiler cannot flag one.
- `apps/android/.../loans/LoansViewModel.kt:30` — `private const val BASE_CURRENCY = "INR"`, with
  a comment admitting it is hardcoded to match Dashboard.
- `apps/android/.../loans/AddLoanScreen.kt:63` — `fromMajor(it, "INR")` when parsing input, so a
  loan in any other currency is stored with the wrong scale.
- `apps/android/.../transactions/{Edit,}TransactionsViewModel.kt` — `Currency.getInstance("INR")`
  and `currency: String = "INR"`.
- `apps/ios/.../SplitsView.swift:102` — `openOrCreateDirectGroup(..., currency: "INR")`.

Fixed already, in the same file that surfaced it: `SplitsViewModel`'s overview roll-ups
(`netPosition`, `owed`, `owe`) and its direct-balance rows now use `baseCurrencyNow()`. The
per-group rows beside them already used `g.group.currency` correctly, which is exactly what made
the inconsistency easy to miss.

The rest needs a base-currency source on both platforms (web has `useBaseCurrency()`) and should
be one change set with a lint rule or test behind it — a hardcoded currency is invisible in
review, and a **default parameter** of `"INR"` is worse than a literal because no call site
shows it.

### Open 2026-08-27 — hardcoded ×100 / ÷100 across BOTH apps' UI layers

Found while wiring `learnFromSave` into the edit screens. **29 sites on Android,
20 on iOS**, all in `ui/` and `App/` — not Domain, which is clean.

They are not one bug, they are two:

1. **Faithful ports of web bug #8.** Web itself writes `Math.round(x * 100)` in
   `GoalsPage`, `GroupDetail`, `Walkthrough`, `parseCsv`, `parsePdf`. Porting
   the literal reproduces the bug; using `fromMajor` diverges from the browser.
   Every place the ports have already chosen `fromMajor` is recorded against
   bug #8, and the golden vectors pin the divergence deliberately.
2. **Port-introduced, with no web counterpart.** These are the ones that matter
   here, because nothing forced them. The clearest is
   `EditTransactionViewModel.kt:213` / `EditTransactionView.swift:271`: the
   transaction's `amount` is summed with `* 100` while the *items* directly
   beside it go through `fromMajor(..., currency)`. On JPY or KWD the header and
   its own breakdown disagree, inside a single write.

Also here: `ui/goals`, `ui/budgets`, `ui/insights` (chart series), `ui/splits`,
`ui/receipts`, `ui/loans` and their iOS equivalents.

**Not fixed in this pass, deliberately.** Each site needs a per-call judgement —
"does web hardcode here too, and if so do we reproduce or fix?" — and a sweep
that guesses would either break browser parity or leave the bug in half the
places. It should be one change set with a **grep guard in the parity job**
behind it (`* 100` / `/ 100.0` on anything money-shaped outside Domain), because
a hardcoded scale factor is invisible in review — it looks like arithmetic.

### Open 2026-08-27 — the auto-categoriser was not entitlement-gated on either phone

Found while porting `learnFromSave` to the edit screens, and **fixed in the same
commit**. Web gates both halves:

```
useAutoCategorize(autoCategorizeText, categories, isPaid && type !== "transfer")
if (type !== "transfer" && autoCategorizeText && isPaid) learnCategory(...)
```

The first port of the create screen carried neither check across. A free account
was getting a paid feature — which is the small half. The larger half is that it
was **writing category rules**, at weight 1000 for a phrase and with corrections
counted at five ordinary sightings, into a table it was never supposed to touch.
Those rules then shape suggestions after an upgrade, so the damage outlives the
gate.

Both gates now start CLOSED and stay closed when the entitlement can't be read.
A gate that fails open is not a gate.

### CI run 33067200029 (f9811d5) — 3 real errors, none of them in the PDF work

Worth recording because of WHERE they came from: `aa0315f` (the analyzer screen)
and `bf9759e` (the categoriser) were pushed together, so GitHub only ran the
head commit. Two commits' worth of errors surfaced against the third, and the
log named files the third commit had barely touched.

| Error | Cause | Guard added |
| --- | --- | --- |
| 12 × `No value passed for parameter 'onClick'` / `'() -> Unit' but 'Modifier' was expected` | `SanvyaChip(label, active) { … }`. Its signature is `(label, active, onClick, modifier = Modifier)` — `modifier` is LAST, so a trailing lambda binds to it | **`tools/parity/check-trailing-lambda.mjs`**, now in the parity job. It READS every `@Composable fun Sanvya*` signature, works out whether the last parameter is a function type, and only flags call sites of the ones where it is not |
| `No parameter with name 'nowIso'` | `importTransactions`'s parameter is `stampIso`; the analyzer called it `nowIso` because the helper that produces the value is called `nowIso()` | none — one wrong keyword, and the compiler's message is already the answer |
| `escaping closure captures non-escaping parameter 'content'` | `chartCard(_:content:)` declared `@ViewBuilder content: () -> some View` and handed it to `SanvyaCard`, whose init stores it (`@escaping`) | new **escaping-content scan** in `check-swift-traps.mjs`. Which components need `@escaping` is read from their own initialisers, so a component that stops storing its content stops being flagged |

Both guards were verified the usual way: break the file deliberately, watch the
guard name it and exit 1, restore, watch it go clean.

**The parity job passed**, including the two new generators and the 28 PDF
vectors' regeneration check — so the PDF work itself has no drift. It has still
never been through a compiler.

### `/join` — 2026-08-27

53 lines on web, and the smallest remaining route. Almost all of the work was
deciding where it lives on a phone, because the two platforms disagree about
what a route even is.

**It is not a tab and not a start destination.** Web gives `/join` no chrome
because it is a landing for a link from *outside* the app, and every visit ends
by leaving — into the group, or into sign-in. So Android registers `join/{token}`
and *navigates* to it (keeping `dashboard` as the start destination, so backing
out of a joined group lands somewhere real), and iOS presents it as a
`fullScreenCover` above the shell. Giving iOS a `NavTab` for it would have left
a spent invite in the navigation for the rest of the session.

**The ordering that matters.** Clear the stashed token BEFORE accepting, not
after. Web does this and says why: the token is being consumed, so leaving it
stashed sends the user back to this screen on the next launch to accept an
invite that is already spent. Both ports do the same, in the same place.

**Both entry points, or it works exactly once.** Android reads the token in
`onCreate` AND `onNewIntent` — the same trap the auth callback above it
documents, and for the same reason: a cold start arrives through one and a warm
start through the other. `LaunchedEffect` is keyed on the token, not on `Unit`,
so a second invite arriving while the app is open still moves the app.

**`InvitesRepository`, not a method on `SplitsRepository`.** SplitsRepository's
own header already said invites were out of its scope and it was right:
everything there reads and writes local PowerSync, while this is one HTTPS call
to an Edge Function. Sharing a class would have meant a repository needing both
a database and a Supabase client for one method.

**No vectors.** There is no pure function here — the whole screen is one call
and three branches. The nearest thing to logic is `edgeFnMessage`'s status-code
fallbacks, ported because the day one of them fires, "Edge Function returned a
non-2xx status code" is a dead end for the user and for whoever reads the bug
report.

**What is still blocked, and it is the visible half:** an invite link tapped in
WhatsApp opens the browser. Both `.well-known` files exist and both are
placeholders — thirty-two zero bytes where the release keystore fingerprint goes,
and the literal string `TEAMID` where the Apple Team ID goes. They live under
`apps/web`, which this effort does not touch. Recorded in ABSENT-BY-DECISION with
exactly what each needs.

### CI run 33074275835 (2c0edeb) — parity ✅ android ✅ ios ✅

The PDF work, the categoriser gate, the edit-screen learning and both new guards
all compile. `statements-pdf` reports **28 passed, 0 skipped, 0 failed**, so the
vectors ran rather than being silently skipped for want of a registration.

One observability gap closed in passing: Gradle swallows test stdout, so
`VectorRunnerTest`'s per-domain "total/passed/skipped/failed" line — which iOS's
log shows — was invisible on Android. `showStandardStreams = true` on
`:domain`'s test task. A green build already proved the vectors PASSED; what was
missing was proof they RAN.

### The assistant, part one — the parser — 2026-08-27

`/assistant` is 1,678 lines across six files and the last unbuilt route. This is
the layer everything else sits on: what the model says, turned into structure.

**What is ported.** `richMessage.tsx`'s JSX-free half — `compactNum`,
`parseBlocks`, `toCard`, `toAction`, `parseAssistantMessage` — is now
`AssistantMarkdown.kt`/`.swift` under **71 vectors**. Prose becomes blocks
(headings, tables, task lists, fenced code, quotes, rules), and the one `<ui>`
JSON block the model may append becomes validated cards and actions.

**Where the fixtures came from, because it is not uniform.** The JSX-free
functions were lifted out of `richMessage.tsx` **verbatim** and executed — every
extracted chunk was diffed back against the source to prove nothing changed but
the file it lives in. `assistantInlineSpans` is the exception and is labelled as
such: web's `inline()` returns React elements, so there is no value to capture.
Its regex and branch order were copied character-for-character and checked
against the source; the reference that produced its expectations emits spans
instead of elements. Those 15 vectors prove Android and iOS agree — not that
either matches a browser.

**`toFixed(1)` is three different functions.** `1.15` formats as `1.1` in JS
(nearest on the exact BINARY value, 1.14999…), `1.2` through Java's `%.1f`
(HALF_UP on the DECIMAL text), and C's printf — which Swift's `String(format:)`
uses — rounds ties to EVEN and disagrees with both. ECMA-262 also strips the
sign FIRST, so a tie on a negative rounds away from zero: `(-1.25).toFixed(1)`
is `"-1.3"`. Both ports implement the spec rule explicitly, and the vectors
include the tie cases (1050, 1150, 1250, −1250, 99950) that separate the three.

**Domain declares its own JSON tree.** The `<ui>` block is JSON, so something
has to parse it, and `:domain` has no JSON dependency in its main source set —
nor does Swift's Domain. Adding kotlinx.serialization to ship would have bought
a dependency and an asymmetry to save twenty lines. Instead `AssistantJson` is a
six-case sealed type; each platform adapts its own parser into it
(`JsonElement` / `JSONSerialization`'s `Any`) and everything downstream is
shared and pinned. `splitAssistantUi` needs no parser at all, which is what
makes that split possible.

**Two security controls, ported as controls and commented as such.** Only `/…`
routes and explicit `http(s)` URLs become links — `javascript:`, `data:` and a
bare `evil.test` degrade to plain text. And an action's `href` must start with
`/` or the action is dropped entirely. This string came from a language model,
which can be talked into emitting whatever a transaction description tells it
to.

**Still to come:** `AssistantChat.tsx` (644 — the streaming chat), `tools.ts`
(276 — the tool surface over the ledger), `summary.ts` (184 — the on-device
aggregate that is the only financial data sent), `speech.ts` + `MicButton.tsx`
(181 — voice, and the earlier audit claim that "web has no voice input" was
wrong). `summary.ts` also carries a **sixth** hardcoded `/100`.

### The assistant, part two — the prompt and the tool surface — 2026-08-27

**`summaryForPrompt` — the only financial data that leaves the device.** Web's
header makes the claim and this is the function that keeps it: aggregates only,
never raw transactions. No merchant names, no dates of individual spends, no
counterparties. Ported with **8 vectors** against web's real output, including
the caps (12 accounts, 12 goals, 8 upcoming) and the drop rules — each of which
is a token budget, not a display choice.

Two details in it are easy to lose and are load-bearing:

* **`today` is on the type and not in the prompt.** The date is carried
  separately.
* **`upcoming` drops its currency.** Web projects `{n, date, amt}` and nothing
  else, so a renewal in a second currency goes as a bare number. Reproduced
  rather than fixed — a phone that sent an extra field would be answering a
  different prompt.

**`JSON.stringify` on a number is a real problem, solved narrowly.** The general
algorithm is shortest-round-trip and is hard to reimplement twice identically;
`1234.0` is what both Kotlin and Swift produce and `1234` is what JS produces.
But every number in this prompt is `Math.round(minor)/100` or `+(x).toFixed(2)`
— an integer number of hundredths — and for those the formatting is three cases.
`jsonHundredths` implements exactly that and documents the contract. A general
"close enough" formatter would have put a different prompt in front of the model
on each platform and nothing would ever have failed loudly.

**The tool surface is GENERATED.** `tools/parity/generate-assistant-tools.mjs`
reads `ASSISTANT_TOOLS` and `CONFIRM_TOOLS` out of `tools.ts` and emits
`AssistantTools.kt`/`.swift` — 7 tools, 6 requiring confirmation. It is in the
parity job. The reason it is generated rather than transcribed is that those
descriptions are **prompt text, not documentation**: "Use sparingly — not
one-off details" is doing real work on the model, and a paraphrase on one
platform is a behaviour change nobody would ever attribute to a typo. The
schemas are emitted as JSON string literals because that is what goes over the
wire; building a typed tree on each platform only to re-serialise it would add
two chances to differ and buy nothing.

**`describeToolCall` is the most consequential sentence in this feature**, so it
is in Domain under 16 vectors rather than formatted at each call site. It is the
line a user reads before authorising a write to their ledger. The curly quotes
and middle dots are web's character for character — `Create goal "X"` versus
`Create goal “X”` is a visible difference on the one screen where trust is being
asked for. `isValidToolInput` has 16 more; web's own comment names the case it
exists for, the model firing `record_transaction` with amount 0 for what was
really a navigation request.

**Assistant vectors now total 111** across seven functions.

**Still to come:** `AssistantChat.tsx` (644 — the streaming chat and the confirm
cards), `executeTool` (repository writes for all seven tools),
`buildFinancialSummary` (the repository half of the snapshot — and web bug #8's
**sixth** hardcoded `/100` lives in its `major()`), and `speech.ts` +
`MicButton.tsx` (voice).

### `JsNumbers` — one home for JavaScript's number semantics — 2026-08-27

Writing the assistant's `compactNum` produced a **second** copy of `jsRound`, and
looking for the first turned up a third copy of `jsParseFloat`. Three helpers,
five definitions across two languages:

| Helper | Was | Now |
| --- | --- | --- |
| `jsRound` | `private` in `StatementPdf.kt`/`.swift`, about to be a second copy in `AssistantMarkdown` | `domain/js/JsNumbers.kt` · `JsNumbers.swift` |
| `jsToFixed1` | `internal` in `AssistantMarkdown` | same |
| `jsParseFloat` | `internal` in `csv/Csv.kt` AND `statements/StatementCsv.kt` (two definitions in two packages, both live) | same |

Kotlin is the one that let this happen quietly: two top-level `fun
jsParseFloat(String)` in different packages are both legal, and each caller
picked up whichever its imports named. Swift's single module would have refused
the redeclaration.

**No guard added for it**, deliberately — this codebase's bar for a parity guard
is "shipped to CI at least twice", and this was caught locally on the first
occurrence. It is written down here instead.

Each function's doc comment now carries the specific divergence it exists for,
in one place rather than three: `Math.round` is half-up and not
half-away-from-zero; `toFixed(1)` is nearest-on-exact-binary with ties toward
the larger digit AFTER the sign is stripped; `parseFloat` takes a leading prefix
where both platforms' parsers demand the whole string.

### CI run 33076171227 (f3bb08d) — one iOS vector, and it was the one the fixtures were for

parity ✅ · android ✅ (assistant **71/71**) · ios ❌ — a single failure:

```
assistant[19] assistantCompactNum: expected Optional(1.1k) but got 1.2k
```

`1150 / 1000` is `1.15`, and the double is `1.1499999999999999111…`. JS rounds
on that exact value and says `1.1`; Swift's `Decimal(Double)` converts via the
double's SHORTEST decimal form — exactly `1.15` — and `NSDecimalRound(.plain)`
then says `1.2`. Kotlin's `BigDecimal(double)` is exact-binary and was right all
along, which is why only one platform failed.

The fix does the rounding by hand from `String(format: "%.20f", v)`, which is
printf printing the exact expansion rather than a rounded one. Because
ECMA-262 strips the sign first and breaks ties toward the larger digit, "more
than half" and "exactly half" collapse into one test — **is the next digit ≥ 5**
— and the whole function is six lines.

**This is the fixture set doing its job.** Those tie cases (1050, 1150, 1250,
−1250, 99950) were added specifically because three languages disagree here, and
the one that caught it was the one I would not have thought to try by hand.
`showStandardStreams`, added in the same commit, is why Android's 71/71 is
visible above rather than inferred from a green build.

### The assistant, part three — the writes — 2026-08-27

`AssistantRepository` on both platforms: durable memory, chat threads, the seven
tool executions, and `buildFinancialSummary`.

**Every write goes through the repository that owns its table.** That matters
most for `record_transaction`: `LedgerRepository.createTransaction` carries the
overdraft guard and the transfer/items validation, and a tool doing its own
INSERT would let the model write rows the user's own Add Transaction screen
would have refused. `SubscriptionsRepository` was READ-ONLY until this pass and
gained a `create` rather than having the assistant reach past it — the first
exception would have been the one that made the rule stop meaning anything.

**Failure is a RESULT, not an exception.** The model reads the result line back
and has to be able to tell "no goal by that name" from "no account to record
into"; an exception reaches it as a generic failure and it retries the same call.
The strings are web's, verbatim.

**Two orderings that would otherwise be platform-specific.** `pairwiseEdges` is
order-sensitive at the rounding boundary, so both the expense grouping and the
net-balance map are insertion-ordered by hand — a `HashMap` on Android and a
`Dictionary` on iOS would each have made the last paisa of a three-way split
depend on hash order.

**`todayIso` and `now` are parameters, not clock reads.** Same rule every
date-sensitive port here follows: a function that reads the clock cannot be
tested against a fixture.

**Not vector-tested, and that is not an oversight.** This layer is repository
I/O — SQL against a live PowerSync database. What CAN be pinned already is:
`summaryForPrompt` shapes its output under 8 vectors, `describeToolCall` and
`isValidToolInput` under 32. The untested part is the SQL, and the honest way to
cover that is the integration testing that is blocked on a test Supabase +
PowerSync project.

**Four deliberate gaps recorded in ABSENT-BY-DECISION**, including web bug #8's
sixth `/100` — the ONLY one of the six reproduced rather than fixed, because
this number goes into a prompt rather than into the database, and a phone that
sent a different snapshot than the browser would get a different answer to the
same question.

**Still to come:** `AssistantChat.tsx` (644) — the streaming chat, the confirm
cards and the thread list — plus `speech.ts` + `MicButton.tsx` (voice).

### CI run 33082408269 (1dc5d93) — BOTH platforms, same vector, and my contract was the bug

parity ✅ · android ❌ (assistant 110/111) · ios ❌ (1 of 111). Same failure on
both, which is the tell: not a platform difference, a wrong shared assumption.

```
summaryForPrompt[caps]: expected …"saved":6172.799999999999… but got …"saved":6172.8…
```

`jsonHundredths` was written on a stated contract — *every number in this prompt
is an exact multiple of one hundredth* — which is **true of the callers and false
of the function**. `summaryForPrompt` is public, takes a struct of plain
`Double`s, and enforced nothing. The first fixture that violated it (`5 *
1234.56`, ordinary float multiplication) produced a different prompt on both
phones than in the browser, silently.

I documented that contract as a virtue at the time. It was an unenforced
precondition on a public function, which is a defect even when every current
caller happens to satisfy it — and the vector that caught it was the one I
included precisely because I could not predict its output.

**Fixed properly, not narrowly.** `jsonNumber` in `JsNumbers` is now ECMA-262's
`Number::toString` in full:

1. the SHORTEST decimal that round-trips — found by rounding the EXACT binary
   value to 1…17 significant digits and taking the first that survives, on both
   platforms, rather than trusting either one's printer (Kotlin's
   `Double.toString` is not shortest-round-trip before JDK 19; Swift's
   `description` is but formats exponents differently from JS);
2. the spec's plain-vs-exponent rules — plain for `1e-7 < |x| < 1e21`. `1e21` is
   `"1e+21"` and `1e-7` is `"1e-7"`: the positive exponent carries a sign and the
   negative one does not.

Verified against V8 across **431 values** (the CI failures, both notation
boundaries from both sides, ties, subnormals, `MAX_VALUE`, and 400 random
draws), then pinned with **41 new vectors** — so the next person to "simplify"
this has something to fail.

`jsonHundredths` is gone, and both repositories' `describeNumber`/`describe()`
helpers — which were the same narrow thing under two more names — are gone with
it. Assistant vectors now total **152**.

### CI run 33086393752 (158d366) — AssistantRepository compiled

parity ✅ · android ❌ · ios ❌ — but the ONLY failure on either was the
`summaryForPrompt` vector already fixed in `01f5728`. `** TEST SUCCEEDED **` on
the app scheme, `Compiling AssistantRepository.swift` in the Data target, and
Android's `:app` and `:data` both built. The largest file of that cycle — the
seven tool executions, the snapshot, the new `SubscriptionsRepository.create`
and the DI on both platforms — went through clean.

### The assistant, part four — the turn loop — 2026-08-27

`AssistantChat.tsx` is 644 lines. This is its brain, not its screen.

**PERSONA is GENERATED.** `tools/parity/generate-assistant-persona.mjs` emits
41 lines / 8,662 characters into both Domains, and it is in the parity job. This
is a bigger deal than the tool descriptions were: PERSONA is the assistant's
voice, its refusal scope, the exact `<ui>` card grammar it may emit, the route
list it may link to, and the rule separating a TOOL CALL from a NAVIGATION LINK.
Every one of those is behaviour. A hand-copy would drift the first time someone
reflowed a paragraph, and the failure would be invisible — the phone's assistant
declining something the browser answers, or calling a tool where the browser
links, with nobody attributing it to a transcription.

**`planAssistantTurn` is the safety-critical function in this feature**, and it
is in Domain under vectors for exactly that reason. It sorts a model turn's tool
calls into three disjoint buckets, and each is a policy:

| Bucket | What it is | Why |
| --- | --- | --- |
| `autoRun` | everything web's `CONFIRM_TOOLS` does not list — today, `remember` alone | the one tool that writes no money |
| `rejected` | a financial call whose arguments fail `isValidToolInput` | never becomes a card. Web's own comment names the case: `record_transaction` with amount 0 because the user asked to be taken somewhere. Surfacing that as "authorise a ₹0 expense?" would train people to tap through confirmations |
| `confirmQueue` | the rest, **one at a time** | someone who agrees to "create this goal" has not agreed to the transaction queued behind it |

A tool that ran without confirmation on one platform and with it on another
would not be a rendering difference — it would be a write to someone's ledger
they were never asked about.

**`trimAssistantHistory`'s second half is the part that would get dropped in a
rewrite.** Taking the last 16 messages is obvious; *then shifting until the
window opens on a plain user turn* is not, and without it the API rejects the
request outright — a conversation cannot begin on a `tool_result` or an
assistant turn. Nine fixtures cover it, including the all-non-user case where
web falls back to the single last message rather than sending nothing.

**28 new vectors** (9 history + 9 turn plans + 10 error keys), assistant total
now **180**. `friendly()` is ported as `assistantErrorKey` returning an i18n KEY
rather than a string, because web calls `t(…)` inline and the native ports have
to resolve through their own catalogues. Its four patterns are checked in web's
order — `errModel`'s would also match some network errors, so the order is not
incidental.

**One finding worth writing down.** An UNKNOWN tool name lands in `autoRun` —
`needsConfirm` is a Set lookup and returns false for anything unlisted. It is
currently unreachable (the API only accepts tool calls from the declared list,
and `executeTool` answers "Unknown tool: X" and writes nothing), so it is
faithful-to-web rather than a defect. Recording it because "unknown ⇒ runs
without asking" is the wrong default to inherit silently if that list ever
becomes dynamic.

**Still to come:** the chat SCREEN on both platforms — thread list, message
bubbles, confirm cards, quota chip, the disclaimer gate — plus the Edge Function
call and voice.

### CI run 33094345889 (01f5728) — the ported function was never called

parity ✅ · android **cancelled** (superseded by the next push — but it printed
`domain=assistant total=152 passed=152 skipped=0 failed=0` first, so Kotlin's
`jsonNumber` is right) · ios ❌ with **41 failures and a compile error**.

**The 41 vectors: a name collision, not a wrong algorithm.**

```
assistant[0] jsonNumber: expected NSTaggedPointerString(0) | actual: __NSCFNumber(double=0.0)
```

`FinanceVectors.swift` has had an internal `func jsonNumber(Double) -> Any`
since the finance port — an Infinity→NSNull helper, deliberately not
file-private so `BudgetVectors` could reuse it. Domain then gained a **public**
`jsonNumber(Double) -> String`. Inside the test target, the target's OWN
declaration wins over the imported module's: **no ambiguity error, no warning.**
Every `jsonNumber(…)` in `AssistantVectors` called the test helper, so 41
vectors compared a number against a string — and the log blamed the ported
function, which was never called.

The test helper moved to `jsonOrNull`; the public API kept its name. A guard was
added, and it is the **one guard in `check-swift-traps.mjs` that has not shipped
to CI twice**. The stated bar exists so guards do not sprawl for loud failures —
every other trap in that file is a compile error, attributable on sight. This
one produces a wrong value and points at innocent code, which is worth the
exception.

**The compile error was mine and unrelated.** Removing `describeNumber` from
`AssistantRepository.swift` in `01f5728` sliced from its doc comment to the
class declaration — and `summaryMajor`, `jsToFixed2Number` and
`parseRenewalDate` were sitting in that range. Restored verbatim. A three-line
lesson about deleting by text range rather than by symbol.

### The assistant, part five — the model call — 2026-08-27

`callModel` on both repositories, ported from `AssistantChat.tsx`.

**Failure is a RESULT here too.** The Edge Function always answers HTTP 200 and
carries the reason in the body's `error` — quota exhaustion, a missing API key,
a prompt-injection screen. All three are answers the chat renders, not
exceptions.

**The cache markers are not decoration.** `system` goes as an ARRAY of blocks,
each marked `cache_control: ephemeral`, and the LAST tool carries one too.
PERSONA alone is ~8.6KB and identical on every request; without the marker it is
re-billed on every turn of a multi-step tool exchange, and a tool exchange is
three or four turns.

**`input_schema` round-trips as a string.** The generator emits it as a JSON
string literal precisely so the repository can hand it back over the wire
unchanged rather than rebuilding a typed tree on each platform and re-serialising
it — two more chances to differ, for nothing.

**iOS needed `AnyJSON`, not `[String: Any]`.** `FunctionInvokeOptions` takes
`some Encodable`, which a bare `Any` dictionary is not; passing pre-serialised
bytes compiles but is sent as `application/octet-stream`, a different request.
supabase-swift's own `AnyJSON` was already in use in `RepairRepository`.

### CI run 33094942154 (b59e0ac) — the import guard had a blind spot in two directions

parity ✅ · android ❌ · ios ❌ (the ios failure was `01f5728`'s deleted
helpers, already fixed).

Android's was four lines of `Unresolved reference 'jsonArray'` in
`AssistantVectors.kt` — and `check-kotlin-imports.mjs` had reported **0 hits**
on that file, for two independent reasons:

1. **It skipped test sources entirely.** `walk(ROOT).filter(f => !f.includes("/src/test/"))`,
   on the theory that a vector adapter is not a screen. Wrong: `:domain:test` is
   compiled by the same build, a missing import there fails it just as hard, and
   the `*Vectors.kt` adapters are *precisely* where kotlinx.serialization's JSON
   accessors get used. Test sources are now in — 225 files became **261**, all
   clean.
2. **It had no way to see an extension PROPERTY.** `.jsonArray` is written
   dotted like an extension function but has no argument list, so neither the
   bare-word rule nor the `extension: true` rule matched it. A new
   `property: true` mode covers it, and eight kotlinx accessors are now watched
   (`jsonArray`, `jsonObject`, `jsonPrimitive`, `contentOrNull`,
   `booleanOrNull`, `doubleOrNull`, `intOrNull`, `longOrNull`).

**This is the third time this one guard has said "0 hits" on the exact file that
was failing**, each time in a different disguise — first a bare `(`-less call
(`rememberSaveable`), then a type annotation (`Color`), now a dotted property.
The pattern is worth naming: the check matches USES, and every time it misses,
it is because Kotlin has another syntax for using something. Verified the new
rule by running it against the broken file before fixing it.

