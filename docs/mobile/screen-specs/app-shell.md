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

## 1. Width classes — the platform's, not web's

Web switches layout at 640 / 860 / 1024 CSS pixels. **Native does not use those numbers.**
Each platform uses its own size classes and its own device identification, because those are
what every other app on the device already switches at, and because they are measured against
how real devices cluster rather than how a browser window resizes
(decision: Akhilesh, 2026-08-23).

So the *layouts* are web's, pixel for pixel. The *thresholds they switch at* are the platform's.

| Class | Android (`WindowSizeClass`) | iOS | Layout |
|---|---|---|---|
| **Compact** | width < 600dp | `horizontalSizeClass == .compact` | Bottom bar, icons only, full-width content |
| **Medium** | 600 <= width < 840dp | `.regular`, window < 840×480 | Bottom bar **with labels**, content capped and centred |
| **Expanded** | width >= 840dp **and** height >= 480dp | `.regular`, window >= 840×480 | Persistent sidebar + inset window frame, **no** bottom bar |

On iOS the **size class does the real work**: it is the platform's own answer to "is this a
phone-shaped window", it already accounts for Slide Over and Split View, and it changes when the
*window* changes rather than when the device does. Only the split between the two regular-width
layouts needs a measurement, and it uses the same 840×480 Android reads from `WindowSizeClass`,
so the two apps agree about what counts as a tablet. iPad portrait (834pt) is therefore Medium
and iPad landscape is Expanded — sidebar in landscape, bottom bar in portrait.

Constants come from `androidx.window.core.layout.WindowSizeClass`
(`WIDTH_DP_MEDIUM_LOWER_BOUND`, `WIDTH_DP_EXPANDED_LOWER_BOUND`, `HEIGHT_DP_MEDIUM_LOWER_BOUND`)
rather than being typed in, so a platform revision moves the app with it.

Three tiers, not web's four: web's 860 "cap the content column" tier folds into **Medium**, which
is the only one of the four that was about content width rather than navigation.

**Expanded needs height as well as width.** The sidebar is a full-height column; give it a short
wide window — a folded foldable turned sideways, a squat freeform window — and it has the width
for a sidebar and nowhere to put it, leaving the content in a letterbox.

**Always the *window*, never the display.** `Configuration.screenWidthDp` on Android and the
window's own size on iOS both report what the app actually got. An app in a narrow split-screen
pane on a tablet is Compact, because the app is phone-sized even though the device is not.

## 1a. The expanded layout

Shown at the **Expanded** class of §1 (Android: width >= 840dp with height >= 480dp), which is
where web's own `>=1024px` layout lives.

Source: `globals.css:594-700` and `AppShell.tsx:416-483`. Every number below is a literal in
that CSS and becomes a `SanvyaMetrics.Expanded.*` token — none may be typed into native code.
Only the *threshold* is the platform's (§1); the layout itself is web's, value for value.

### Window frame

At this width the app stops being a page and becomes an inset console window.

| | Value | Source |
|---|---|---|
| Backdrop | `--surface-2` (the *body* background changes) | `body { background: var(--surface-2) }` |
| Frame inset | `16` on all sides, `minHeight = 100vh - 32` | `.shell { margin: 16px }` |
| Frame fill | `--bg` | |
| Frame border | `1px --border` | |
| Frame radius | `26` | |
| Frame shadow | `--shadow-lg` | |

The frame is **not** a clipping container. Web says so in a comment and it matters natively too:
clipping here would turn the frame into a scroll container and break the sticky top bar.

### Sidebar (`.side-nav`)

Fixed, inset one pixel inside the frame: `left/top/bottom = 17`, `width = 252`.
Fill `--sidebar`, `1px --border` on the trailing edge only, radius `25 / 0 / 0 / 25`
(leading corners only, so it sits flush inside the frame's 26). Padding `18 / 14 / 14`, gap `4`.

Column, three parts:

1. **Brand** — logo at 26, padding `2 / 8 / 14`, taps to dashboard.
2. **Search entry** — a row, not a field: icon 16 + "Search anything…" + a `⌘K` key cap.
   Padding `10 / 12`, `marginBottom 12`, radius `12`, `--surface` on `1px --border`,
   text `--text-3` at 13. Hover moves the border to `--accent-soft`.
   The cap: 10/600, padding `2 / 5`, radius `5`, `--surface-2` on `1px --border`, `--text-2`.
   *Why search and not "+": at this width the add affordance moves into the dashboard's own
   header row, and search is the thing every screen reaches for.*
3. **Scroll region** — `Home`, then `Notifications` (with badge), then `NAV_GROUPS` verbatim —
   the **same groups the More sheet uses**, so both read from one list.
4. **Foot** — pinned, `1px --border` top rule, `paddingTop 10`: guest card (when guest),
   Feedback, version. "Install app" stays unported here too.

Item (`.side-nav-item`): row, gap `10`, padding `9 / 10`, radius `10`, icon 19, label 13.5/500,
`--text`. Active: `--accent-ghost` fill, `--accent` text, weight **650**, plus a
`3 × 20` left rail marker at `left: -14`, radius `0 3 3 0`, `--accent`.
Group title: 10.5/600, uppercase, tracking `0.07em`, `--text-2` at 65% opacity, padding `2 / 10`.
Badge: `minWidth 18`, height 18, padding `0 / 5`, pill, `--negative`, white 10.5/700.

### Top bar (`.top-bar`) — **not ported yet**

Web renders this *and* the util row at this width, which means the notification bell appears
twice. That looks like a web quirk rather than an intention, so native renders the util row
(which works at every size) and leaves the top bar out until someone has looked at the real
page side by side. Its values are recorded below and generated as tokens, so porting it later
is a layout job, not a re-derivation.



Sticky at `top: 16`, right-aligned, gap `16`, margin `-4 / 0 / 18`, padding `10 / 0`,
fill `--bg` (opaque — it scrolls under content).
Actions gap `8`. Icon button `36 × 36`, circle, `--surface` on `1px --border`, `--text`;
unread dot `7 × 7` at `top 7 / right 8`, `--negative`. Avatar `36 × 36`, circle,
`--accent` fill, white 14/700, `2px --surface` ring, `--shadow`.

### Content column

`startInset 252`, `maxWidth 1440`, padding `24 / 32 / 40`. **No bottom clearance** —
the floating bar is gone, so reserving 96 for it would leave a dead strip.

Full-bleed routes (`/insights`) drop horizontal padding at every width and drop the
`maxWidth` cap below 1024; at 1024+ they keep the 1440 cap.

### What is *not* in the sidebar

The bottom bar's four customizable slots have no meaning here — every destination is already
one tap away in the sidebar. `NavPrefs` is untouched, unread, and unshown at this width;
switching back to a narrower window restores the bar exactly as it was. The **More sheet and
the bottom-nav customizer are unreachable** at `expanded`, so anything reachable *only* from
them would be lost — which is why the sidebar renders the same `NAV_GROUPS` list rather than a
new one.

## 1b. Orientation and device type

Policy (Akhilesh, 2026-08-23):

| Device | Orientations |
|---|---|
| Phone, no hinge | **Portrait only** |
| Foldable | All |
| Tablet | All |

Device type is read from the platform's own capability flags, not from a size:

- **Foldable** — `PackageManager.FEATURE_SENSOR_HINGE_ANGLE`. A property of the *device*, so it
  stays true when the phone is folded shut and running on the cover display. A posture or
  window-size check would say "phone" there and lock a foldable to portrait.
- **Tablet** — `smallestScreenWidthDp >= 600`, the value behind the `sw600dp` resource
  qualifier. Smallest width is the shorter dimension by definition, so it reads the same in
  both orientations.
- **Phone** — neither of the above.

Hinge is tested first, so a large foldable is Foldable rather than Tablet. Both rotate freely,
so nothing turns on it today — but the two diverge the moment anything cares about the fold.

**Android** applies the lock at runtime (`Activity.requestedOrientation`) and **restores it on
dispose**: it is Activity state, not composable state, so leaving it set would pin later screens
— a full-screen receipt camera, say — to portrait too.

**iOS** declares it instead, in `Info.plist` via `UISupportedInterfaceOrientations` (portrait
only) and `UISupportedInterfaceOrientations~ipad` (all four). Declared rather than set at
runtime so the system applies it before the first frame, instead of after one has been laid out
the wrong way round. `SanvyaDeviceType` mirrors the same policy in code
(`UIUserInterfaceIdiom`, the platform's own identification) for anything that needs to *ask*.

Worth knowing: from **Android 16 the system ignores an orientation restriction on displays at or
above `sw600dp`**. This policy is therefore not fighting the platform — on phones the lock still
binds, and on tablets and unfolded foldables we are not asking for it in the first place.

### Foldables and resize

`AndroidManifest.xml` declares
`configChanges="orientation|screenSize|smallestScreenSize|screenLayout|density|keyboardHidden|uiMode"`.
Without it every rotation, fold and split-screen drag **destroys and recreates the Activity**.
Compose re-lays-out from the new size on its own, so the recreation buys nothing and costs
everything not explicitly saved.

Every class transition is a **resize, not a relaunch**: scroll position, an open More sheet,
in-progress form input and the selected tab all survive it (LIFE-1..4 in §10).

iOS has no shipping foldable and no hinge API; there, a fold would arrive as a width change and
is covered by the table above. What iOS adds is **Stage Manager, Split View and Slide Over**,
where width changes at runtime with no rotation event — so nothing may cache a size class
across a layout pass.

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
| ⌘K → `/search` | desktop only | ported at Expanded only — `⌘K` on iPad/Android hardware keyboards, matching the sidebar's own `<kbd>⌘K</kbd>` hint |

## 8a. Forms: a route on Android, a sheet on iOS

The two platforms present `Create*` / `Edit*` / `Add*` deliberately differently, and it is worth
stating so it is not mistaken for drift.

Web treats every form as a **route** — `/accounts/new` is a page, with the shell around it and Back
in the utility row.

- **Android follows web**: forms are `composable("accounts/new")` destinations inside `AppShell`.
  They therefore had a `TopAppBar` sitting above the shell's own chrome, which is what the W2 pass
  removed. They now use `SanvyaPage` like every other screen.
- **iOS does not**: forms are `.sheet(...)` presentations. A sheet with its own navigation bar —
  Cancel on the left, Save on the right — is the iOS idiom for a modal edit, and it brings
  swipe-to-dismiss with it. Those `NavigationStack`s **stay**.

This is the one place the brief's two halves pull against each other: *"exact replica of web"* and
*"best practices for the respective platforms"*. A sheet is not a page — it does not show the
bottom bar, and it dismisses by gesture. Judged worth it on iOS, where a full-screen push for a
two-field form reads as heavy.

**Open for a ruling**: if exactness wins, iOS's forms become routes and lose the sheet. Nothing
downstream depends on the current choice.

## 9. Deliberately not ported

- ~~**Desktop sidebar and top bar** (`≥1024px`)~~ — **this decision is reversed.**
  Tablets, foldables and iPad are explicit targets (Akhilesh, 2026-08-23: *"android tablets,
  foldables, ios foldables, tablets should work flawlessly as well"*). The expanded layout is
  specified in §1a and is required on both platforms — at the *platform's* breakpoint (§1),
  not web's 1024px.
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
- [ ] All three width classes render at their exact thresholds (599/600, 839/840, 479/480 height).
- [ ] Resizing across a threshold keeps scroll, tab, open sheets and form input.
- [ ] Phones stay portrait; tablets and foldables rotate freely; the lock is restored on dispose.
- [ ] iPad: Slide Over, Split View and Stage Manager each pick the class from *window* width.
- [ ] A narrow split-screen pane on a tablet renders the Compact layout.
- [ ] TalkBack/VoiceOver: every bar item announces its label; the "+" announces its action.
- [ ] CI green on both platforms.
