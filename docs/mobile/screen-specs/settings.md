# Settings — mobile screen spec (task #47)

Source-verified against `apps/web/app/settings/page.tsx` (272 lines) and its ~10 imported
sub-components (`ProfileTraits.tsx`, `NotificationPanel.tsx`, `SecurityPanel.tsx`,
`PaymentHandlePanel.tsx`, `DiagnosticsPanel.tsx`, `RepairPanel.tsx`, `ProblemsPanel.tsx`,
`FaultInjectionPanel.tsx`, `Billing.tsx`), plus `apps/web/src/{account,theme,prefs,sync}.ts`,
`apps/web/src/sync/{repair,deadletter}.ts`, `apps/web/src/diagnostics/{queue,log}.ts`, and
`supabase/migrations/0006_delete_account_rpc.sql`.

## Scope decision (confirmed with Akhilesh before building)

Web's Settings page is a large aggregator with sections of very different character. Built this pass,
both platforms:

- **Account** — display name edit, guest banner + days-left, sync status dot, sign out / delete account.
- **Appearance** — light/dark, now persisted (was a static "System default" label on both platforms).
- **Privacy** — hide-amounts (already existed, unchanged).
- **About you** — optional gender/country traits (`profiles` table).
- **Notifications** — existing toggle set (already existed, unchanged).
- **Base Currency** — 9-currency chip picker, now persisted.
- **Plan & Billing** — real entitlement tier/paid-status display; "Upgrade"/"Manage" button is a stub
  (see Deferred below — no purchase flow exists).
- **Problems syncing**, **Check for unsynced data**, **Diagnostics** — the dead-letter-queue /
  stranded-row-repair / support-log trio. Backing data-layer code (`RepairRepository`, `Quarantine`,
  `DiagnosticsLog`) already existed on both platforms and was **already live** (wired into
  `SupabaseConnector.uploadData`'s failure path) — this pass added the missing network-facing half
  (`scanForStranded`/`repairStranded`/`retryFailedWrite`/`discardFailedWrite`, plus `ps_crud` queue
  inspection) and the UI. So these panels show real data from day one, not an empty shell.
- **Help & Support** — contact-support mailto only.

## Explicitly deferred (queued as separate tasks, not built this pass)

- **Security & encryption** (`SecurityPanel.tsx`) — E2E passphrase setup/unlock/recovery-code, native
  Keychain/Keystore key storage. A full standalone crypto feature, not a Settings-screen UI task.
- **UPI Payment Handle** (`PaymentHandlePanel.tsx`) — bundles with Splits (task #30) instead, since it's
  settle-up infra that has no consumer until Splits exists on mobile.
- **Categories/Labels management, Import/Export** — web links to `/settings/categories`,
  `/settings/labels`, `/data`; none of these screens exist on mobile yet. Omitted rather than linking to
  nothing; queued as their own future screen tasks.
- **Language** — no i18n infrastructure on mobile (established convention from every prior screen).
- **Fault Injection** (`FaultInjectionPanel.tsx`) — excluded on purpose, not merely deferred. The web
  source's own doc comment: "GATING: hidden unless `NEXT_PUBLIC_ENABLE_FAULT_INJECTION` is set, or on
  localhost. A shipped build with this visible would be a way to break a real user's sync." Shipping this
  to a mobile Settings screen with no build-flag gate would be a real footgun, not a parity gap.
- **Real subscription/purchase flow** — web's `Billing.tsx` drives Razorpay checkout; mobile's equivalent
  would be StoreKit/Play Billing, a distinct native-IAP integration project. The Plan & Billing card shows
  real entitlement status but the upgrade button is a no-op stub, matching what was already there.

## Base currency / theme persistence

Both are simple local-only preferences, matching web's own `localStorage`-backed
`useBaseCurrency`/`useTheme` (same key names, same defaults) — not synced tables. Android:
`Prefs.kt`, extended with `theme`/`baseCurrency` `StateFlow`s alongside the existing `amountsHidden`
(SharedPreferences-backed). iOS: `Prefs` class in `SettingsView.swift` was previously **in-memory only**
for `amountsHidden` (lost on relaunch) — this pass fixed that by backing all three with `UserDefaults`.

Neither the base-currency picker nor the theme picker propagate anywhere else in the app yet (every
screen still hardcodes `"INR"` / the system color scheme). That propagation is a follow-up, not part of
this change — flagged here so it isn't mistaken for done.

## Problems / Repair / Diagnostics — what already existed vs. what this pass added

Discovered mid-implementation: the data layer for all three panels was already fully built and *live* on
both platforms (`RepairRepository.{kt,swift}`, `Quarantine.{kt,swift}`, `DiagnosticsLog.{kt,swift}`),
wired into `SupabaseConnector.uploadData`'s failure path (classify → quarantine → log), from an earlier
porting phase (P2.2–P2.6). It just had no UI and was missing the network-facing repair operations. Added
this pass:

- `scanForStranded()` / `repairStranded()` — diff local rows against the server (100-id chunked
  `in.()` queries against the `pocketcare` schema, parents-before-children via the existing
  `REPAIR_ORDER`), re-upload via direct upsert.
- `retryFailedWrite()` / `discardFailedWrite()` — direct upsert/delete against Postgrest for a single
  quarantined row, mirroring `deadletter.ts`.
- `inspectQueue()` / `discardOps()` / `summarizeQueue()` / `failingTableFrom()` — new
  `data/diagnostics/Queue.{kt,swift}`, a straight port of `apps/web/src/diagnostics/queue.ts`, reading
  `ps_crud` directly (PowerSync's own batch API gives no deletable row ids).

**Schema note**: every direct Supabase call in this pass (`RepairRepository`'s scan/repair/retry, and
`delete_user_account`) uses the `pocketcare` schema, matching `SupabaseConnector`'s own `DB_SCHEMA`
constant and web's identical calls — **not** the `sanvya` schema CLAUDE.md's golden rules describe for
everything else. Verified against the real migration
(`supabase/migrations/0006_delete_account_rpc.sql`: `create or replace function
pocketcare.delete_user_account(...)`) before relying on it, since this is a real, deliberate exception to
the stated convention, not an inconsistency to "fix."

### Kotlin/Swift API notes worth flagging for anyone hitting a real compiler error here

- Android: `Postgrest.rpc()` has no schema parameter — only `from(schema, table)` does. The schema
  override happens inside the RPC request lambda (`request = { schema = "pocketcare" }`), confirmed
  against supabase-kt's real source (`PostgrestRequestBuilder.schema` is a mutable var defaulting to
  `config.defaultSchema`).
- iOS: `client.schema("pocketcare").from(table)` / `.rpc(fn, params:)` (schema-scoped client copy),
  matching the exact pattern `SupabaseConnector.swift` already uses.
- iOS: `AnyJSON` is a closed enum with no `init(Any)` — dynamic row values need an explicit
  `sendableToAnyJSON` switch, not a direct wrap.
- Both platforms: reading an *entire* row generically (needed to re-upload a stranded row, since the
  columns aren't known ahead of time unlike every other repository's typed mapper) is new API surface —
  Kotlin's `SqlCursor.columnNames` and Swift's equivalent — not exercised anywhere else in the codebase.
  Flagged in both `rowToMap`/`rowToDict`'s doc comments as the riskiest guess in this change; first place
  to look if a real error surfaces from the repair-scan path specifically.

## Sync status (kept deliberately minimal)

Only `db.currentStatus.connected` and `.lastSyncedAt` are read (both confirmed against PowerSync's own
SDK docs). `dataFlowStatus.uploading/downloading` and any error surface exist on the SDK but their exact
Kotlin/Swift shape wasn't verified — "waiting to upload" instead comes from a direct `ps_crud` count,
which is what web's own `DiagnosticsPanel` falls back to as well.

## Data touched
- `profiles` (gender, country) — read/write, via the existing `insertRow`/`updateRow`/write-helpers
  convention.
- `notification_prefs` — unchanged (already existed).
- `entitlements` — read-only (`PrefsRepository.watchEntitlement()`, already existed from Insights).
- `failed_writes`, `sync_attempts`, `ps_crud` — local-only tables, read/write via the new repair +
  queue-inspection code.
- Supabase Auth: `auth.updateUser` (username), `auth.signOut`, `pocketcare.delete_user_account` RPC.

## Key files
- Android: `Prefs.kt` (extended), `data/diagnostics/Queue.kt` (new),
  `data/repository/RepairRepository.kt` (extended), `data/di/DataModule.kt` (extended),
  `ui/SettingsViewModel.kt` (rewritten), `ui/SettingsScreen.kt` (rewritten).
- iOS: `Data/Sources/Data/Queue.swift` (new), `Data/Sources/Data/RepairRepository.swift` (extended,
  `FailedWriteItem`/`StrandedRow` gained the payload/row fields needed for re-upload),
  `Data/Sources/Data/DI/DataModule.swift` (extended), `App/ViewModels/SettingsViewModel.swift` (new,
  split out of `SettingsView.swift`), `App/SettingsView.swift` (rewritten, `Prefs` upgraded to persist).

## Gating
Free tier throughout — Settings itself isn't gated (matches web: everyone can see their own settings).
The Plan & Billing card's content differs by tier, not its visibility.

## Edge cases
- Guest account: no email, days-left countdown shown, sign-out warns data is unbacked.
- Offline: username save/profile save fail silently and keep the locally-shown value (matches web's
  swallow-and-keep-local for `updateUsername`).
- Empty diagnostics/problems/repair states: Problems section renders nothing at all when clean (matches
  web's "silence is the correct empty state" comment); Diagnostics/Repair always render (status cards,
  "Check now" button).
- Delete account: RPC failure surfaces inline in the confirm dialog; local PowerSync clear
  (`disconnectAndClear`) is best-effort and does not block sign-out.
