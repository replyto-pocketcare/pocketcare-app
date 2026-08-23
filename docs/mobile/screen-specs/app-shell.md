# Screen spec — App shell

> **Source:** `apps/web/app/AppShell.tsx` (693 lines), `apps/web/src/navPrefs.ts`,
> `apps/web/src/ui/BottomNavCustomizer.tsx`, `apps/web/src/ui/AddAction.tsx`,
> `apps/web/app/globals.css` (`.bottom-nav*`, `.util-*`, `.add-popover*`, `.shell*`).
> Derived 2026-08-23 by source translation, not from screenshots.
>
> **Scope:** the chrome around every screen. Every value below is a generated token
> (`SanvyaMetrics`, `SanvyaType`, `SanvyaColors`) — nothing here is a literal in native code.
>
> **Native targets:** `apps/android/.../ui/shell/` and `apps/ios/App/Shell/`.
> Android `ui/navigation/NavDrawer.kt` and iOS `MainTabView.swift`/`DrawerMenuView.swift`
> are **deleted** — they implement a navigation model web does not have.

## 1. Which web layout is "the mobile version"

`globals.css` has three breakpoints. Native mirrors the phone one:

| Width | What web shows |
|---|---|
| ≥ 1024px | Bottom bar hidden, persistent left sidebar + top bar, window-inset "console" frame |
| 640–1023px | Floating bottom bar **with** text labels |
| < 640px | Floating bottom bar, **icons only**, item height 46 (not 52), add button 48 (not 52) |

**Every phone is below 640px.** So the compact values are the ones a phone renders, and the
`≥1024px` sidebar is *not* ported — but a tablet in landscape does cross 640px, so the shell
selects by `WindowSizeClass` (Android) / horizontal size class + width (iOS) rather than
hardcoding compact.

## 2. Structure, outermost first

```
OfflineBanner                     (sticky, only while offline)
SyncProblemsBanner                (sticky, only when failed_writes is non-empty)
└── shell
    ├── GlobalLoader              (route-transition progress)
    ├── content column
    │   ├── util row              (skipped on dashboard)
    │   ├── sync status strip     (only when syncMessage() returns one)
    │   ├── TrialNotice
    │   └── <screen>
    ├── bottom nav                (fixed, floating)
    ├── add popover               (conditional)
    ├── More sheet                (modal)
    ├── BottomNavCustomizer       (modal)
    ├── InstallGuide modal        (web-only — see §9)
    └── BugReport modal
```

Bare routes render **no chrome at all**: `/onboarding`, `/login`, `/join` (and `/admin/*`,
which is not ported). They get the offline banner and nothing else.

While auth is resolving (`authStatus === "loading" | "none"`) the shell renders a centred
34px spinner on a full-height surface — no app flash, no partial chrome.

## 3. Bottom navigation bar

Fixed. `left/right = 16`, `bottom = 14 + safeAreaBottom`, centred, `maxWidth 460`.
Background `--surface`, `1px --border`, radius pill, `--shadow-lg`. Padding `6 × 8`, gap `2`.

Seven slots, in order:

| # | Content | Behaviour |
|---|---|---|
| 1 | **Home** — `space_dashboard` | fixed, routes to `/` |
| 2–3 | customizable slots 1–2 | from `navPrefs` |
| 4 | **"+"** | the contextual add action, §5 |
| 5–6 | customizable slots 3–4 | from `navPrefs` |
| 7 | **More** — `more_horiz` | opens the More sheet; carries an unread dot |

Item: column, centred, `flex 1`, height 46 (compact) / 52, radius pill, icon 22.
Idle `--text-2`; **active `--accent` on an `--accent-ghost` pill**.
Label (≥640px only) `navLabel` style, single line, ellipsised.

Active test — port exactly: `href === "/" ? path === "/" : path.startsWith(href)`.

The "+" is different: `52×52` (48 compact), **`margin-top: -14`** so it rises above the bar,
`3px --surface` ring, `--accent` fill, white plus at 24, `--shadow-accent`.

More's unread dot: 8×8, `--negative`, `top: 2`, `right: 22%`.

**Native notes.** Draw it over content and add its height to the content's bottom padding —
web already reserves `96 + safe-area`. Respect gesture insets on Android (edge-to-edge,
`WindowInsets.navigationBars`) and the home indicator on iOS. It is a custom composable/view,
**not** `NavigationBar`/`TabView` — neither can produce the raised centre button or the
floating capsule.

## 4. Customizable slots (`navPrefs.ts`)

- Catalog of **14** destinations: transactions, friends, insights, accounts, budgets, goals,
  recurring, loans, investments, cards, statements, search, assistant, settings.
- **4** slots. Defaults `["transactions", "accounts", "friends", "insights"]`.
- Persisted as a JSON array of ids under key `pc_bottomNav`
  (Android: DataStore, same key; iOS: `UserDefaults`, same key).
- `sanitize()` must be ported **exactly**: drop non-strings and unknown ids, dedupe, take the
  first 4; if the result is empty fall back to the defaults; **if it is short, top up from the
  defaults in order**. That top-up is not defensive padding — it is what stops a saved
  3-item list (from before the bar grew to 4) rendering a lopsided bar.
- Changes must be observable so the bar redraws immediately: `useSyncExternalStore` on web →
  `StateFlow` on Android, `@Observable`/`ObservableObject` on iOS.

**Customizer sheet** (from the More sheet's edit button): title, hint
`nav.customizeHint` (interpolates `n = 4`), then the catalog as a scrolling list, max height
50% of the screen. Row: icon 20, label, trailing 20×20 circle — `--accent` filled with a white
13px check when picked, otherwise `1.5px --border-strong` outline. Picked rows get an
`--accent-ghost` background and weight 650. When 4 are picked, unpicked rows go **disabled**
at 0.55 opacity with `--text-3` text — taps are ignored rather than silently evicting someone.
Footer: ghost Cancel + primary Save, **Save disabled unless exactly 4 are picked**.

## 5. The contextual "+"

An `AddAction` is one of three shapes, supplied by the current screen through a context
(`useRegisterAddAction`), falling back to a default:

- `link` — navigate immediately, no menu.
- `button` — run a callback immediately, no menu.
- `menu` — open the add popover.

Default action (when a screen registers nothing): a **menu** of two items —
*Add transaction* → `/transactions/new`, and *Scan bill / receipt* → `/receipts/new`, the
latter **lock-badged** (a lock glyph, deliberately not a tier name) unless
`tier ∈ {lite, pro}` or a trial is active.

Popover: `--surface`, `1px --border`, radius 18, `--shadow-lg`, padding 10, gap 8,
`minWidth 220`, anchored `84 + safeAreaBottom` from the bottom, centred, capped at
`screenWidth − 32`. Items: 10×12 padding, radius 12, icon + label at weight 600.
A transparent full-screen scrim dismisses it.

Closes automatically on navigation. (Web also closes it on scroll/resize when anchored to the
desktop header button — not applicable on phones.)

**Native:** on Android this is a popup positioned above the bar, not a `ModalBottomSheet` —
it is a small floating menu, not a sheet. On iOS, an overlay in the same `ZStack` as the bar.

## 6. Banners and status strips

**OfflineBanner** — sticky top, `--warning` background, white text, `7 × 14` padding,
12.5/600, a 7px white dot then the copy: *"You're offline — changes are saved on this device
and will sync when you're back online."* Shown whenever connectivity is lost.
Android: `ConnectivityManager.NetworkCallback`; iOS: `NWPathMonitor`.

**SyncProblemsBanner** — sticky, above the offline banner in z-order, `--negative`, tappable,
routes to Settings → Problems. Copy: *"{n} change(s) couldn't be saved — tap to review"*.
Reads `failed_writes` (local-only table), **polled every 30 s** — deliberately polled, not
reactive, because the table never syncs so there is no event to hang off, and the state is
rare enough that a poll costs nothing. Port the poll; do not "improve" it into a watch that
would not fire.

**Sync status strip** — in-flow, not sticky. Only when `syncMessage(status)` returns one.
`9 × 14` padding, radius 10, 13px, bottom margin 16. Warn tone → `--warning` border,
`--accent-ghost` background; otherwise `--border` + `--surface-2` + `--text-2`. An 8px status
dot, the message, and — for `action === "force-sync"` — a **Force Sync** button plus a
**Report Issue** mail link, both 28px tall.

**TrialNotice** — its own component, unchanged in position.

## 7. Utility row

Rendered above every screen **except the dashboard**, which places its own greeting and bell.
`min-height 40`, space-between, `margin-bottom 8`.

- **Left:** a single Back affordance, present when the path has ≥2 segments, or is one of
  `/receipts/new`, `/receipts/review`, `/receipts/split` (flow steps with nowhere else to go).
  Pill, auto width, `12/14` padding, gap 6, `arrow_back` at 18 + the word "Back".
- **Right:** the notification bell — 40×40 circle, `--surface`, `1px --border`, bell at 19,
  with an unread badge (min 15×15, `--negative`, white 9.5/700, `9+` cap) at `top/right 3`.

**A screen gets at most one back affordance — this one.** Web deleted every page-local
"← back to X" link to guarantee it. Native must do the same: no `TopAppBar` navigation icon
in addition to this row.

On Android, hardware/predictive back must do exactly what this button does.

## 8. Shell-level behaviour to port

| Behaviour | Web | Native |
|---|---|---|
| Auth gate | `authStatus === "none"` → replace to `/onboarding` | same, before any chrome renders |
| Pending invite | `localStorage.pendingInvite` → replace to `/join?token=` | DataStore / `UserDefaults`, same key |
| Recurring materialisation | 2.5 s after auth, once per launch: `runRecurring()` then `runLoanAutoPost()` | same delay, same order, once per process |
| Scroll restoration | per-path, `pc_scroll:<path>`, retried ≤20× at 60 ms as async content grows | `rememberSaveable` / `@SceneStorage` per route |
| Close overlays on navigation | More sheet + add popover | same |
| Diagnostics | `installDiagnostics()`, `startErrorReporting()`, route tagged on every change | same, at process start |
| ⌘K → `/search` | desktop only | **not ported** — hardware-keyboard iPad support is a later task |

## 9. Deliberately not ported

- **Desktop sidebar and top bar** (`≥1024px`) — a different layout for a form factor these
  apps do not target in v1. Revisit for iPad/foldable.
- **"Install app" / `InstallGuide`** — a PWA affordance. Both native apps are already installed.
  The More sheet's footer loses that row and keeps Feedback + version.
- **Service-worker registration** — no equivalent.

## 10. Done-when

- [ ] Bar renders 7 slots with the raised centre button, correct at 46/52 heights.
- [ ] Slot customization persists, survives restart, sanitises a short/corrupt saved list.
- [ ] All three banners appear under their real conditions (airplane mode; a quarantined write).
- [ ] Back affordance appears on exactly the routes §7 lists, and nowhere twice.
- [ ] Unread badge matches the notification count, `9+` capped.
- [ ] Default "+" menu locks receipt scanning below Lite/Pro/trial.
- [ ] No value in the shell source is a literal — everything reads a generated token.
- [ ] Rotation, fold, background/restore and process death lose nothing (LIFE-1..4).
- [ ] TalkBack/VoiceOver: every bar item announces its label; the "+" announces its action.
- [ ] CI green on both platforms.
