# Screen spec — App navigation drawer (hamburger menu)

> Source: `apps/web/app/AppShell.tsx` (read 2026-08-05), `NAV_GROUPS` array (lines 135–167) + the `<aside className="sidebar">` block (lines 298–338). This is the actual source of truth — **iOS's existing `DrawerMenuView.swift`/`NavModels.swift` (pre-dates this session) is itself an incomplete, unverified port of this**, missing two nav items and the whole footer block. Both platforms are corrected against this spec, not against each other.

## Why this exists

Android's `SanvyaNavHost.kt` (built earlier this session) used plain push/pop route navigation with **no drawer at all** — confirmed missing by Akhilesh 2026-08-05 ("dashboard does not have the hamburger menu"). Investigating iOS's equivalent (`DrawerMenuView.swift` + `MainTabView.swift`, both pre-existing, not written this session) surfaced that iOS *has* a full slide-out drawer, but it was never checked against the real web nav either — it's missing the "Notifications" and "Reflect" items and the entire footer (guest banner / feedback / install / version). Fixing both platforms against the real source in the same pass.

## Structure (`NAV_GROUPS`, web `AppShell.tsx:135-167`)

A "Notifications" item (bell icon, unread-count badge) renders **above** the groups, not inside one (`AppShell.tsx:303`). Then 5 groups, first and last untitled:

1. *(untitled)*: Dashboard (`space_dashboard`) → `/`, Ask Sanvya (`auto_awesome`) → `/assistant`
2. **Money**: Accounts (`account_balance`) → `/accounts`, Transactions (`swap_horiz`) → `/transactions`, Templates (`bookmarks`) → `/templates`, Cards (`credit_card`) → `/cards`, Splits & groups (`groups`) → `/friends`, Search (`search`) → `/search`
3. **Planning**: Budgets (`donut_small`) → `/budgets`, Goals (`flag`) → `/goals`, Planned Cashflow (`waterfall_chart`, **BETA badge**) → `/cashflow`, Recurring (`autorenew`) → `/recurring`, Loans (`request_quote`) → `/loans`
4. **Growth**: Investments (`trending_up`) → `/investments`, Reflect (`self_improvement`) → `/reflect`, Insights (`insights`) → `/insights`, Statements (`description`) → `/statements`
5. *(untitled)*: Settings (`settings`) → `/settings`, Help & FAQ (`help`) → `/help`

Active item: bold weight, `--accent` text + `--accent-ghost` background. Tapping any item closes the drawer.

## Footer (below the nav list, `AppShell.tsx:319-337`)

- If guest session: a banner — "Guest · {N}d until data is deleted" + "Create account →" link to `/login`.
- "Feedback" ghost button (chat bubble icon) → opens a bug-report modal.
- "Install app" ghost button (download icon) — only when not already installed as a PWA.
- Footer text: "Sanvya v{APP_VERSION}".

**Deferred for mobile** (own TODO rows, not silently dropped): the guest banner and feedback/install buttons are web-specific-enough (PWA install has no mobile equivalent; feedback modal doesn't exist on mobile yet) that this pass ports the nav list only. Version footer text is cheap and worth keeping.

## What exists vs. doesn't, per platform (as of 2026-08-05)

Real screens today: Dashboard, Accounts, Transactions, Settings (both platforms). iOS additionally has real-looking Views for Budgets/Goals/Investments/Loans/Insights/Cards/Splits/Statements (pre-existing, never verified against web — separate audit tasks, `docs/mobile/TODO.md`). Everything else (Assistant, Templates, Search, Cashflow, Recurring, Help, Notifications, Reflect) has no real screen on either platform; iOS already points these at a generic `PlaceholderView` ("this feature is coming soon") — Android gets the same treatment via a shared `ComingSoonScreen`.

## Port notes

- Android: `ModalNavigationDrawer` (Compose Material3) wrapping the existing `SanvyaNavHost`'s `NavHost`, not a replacement for it — Android's push/pop back-stack per top-level section is idiomatic and already working (Accounts/Transactions CRUD sub-routes), so the drawer is an added entry point, not an architecture replacement. Hamburger icon added to the `TopAppBar` of every top-level screen (Dashboard/Accounts/Transactions/Settings), opening the shared drawer.
- iOS: keep the existing `MainTabView`/`DrawerMenuView`/single-`currentTab`-switch architecture (already built, working, just incomplete) — add the 2 missing `NavTab` cases + `NavItem`s + `PlaceholderView` wiring, don't rearchitect.
- Icon mapping is platform-native (Material Symbols name → SF Symbol name → Compose Material Icons), not a literal string port — same discipline as every other screen this session.
