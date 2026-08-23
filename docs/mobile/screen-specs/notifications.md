# Screen spec — Notifications

> **Source:** `apps/web/app/notifications/page.tsx` (75 lines), `apps/web/src/notifications/
> hooks.ts` (101), `apps/web/src/notifications/push.ts` (126), `apps/web/src/notifications/
> NotificationPanel.tsx` (123), `apps/web/src/ui/icons.tsx` (197, for `BellIcon`),
> `apps/web/app/globals.css` (`.card`, `.chip`, `.btn`).
> Derived 2026-08-23 by source translation, not from screenshots.
>
> **Scope:** primarily the `/notifications` route (the inbox) — **no native screen on either
> platform today**. `NotificationPanel.tsx` is included because it lives under
> `src/notifications/**`, but it is not this route: it renders inside `/settings`
> (`apps/web/app/settings/page.tsx:187`), and **that half already has a partial native port**
> (Android `SettingsScreen.kt` lines ~224–234, iOS `SettingsViewModel.swift` +
> `PrefsRepository.swift`). §8 covers it separately and narrowly — gap analysis against what
> already exists, not a full fresh spec.
>
> **Native targets:** `apps/android/.../ui/notifications/` and `apps/ios/App/Notifications/`
> for the inbox. The settings panel's existing files are listed above, not moved.

## 1. Component tree, render order (the inbox, `/notifications`)

```
NotificationsPage                             NO i18n — see §6
├── header row (space-between, wrap)
│   ├── h1 "Notifications"
│   └── button row
│       ├── chip "Mark all read"                only when unread > 0
│       └── Link chip "Settings" → /settings
└── body
    ├── empty state .card                       when items.length === 0
    │   ├── BellIcon (30px, --text-3)
    │   ├── "You're all caught up"
    │   ├── muted hint text
    │   └── ghost btn "Enable notifications" → /settings
    └── list .card (padding 0, overflow hidden)  when items.length > 0
        └── row per notification (see §3)
```

This screen renders **below** the shared AppShell util row (back affordance + bell — see
`app-shell.md` §7); `/notifications` has ≥1 path segment past root so the Back pill appears
there automatically. Do not add a second back control.

## 2. Data model and access

`Notification` (from `hooks.ts`): `id, kind, title, body, severity, href, read_at, created_at`.
Rows are synced down from Postgres (server creates them via the notify-dispatch edge function);
the client only ever reads, marks-read, and soft-deletes — **never inserts** a notification.

| Hook / fn | Query | Native repository |
|---|---|---|
| `useNotifications(limit = 50)` | `SELECT id, kind, title, body, severity, href, read_at, created_at FROM notifications WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT ?` | none — new |
| `useUnreadCount()` | `SELECT COUNT(*) AS c FROM notifications WHERE deleted_at IS NULL AND read_at IS NULL` | none — new, **but shared**: `app-shell.md` §7's bell badge and the More sheet's dot both need this exact count, and a repo-wide search found no native implementation of it either. Build one repository method and have the shell chrome and this screen both call it — do not duplicate the query. |
| `markRead(id)` | `updateRow("notifications", id, { read_at: nowIso() })` | maps to the generic row-update helper both platforms already have for synced tables |
| `markAllRead()` | one `writeTransaction`: `UPDATE notifications SET read_at = ?, updated_at = ? WHERE read_at IS NULL AND deleted_at IS NULL` | needs a raw transactional update — not a per-row loop, so the write queue doesn't enqueue N separate uploads for what is conceptually one action |
| `dismiss(id)` | `softDelete("notifications", id)` | generic soft-delete helper |

`limit = 50` is the inbox's default page size; nothing in the source paginates past it — there
is no "load more." Port as a hard cap, not a placeholder.

## 3. Row layout, states, and behaviour

Each row: flex row, gap 12, `align-items: flex-start`, padding `12px 14px`, `1px solid
--border` top divider (skipped on the first row — the divider is between rows, not around the
list). **Unread rows get an `--accent-ghost` background wash**; read rows are transparent. A
severity dot (8×8, radius pill, `margin-top: 6`) sits left of the content:
- unread → `SEV_COLOR[severity]`: `info` → `--accent`, `warn` → `--warning`, `urgent` →
  `--negative`. (`warn`'s CSS fallback `var(--warning, #c08a3e)` is dead code — `--warning` is
  already `#c08a3e` in `:root`, so the fallback branch can never fire. Don't port the fallback,
  just the token.)
- read → always `--border-strong`, regardless of severity. Read state overrides colour entirely.

Content column (flex 1, `min-width: 0` so long titles ellipsise instead of pushing the row
wide): title 14/600, single line, ellipsised; body (only when non-null) 12.5px muted, line-
height 1.4, **not** truncated — wraps freely; a relative timestamp (`timeAgo`, §4) at 11px
muted. **The whole content column is one tap target** (`onClick` on the div, not a `<Link>` on
the row) that calls `markRead(id)` and, only if `href` is non-null, also navigates there. A
notification with no `href` is markable-read but not navigable — `cursor: default` vs
`pointer` reflects this. A trailing "×" dismiss chip (`.chip`, padding `2px 8px`,
`aria-label="Dismiss"`) calls `dismiss(id)` and does **not** trigger the row's own click
(separate button, not nested inside the clickable div — check the JSX: the dismiss button is a
sibling of the clickable content div, not a child, so there's no click-bubbling bug to
reproduce or avoid).

### `timeAgo(iso)` — port exactly
```
< 60s        → "just now"
< 60m        → "{m}m ago"
< 24h        → "{h}h ago"
< 7d         → "{d}d ago"
else         → locale date string (Date.toLocaleDateString(), no explicit format options)
```
Not reactive — computed once per render, not on an interval. A notification that ages from
"5m ago" to "6m ago" while the screen is open will not update until something else re-renders
the list. Port this as a plain non-reactive computation, not a ticking timer — adding a timer
would be new behaviour web doesn't have.

### States

| State | Trigger | Render |
|---|---|---|
| Empty | `items.length === 0` | centred `.card`, bell glyph, "You're all caught up" + hint + "Enable notifications" link to Settings |
| Populated | `items.length > 0` | `.card` (padding 0) containing every row, no pagination |
| Unread present | `unread > 0` (from `useUnreadCount()`, a **separate** query from the list — it is not `items.filter(i => !i.read_at).length`) | "Mark all read" chip appears in the header |

No explicit loading state (same reasoning as `search.md` §4 — `useQuery` defaults to `[]`, and
local SQLite reads resolve fast enough that web never needed one) and no error state. No
premium/entitlement gating anywhere in this file.

**Two separate queries drive "empty" and "unread" independently** — `useNotifications()` (the
list, capped at 50) and `useUnreadCount()` (a true `COUNT(*)`, uncapped). If a user somehow has
more than 50 unread, the header's unread affordance and the visible list can disagree (the
header says N unread, fewer than N are visibly highlighted). This is an existing edge case in
web, not something to "fix" by re-deriving the count from the capped list — keep them as two
separate reads on native too, so the two platforms don't disagree with web about which count is
authoritative.

## 4. Tokens

| Element | Value | Token |
|---|---|---|
| Page wrapper | `gap 16`, `maxWidth 640` (inline), `fade-up` | gap: raw literal; **`maxWidth: 640` is a raw literal narrower than the shell's own page `maxWidth: 720`** (`SHELL.page`) — a deliberate per-screen choice (a list of short rows doesn't want the full page width), not a bug; carry the 640 as a literal, don't substitute the shell default. Animation: `MOTION.fadeUp`. |
| `h1` | `margin: 0` override, otherwise `TYPOGRAPHY.styles.h1`/`h1Compact` | as `search.md` |
| Header row | `justify-content: space-between`, gap 12, `flex-wrap: wrap` (inline) | raw literals |
| "Mark all read" / "Settings" chips | pill 999, border 1px, padding `8 14`, font 14 | `SHAPE.pill`, `TYPOGRAPHY.styles.chip` |
| Empty-state card | `.card`, padding 40 (inline), `display: grid`, gap 8, centred | `radius-lg`/`shadow` from `.card`; 40px padding and 8px gap raw literals |
| Empty bell icon | 30px, `--text-3` | raw SVG (`BellIcon`, not Material Symbols — see `search.md` §7 for why this icon family is separate) |
| "Enable notifications" | `.btn.ghost`, `margin-top: 6` (inline) | `.btn.ghost` = `--surface` bg, `1px --border-strong`, no shadow; 6px margin raw literal |
| List card | `.card`, `padding: 0`, `overflow: hidden` | `radius-lg`/`shadow`; the row dividers (not the card) supply internal structure |
| Row | padding `12px 14px`, gap 12, `1px solid --border` top divider (not on row 0) | raw literals — no catalogued "row" padding matches these exactly (`SHAPE.row` is a *border-radius* token, 10px, not a padding value; do not confuse the two) |
| Unread wash | `--accent-ghost` background | token |
| Severity dot | 8×8, radius 999, `margin-top: 6` | `SHAPE.pill`; 8px/6px raw literals |
| Title | 14/600, ellipsised | raw literal — not `TYPOGRAPHY.styles.chip` (14/400); same size, different weight, so it is its own value, not a token reuse |
| Body | 12.5px, `line-height: 1.4`, muted | raw literal, `--text-2` |
| Timestamp | 11px, muted | raw literal |
| Dismiss chip | `.chip`, padding `2px 8px` (inline override) | `.chip` base + inline padding override — the inline padding wins over the class's `8px 14px` |

## 5. `NotificationPanel` (rendered in `/settings`, not `/notifications`) — tokens

Included for completeness since it's in-scope source, but see §8 for what's already built.
`section.card`, padding 20, gap 14 (inline). Header: `h2` 16px (override of the 18px default),
muted 12.5px description. A custom `Toggle` (not `.chip`/`.btn` — hand-rolled): track 42×24,
radius 999, `--accent` on / `--border-strong` off, thumb 20×20 white circle sliding
`left: 2px ↔ 20px`, both transitioned at 0.15s. Section divider: 1px `--border` hairline
(inline `<div style={{height:1, background:"var(--border)"}} />`, not a CSS rule). Uppercase
group-header ("Groups & trips"): 11px muted, weight 600, `text-transform: uppercase`,
`letter-spacing: 0.06em` — **note this does not match the catalogued `TYPOGRAPHY.styles.eyebrow`
token** (11px/600/uppercase but `0.09em` tracking, not `0.06em`) or `sectionTitle` (10.5px, not
11). It is its own one-off value; do not silently substitute `eyebrow` for it, the letter-
spacing would visibly differ from web.

## 6. i18n — there is none. This is the headline finding.

**Every string in `page.tsx` and `NotificationPanel.tsx` is hardcoded English** — no
`useTranslation`, no `t()` call, anywhere in either file. Confirmed by absence: there is no
`notifications` namespace under `packages/core/i18n/src/locales/` at all (the directory listing
has 26 other namespaces; `notifications` is not one of them), and neither generated native
string table has a `Notifications` section (`S.kt` has no `object Notifications`,
`Generated/S.swift` has no `Notifications` enum) — the generator (`generate-i18n.mjs`) is
namespace-driven purely off that locales directory, so nothing was ever there to generate.

**Do not copy this.** Hardcoding English on native would both (a) regress behind every other
screen in the app, which is localized, and (b) be unfixable by the existing tooling without
first creating the namespace web itself doesn't have. Before native strings are written:
1. Add `packages/core/i18n/src/locales/notifications/{en,hi,nl}.json` with keys for every
   string below, and update `apps/web/app/notifications/page.tsx` /
   `NotificationPanel.tsx` to call `useTranslation("notifications")` + `t(...)` — bringing web
   in line with the rest of the app, not just adding a native-only translation file web doesn't
   share.
2. Run `node tools/parity/generate-i18n.mjs` to produce `S.Notifications.*` /
   `Generated/S.swift`'s `Notifications` enum, same as every other namespace.
3. Only then build the native screens against the generated accessors.

Strings needing keys (inbox): "Notifications" (h1), "Mark all read", "Settings", "You're all
caught up", "Alerts about bills, budgets, low balances and unusual spend will show up here.",
"Enable notifications", "Dismiss" (aria-label). Panel adds: "Notifications" (h2 — a second,
independent string from the h1 above, do not collapse them into one key), the description
paragraph, "Working…", "Push notifications", "Blocked in browser settings", "Deliver alerts to
this device", the four `enablePush()`/`sendTestNotification()` error strings, "Send test
notification", "Sent — check your device notifications.", "Upcoming EMIs & bills" + its
interpolated hint (`` `Alert ${days} days before due` ``), "Budget limits", "Low balance",
"Unusual transactions", "Groups & trips", "Group activity", "Shared expenses", and each of
those toggles' hint text.

## 7. Web-only mechanism — do not port

`push.ts` is Web Push (VAPID + Service Worker `PushManager`): `enablePush()` requests
`Notification.requestPermission()`, registers/reads `/sw.js`, subscribes via `pushManager
.subscribe()`, and upserts the subscription to **`pocketcare.push_subscriptions`** (a separate
Postgres schema from the app's main `sanvya` schema — this is intentional and consistent, not a
typo: the same `pocketcare` schema also holds crypto keys and a few other cross-cutting tables
on web, and **both native platforms already write to the same schema name** in their own push
repositories — `SupabasePushRepository.kt`/`.swift` — so this is already correctly matched, no
action needed there). `sendTestNotification()` fires `reg.showNotification()` directly from the
service worker with no server round trip, specifically to isolate "is permission/registration
broken" from "is the server dispatch broken." None of the Service-Worker/VAPID/PushManager
mechanism applies to native — **both platforms already have their own push path** (Android FCM
via `PocketCareFirebaseMessagingService` + `PushRepository`; iOS APNs via the equivalent). Do
not attempt to port `push.ts`'s mechanism; only its *behavioural contract* (permission states,
error reasons surfaced to the user, and the settings toggle wiring) is relevant, and that's
already partially built — see §8.

## 8. Gap check against the existing native settings-panel port

Both platforms already render prefs toggles in Settings (`SettingsScreen.kt` ~L224-234,
`SettingsViewModel.swift` + `PrefsRepository.{kt,swift}`), reading/writing the same
`notification_prefs` row shape as web's `NotifPrefs`. What's there and what's missing,
relative to `NotificationPanel.tsx`:

- **Present:** all seven boolean toggles (`push_enabled, emi_due, budget, low_balance, outlier,
  group_invite, group_expense`), grouped with a "Groups & trips" divider, matching web's field
  set and order.
- **Missing:** the busy/"Working…" state during `togglePush`; the four distinct error strings
  for permission-denied / unsupported / missing-server-config / other; the "Send test
  notification" button and its result message; the `emi_lead_days`-interpolated hint text on
  the EMI toggle (native currently has no hint text on any row).
- **Discrepancy to resolve, not silently inherit:** web's `ensurePrefs()` creates a new prefs
  row with `low_balance_threshold: 0` (matches the Postgres column default in migration
  `0037_notifications.sql`, `default 0`). Both native `NotificationPrefs` constructors default
  this field to **500** (`PrefsRepository.kt` line 22, `PrefsRepository.swift` line ~27), and
  iOS's `SettingsViewModel.load()` actively **writes** a fresh `NotificationPrefs(user_id:)` —
  i.e. persists 500 — the first time a user has no prefs row, which web never does. This is a
  real behavioural divergence already in the shipped native code, independent of anything new
  here; flag it for a fix (align the Kotlin/Swift default to 0) rather than treating 500 as
  intentional. It is not something this spec introduces or something the notifications inbox
  needs to solve, but it belongs on record since it was found while tracing this exact prefs
  row.
- Neither existing native settings screen uses the `SanvyaButton`/`SanvyaChip`/`SanvyaText`
  component layer for this section (`SettingsScreen.kt` uses raw Material3 `Button`/
  `FilterChip`/`Text` with `MaterialTheme.colorScheme`) — an existing inconsistency with the
  design-token system used elsewhere, out of scope to fix here but worth a follow-up ticket.

## 9. Done-when

- [ ] Inbox lists up to 50 notifications, newest first, unread visually washed with
      `--accent-ghost`.
- [ ] Tapping a row's content marks it read and, only if `href` is set, navigates; the dismiss
      "×" is a separate tap target that does not also trigger read/navigate.
- [ ] "Mark all read" only appears when `useUnreadCount() > 0`, and performs one transactional
      update, not N per-row writes.
- [ ] Unread badge (shell bell + this screen's header) reads from **one shared** repository
      method, not two independently-written queries that could drift.
- [ ] Empty state matches copy, icon, and the "Enable notifications" link to Settings.
- [ ] `timeAgo` buckets match exactly (60s / 60m / 24h / 7d thresholds) and are non-reactive.
- [ ] A `notifications` i18n namespace exists in `packages/core/i18n/src/locales/`, web itself
      has been updated to consume it (not just native), and every string on both native screens
      goes through the generated `S.Notifications.*` accessors — zero hardcoded English.
- [ ] No native push-permission/VAPID/service-worker code was written — FCM/APNs paths already
      in place are reused; only the settings toggle's UX contract (busy state, four error
      strings, test-notification button) is added.
- [ ] The `low_balance_threshold` default-value discrepancy (§8) is fixed or explicitly ticketed,
      not left silently inconsistent with the Postgres column default.
- [ ] No value in the new inbox screen is a literal where a token exists; every genuine literal
      (§4's "raw literal" rows, including the deliberate 640 max-width) is called out as such.
- [ ] CI green on both platforms.
