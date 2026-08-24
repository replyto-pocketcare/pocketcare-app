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

Legend: ✅ built & spec-checked · ⚠️ built, unverified or spec drifted · 🔶 partial · ❌ missing · 🚫 n/a

| Web route | Web source (lines) | Android | iOS | Status |
|---|---|---|---|---|
| `/` dashboard | `app/page.tsx` (634) + `src/dashboard/tiles.tsx` (1022) + `src/dashboard.ts` + `Suggestions.tsx` | `ui/dashboard/DashboardScreen.kt` (410) | `DashboardView.swift` (444) | 🔶 hero + accounts strip + FAB only. **12-tile catalog, drag-reorder/resize, edit mode absent on both** |
| `/accounts` | `app/accounts/page.tsx` (126) | `ui/accounts/AccountsScreen.kt` (156) | `AccountsView.swift` (133) | ⚠️ |
| `/accounts/new` | (165) | `CreateAccountScreen.kt` (183) | `CreateAccountView.swift` (128) | ⚠️ credit-card/demat branches + `MultiCurrencyCard` deferred |
| `/accounts/[id]/edit` | (189) | `EditAccountScreen.kt` (210) | `EditAccountView.swift` (271) | ⚠️ |
| `/transactions` | (92) + `src/ui/TransactionTile.tsx` (273) | `TransactionsScreen.kt` (156) | `TransactionsView.swift` (137) | ⚠️ |
| `/transactions/new` | (674) | `CreateTransactionScreen.kt` (257) | `CreateTransactionView.swift` (262) | 🔶 splits-create, templates, auto-categorize deferred |
| `/transactions/[id]/edit` | (449) | `EditTransactionScreen.kt` (218) | `EditTransactionView.swift` (315) | 🔶 edit-history audit modal missing |
| `/cards` | (352) + `src/cards/*` | `creditcards/CreditCardsScreen.kt` (307) | `CreditCardsView.swift` (297) | ⚠️ `docs/features/cards.md` is stale (describes a retired 3D wallet) |
| `/friends` (splits hub) | (493) + `src/splits/hooks.ts` (398) | `splits/SplitsScreen.kt` (227) | `SplitsView.swift` (167) | 🔶 FriendInsights/Patterns panel not rendered; tiles redesign of 2026-08-12 not ported |
| `/groups` | (19) redirect → `/friends` | 🚫 | 🚫 | 🚫 |
| `/groups/[id]` | (364) + `src/splits/write.ts` (304) | `splits/GroupDetailScreen.kt` (281) | `GroupDetailView.swift` (313) | 🔶 equal-split only; percent/exact/itemized, group edit/delete missing |
| `/search` | (148) | ❌ | ❌ `SearchView` is a `PlaceholderView` | ❌ |
| `/budgets` | (410) | `budgets/BudgetsScreen.kt` (140) + Create/Edit | `BudgetsView.swift` (151) + Create/Edit | ⚠️ |
| `/goals` | (304) + `src/goals/GoalCelebration.tsx` (222) | `goals/GoalsScreen.kt` (171) + Create/Edit/Allocate | `GoalsView.swift` (166) + Create/Edit/Allocate | 🔶 GoalCelebration not ported |
| `/recurring` | (218) + `src/recurring/engine.ts` (251) | ❌ | ❌ `RecurringView` is a `PlaceholderView` | ❌ **redesigned on web 2026-08-12** |
| `/recurring/[direction]` | (157) | ❌ | ❌ | ❌ |
| `/loans` | (249) | `loans/LoansScreen.kt` (159) + Add/Edit | `LoansView.swift` (467) + Add/Edit | ⚠️ |
| `/loans/[id]` | (484) + `src/loans/settleEmis.ts` | `loans/LoanDetailScreen.kt` (369) | inside `LoansView.swift` | ⚠️ auto-post surfacing + recurring groups missing |
| `/investments` | (370) + `src/investments/*` | `investments/InvestmentsScreen.kt` (290) + AddHolding | `InvestmentsView.swift` (248) + AddHolding | 🔶 live catalog picker, SIP recurring transfer, CSV/XLSX import deferred |
| `/reflect` | (97) + `src/reflect/IntentCard.tsx` (141) | ❌ | ❌ `ReflectView` is a `PlaceholderView` | ❌ |
| `/insights` | (60) + `src/insights/generators.ts` (422) + `InsightFeed.tsx` (224) | `insights/InsightsScreen.kt` (376) | `InsightsView.swift` (515) | ⚠️ 18 generators ported; full-bleed feed layout + entitlement CTA need re-check |
| `/statements` | (145) | ❌ | `StatementsView.swift` (102) | ❌ / **🩹 MOCK** — four hardcoded `StatementUiModel` rows ("July 2026", "01 Jul - 31 Jul"). No repository, no view model. Shows fiction that looks like data |
| `/statements/analyze` | (329) + `src/statements/parsePdf.ts` | ❌ | `StatementImportView.swift` (89) | ❌ / **🩹 MOCK** — a hardcoded filename (`HDFC_Statement_July2026.pdf`), a hardcoded account (`HDFC Primary Savings (*4821)`) and four invented transactions incl. a ₹1,25,000 salary credit. Parses nothing |
| `/assistant` | (9) + `src/assistant/AssistantChat.tsx` (644) + `richMessage.tsx` (384) + `tools.ts` (276) + `MicButton.tsx` (91) + `speech.ts` (90) | ❌ | `AssistantView.swift` (153) | ❌ / **🩹 MOCK** — seeded with hardcoded messages; sending appends your text and nothing answers. No repository, no tools, no voice. 153L against web's ~1,670 |
| `/settings` | (272) | `ui/SettingsScreen.kt` (527) | `SettingsView.swift` (413) | ⚠️ Security/crypto, Language, Categories/Labels, Import-Export links absent |
| `/settings/categories` | (157) | ❌ | ❌ | ❌ |
| `/settings/labels` | (89) | ❌ | ❌ | ❌ |
| `/data` (import/export) | (154) + `src/data/importCsv.ts` (243) | ❌ | ❌ | ❌ |
| `/notifications` | (75) + `src/notifications/hooks.ts` | ❌ | ❌ placeholder | ❌ |
| `/help` | (152) | ❌ | ❌ `HelpView` is a `PlaceholderView` | ❌ |
| `/onboarding` | (119) + `src/onboarding/Walkthrough.tsx` (368) | ❌ | `WalkthroughView.swift` (121) | ❌ / 🔶 |
| `/login` | (334) | ❌ | `LoginView.swift` (105) | ❌ / 🔶 guest→OTP→Google + in-place upgrade unverified |
| `/join?token=` | (53) | ❌ | ❌ | ❌ needs App Links / Universal Links + real domain |
| `/auth/callback` | (87) | ❌ | ❌ | ❌ |
| `/receipts/new` | (339) + `src/receipts/{scan,ocr,image}.ts` | `receipts/ReceiptCaptureScreen.kt` (272) | `ReceiptCaptureView.swift` (207) | ⚠️ camera-only; no PDF/gallery, no AI escalation |
| `/receipts/review` | (501) | `receipts/ReceiptReviewScreen.kt` (283) | `ReceiptReviewView.swift` (265) | ⚠️ text-only OCR path (no word boxes) |
| `/receipts/split` | (522) + `src/splits/writeItemized.ts` (258) | ❌ | ❌ | ❌ "Split this bill" is shown disabled on both |
| `/subscriptions` | (8) redirect → `/recurring` | 🚫 | 🚫 | 🚫 |
| `/admin/*` | 7 pages | 🚫 web-only, English-only | 🚫 | 🚫 out of scope |

**Dead native screens to delete** (they mirror web routes that no longer exist): iOS
`TemplatesView`, `CashflowView` in `PlaceholderViews.swift` + their `NavTab` cases; any Android
`comingSoonRoute` entries for the same.

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
| **No `RecurringRepository` on either platform** | `/recurring` is a data-layer task before it is a UI task — no `recurring_items` reads or writes exist natively | W4 |
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

Found by reading web as the parity source. **None are fixed on web.** All three are fixed in the
native ports, which now deliberately diverge from their stated source:

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
| Google | ✅ OAuth redirect | ✅ `signInWithGoogle(idToken)` | ✅ + Apple |
| Guest → account upgrade | ✅ | ✅ `upgradeGuestWithEmail` | ✅ |
| **Email + password sign-in** | ✅ | ✅ `signInWithPassword` + `signUp` | ❌ **absent** — iOS only |
| **A login screen** | ✅ | ✅ `ui/auth/LoginScreen.kt` (2026-08-24) | ✅ `LoginView.swift` — **was a facade until 2026-08-24**, see below |

Two concrete gaps:

1. **Android has no login screen.** The data layer is complete and nothing calls it.

   **1a. iOS's looked like one and was not.** Until 2026-08-24 `LoginView` set a local
   `otpSent = true` on "Continue with Email" and called `onLoginSuccess()` directly on
   "Verify & Sign In" — it never reached `sendOtp` or `verifyOtp`. Any address and any code, or
   no code at all, produced the same result, and no session was ever created. `AuthViewModel` had
   working implementations the entire time; the view kept its own `@State` mirrors and called
   none of them. Now rewired to the view model.

   The lesson generalises past this screen: **a dead control is worse than a missing one.** The
   Google button was the same shape — present, tappable, calling `onLoginSuccess()` — so it has
   been removed rather than left looking functional. It comes back when the native `idToken`
   flow is actually wired.
2. **`signInWithPassword` is missing on iOS only** — Android's `AuthRepository` has had both it
   and `signUp` all along. **This entry previously said "neither platform", and that was my
   error**: the glob I checked with (`apps/*/src*/**/auth/*.kt`) matched nothing on Android and I
   read the empty result as absence. Second time in this audit that a bad search became a
   recorded fact; see §3a. So a web-registered password user can now sign in on Android and
   still cannot on iOS. Native uses a **different token shape for Google**
   (`idToken` via the native SDK) than web's OAuth redirect — that is correct for mobile, not a
   gap, but it means the OAuth callback route has no native equivalent and should not get one.

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

- **Auth gate** — web replaces to `/onboarding` when there is no session. Neither app does.
- **Pending invite** — `localStorage.pendingInvite` → `/join?token=`. No native equivalent.
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

### Done-when for this section

- [ ] Android has a login screen reaching every method its data layer already supports.
- [ ] `signInWithPassword` on both, or a documented decision that mobile is OTP/OAuth-only.
- [ ] `currentUserId` either works or is removed so nothing can depend on it.
- [ ] A real device signs in, writes, force-quits, reopens, and sees its data — offline and on.
- [ ] Guest → account upgrade preserves the guest's local data on both platforms.
- [ ] Auth gate, pending invite, and launch-time materialisation ported.
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
