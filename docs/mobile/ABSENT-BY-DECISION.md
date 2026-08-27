# Absent by decision

Every native gap that is **deliberate**, with the reason and what would close it.

This exists because "it's not there" and "we decided it shouldn't be there yet" look identical in
a codebase, and the difference matters when someone asks *"is Android done?"*. A gap in this file
has been reasoned about. A gap not in this file is just a gap.

**The rule this whole list serves:** a dead control is worse than a missing one, and fabricated
data is worse than either. A button that does nothing costs a user their trust once; an invented
₹1,25,000 salary credit in a finance app costs it permanently.

Keep this current. Adding a row is part of the change that creates the gap, not a follow-up.

---

## Fabrications removed (were worse than absent)

| What | Was | Now | Closes when |
|---|---|---|---|
| iOS `StatementsView` | A searchable list of "July 2026" / "2025 Annual Statement" cards with a premium padlock — **a feature that does not exist in this product** | Real port of web's date-ranged statement | ✅ Done 2026-08-24 |
| iOS `StatementImportView` | A "parsed" HDFC PDF with four invented transactions incl. a ₹1,25,000 salary credit, and "✓ 4 Transactions Parsed • Zero Checksum Drift" | **File deleted.** Nothing routed to it — it was orphaned | A real port of `/statements/analyze` (~400 lines of CSV/PDF parsing + reconcile) |
| iOS `AssistantView` | Three hardcoded chat messages incl. "You've spent ₹6,400 on Food & Dining… 80% of your ₹8,000 monthly dining budget", in a styled insight card; composer appended to a local array and answered nothing | Honest placeholder, same as Search/Help | A real port: ~1,670 lines across `AssistantChat.tsx`, `tools.ts`, `richMessage.tsx`, `summary.ts`, `speech.ts`, `MicButton.tsx` |
| iOS `LoginView` Google button | Present, tappable, called `onLoginSuccess()` directly | Removed 2026-08-23, then **built for real** 2026-08-24 | ✅ Done |
| Android More sheet + side nav | Five entries (`search`, `reflect`, `assistant`, `help`, `notifications`) and the guest "Create an account" chip navigated to routes **the nav graph did not contain** — `IllegalArgumentException` on tap, including from the customisable bottom bar and the tablet side nav's always-visible search icon | Routed to `ComingSoonScreen` / the real login screen | ✅ Done 2026-08-25 |
| iOS guest "Create an account" chip | Not tappable in the More sheet; opened **Settings** in the side nav. Web links both to `/login` | Opens the login screen as a full-screen cover; closes when the guest flag clears | ✅ Done 2026-08-25 |
| Recurring → direction category donut | Absent, because `DonutChart` was `private` inside the Insights screen on **both** platforms | Drawn. All five chart primitives moved to shared components 2026-08-26 | ✅ Done — the reason was never the donut, it was where the drawing lived |
| iOS `AssistantView` mic button | Toggled `isRecording`, swapped to a stop icon, turned accent — captured no audio | Removed with the rest of the view | With the assistant port. **Web does have voice** (`speech.ts` + `MicButton.tsx`) — an earlier audit entry claiming otherwise was wrong |

## Controls deliberately not built

| Screen | What's absent | Why |
|---|---|---|
| Recurring → direction | Web's **kebab menu** | Three actions on a card that has room for three buttons. Hiding them behind a third tap is worse than showing them |
| Recurring form | **Preset name chips** ("Salary", "Rent", "Electricity"…) | They only fill the name field — pure convenience, no hidden behaviour — and web's list is **hardcoded English** in `RecurringModal.tsx`. Porting it verbatim would put untranslated strings in a screen that is otherwise fully localised. It needs a catalogue entry first |
| Recurring form | **Alert time** | `alert_time_utc` is written as `null`. A time-of-day picker is a control neither platform's spec has settled, and **the reminder that would consume the column is not built on either platform** — so the field would store a preference nothing reads |
| Recurring form | A **date picker** for "First due" | Plain ISO text on both, same as Statements. SwiftUI has `DatePicker` and Compose does not; adopting it on one platform only would put the two screens out of step on a field the user rarely changes |
| Recurring overview + direction | The **shell's contextual "+"** | Web registers each screen's Add into the bottom bar via `useRegisterAddAction` — the overview registers a two-item menu (payment / income), the direction screen a single button. Both native shells have the mechanism (`AddAction`), **but no screen on either platform registers into it, and iOS's `.button` case in `AppShell.runAdd()` is literally `break`** — a no-op. Until that channel is wired end-to-end, Add is an in-page button on the direction screens and the overview has none. Tracked as its own task |
| ~~Dashboard → Spending tile `lend` exclusion~~ | The tile grouped transactions in Kotlin/Swift, so there was no subquery to hang web's exclusion on, and it counted money you had fronted for someone as your own spending | Grouped in SQL, exclusion applied, 2026-08-26. **Every spending query on the dashboard now carries it** | ✅ Done |
| Dashboard → month buckets | Correct handling of the **UTC/local boundary** | `strftime('%Y-%m', occurred_at)` and `date(occurred_at)` are evaluated by SQLite in UTC, while "this month" and "today" come from the local calendar. East of UTC, a transaction in the first hours of a day or month lands in the previous bucket. **This is web's behaviour, bug included** — every one of these queries is web's. Fixing it natively alone would make the browser and the phone disagree, which is worse than agreeing on something slightly wrong. For Akhilesh's list |
| Dashboard grid | **Drag to reorder** | Web offers drag AND Move-earlier / Move-later buttons. The buttons are the accessible path, behave identically on both platforms, and are what shipped. Drag is a nicety on top of a working reorder, not a prerequisite for one |
| Dashboard grid | Web's `grid-auto-flow: **row dense**` | Dense back-fills a gap with a LATER, smaller tile — so a tile the user dragged to the bottom can jump to the top because something above it happens to be four columns wide. On a screen whose whole point is that the user chooses the order, silently reordering it is wrong, and it would make a drag preview lie about where a tile lands. Both platforms keep the order and leave the gap. Vector-pinned in `dashboard-grid.json` |
| Dashboard grid | Web's **measured row heights** | Web gives each tile a row span measured by a `ResizeObserver` against `grid-auto-rows: 8px`. That needs rendered CSS pixels before layout, which neither Compose nor SwiftUI can produce. Native rows size to their tallest tile — which is also why native tiles need no equivalent of web's `useFitRows()` clipping |
| ~~Dashboard tiles~~ | Eleven of fourteen were absent from the Add-a-widget picker | **All fourteen render**, both platforms, 2026-08-26. `TileId.isBuilt` stays as an exhaustive `when`/`switch` with no fallthrough, so a fifteenth tile in web's catalog still fails the native build until somebody decides | ✅ Done |
| Statements | Print | `window.print()` has no phone equivalent. Share/PDF export is a feature to design, not a button to add |
| Auto-categorisation | **`learnFromSave`** — the write half | The classifier READS `category_rules`; nothing on either phone writes one, so both run purely on the generated cold-start seeds. Web learns an exact phrase rule plus a token rule per token on every saved transaction, and boosts weight by 5 on a correction. Porting it means touching the add-transaction and edit-transaction save paths on both platforms, which is its own pass. Until then the two phones categorise identically to a **fresh** web install, not to a web user who has been correcting it for months |
| Auto-categorisation | `autoJob.ts`, `anchors.ts`, `semantic.ts` | The background re-categorise job and the embedding-based fallback. Neither is reachable from any screen being ported now, and `semantic.ts` needs a model on device |
| ~~Statements~~ | ~~"Analyze" link~~ | **Built on both, 2026-08-27.** The screen is reachable from Statements exactly as on web | ✅ Done |
| `/statements/analyze` | **PDF statements** | Web's `parsePdf.ts` runs pdf.js in the browser. iOS has PDFKit and could do it in a few lines; **Android has no built-in PDF text extraction at all**, so it needs a third-party library and a licence decision (PdfBox-Android is Apache-2.0 and ~15MB; iText is AGPL). Shipping it on iOS alone would put the two apps out of step on the headline feature of that screen. Both parse CSV; both say so. Closes when the library call is made |
| Statements | "Go Premium" button | Web links to `/settings`; there is **no native upgrade flow yet**, so the button would go nowhere |
| ~~First run, **both platforms**~~ | ~~The **walkthrough**~~ | **Built on both, 2026-08-23.** All 7 steps, both writes, and the `done`/`skipped` split, gated by `shouldShowWalkthrough()` in Domain under 103 vectors. iOS's orphaned 121-line half-draft is gone | ✅ Done |
| Pre-auth deck | The **"Install the app" chip** and `InstallGuide` modal | Web's deck ends with PWA install instructions — Add to Home Screen on iOS Safari, the install prompt on Chrome. On a phone running this app, the app IS installed. There is nothing for the chip to say and no honest destination for it |
| Pre-auth deck | Web's **`?mode=signin`** split between "Create an account" and "Sign in" | Both land on the same login screen. Android's has its own register/sign-in toggle and no entry parameter; iOS's is a single OTP-first form with no modes at all. Giving the deck two buttons that visibly do the same thing would be worse than saying so here. Closing it means adding a start-mode parameter to both login screens — and on iOS, the register mode itself |
| Android forms, crossing 600dp **while open** | The open form closes rather than transforming into a dialog | `formDestination` captures the width class when the graph is built, so crossing the threshold rebuilds the graph. Rotating a tablet mid-form loses unsaved input. The alternative — registering both shapes and swapping — changes destination identity, which loses the same input less predictably. Recorded rather than hidden |

## Platform-honest divergences (present, but not web's implementation)

| What | Web | Native | Why |
|---|---|---|---|
| Date inputs (Statements) | `<input type="date">` → browser picker | ISO text field, **both platforms** | SwiftUI has `DatePicker`; Compose has no equivalent primitive. Taking it on iOS alone would put the two Statements screens out of step over a control neither spec has settled |
| Google sign-in | OAuth redirect via `/auth/callback` | Browser flow to a custom-scheme callback | A native app cannot host an HTTP route. `/auth/callback` **has no native equivalent and must not get one** |
| Google sign-in (guest) | `linkIdentity` | Same — browser flow, deliberately not the native picker | GoTrue has no ID-token equivalent of `linkIdentity`. Using the picker for a guest would orphan every row they entered |
| Catch-up engines | Both fired concurrently | Sequential | Both write transactions into the same local DB and nothing depends on overlap. Per-engine error isolation is kept |
| EMI occurrence timestamp | noon **local** | noon **UTC** | Web's is a different UTC instant per device; two phones in different zones would stamp the same EMI differently |
| Re-entrancy guard | `let running = false` | `Mutex.tryLock()` / actor isolation | Web's flag is safe only because the browser is single-threaded |
| ~~iOS derived reads: account balances, rates, monthly totals~~ | One-shot on iOS, reactive on Android | **All reactive**, via `combineLatest`. Still one-shot on iOS: `watchNetWorth`, `groupBalances`, `splitOverview`, `friendInsights`, `personLedger` | 🔶 narrowed |
| ~~Splits tile reactivity~~ | Android combined two watches; iOS re-read a one-shot snapshot | **Both reactive, 2026-08-26.** `combineLatest` for `AsyncThrowingStream` now exists (`Data/Streams.swift`) — the missing operator was the whole reason, not a decision either platform made. `LedgerRepository`'s `watchNetWorth` / `watchAccountBalances` and Splits' `groupBalances` / `splitOverview` / `friendInsights` / `personLedger` are **still one-shot on iOS** and are the remaining work | ✅ for this tile |
| Loan funding account | Falls back to `localStorage` for pre-0047 loans | Column only, **no fallback** | A per-device memory of which account funds a loan would post different EMIs on different phones |

## Blocked on someone else

| What | Blocked on |
|---|---|
| **W1.6** — native Google account picker (Credential Manager / Sign in with Google) as the non-guest arm | Akhilesh creating an Android OAuth client ID (+ SHA-1 per signing key) and an iOS one. **Google Cloud Console, not Firebase** — Firebase is not involved in auth anywhere here |
| Google sign-in working at all | `com.sanvya.app://auth-callback` added to Supabase → Authentication → URL Configuration → Redirect URLs |
| `anchor_day` migration | Akhilesh's go-ahead. `advance()` already accepts `anchorDay`; nothing passes it |
| Web's `advance()` overflow fix | Akhilesh. Native clamps; **web still skips February and sticks on the 3rd** for days 29–31 |
| Sync L3 (P2.7) | A test Supabase + PowerSync project |

## Verified-by-CI-only (built, never run on a device)

Not gaps, but not evidence either. Nothing below has been exercised against a real backend:

- Google sign-in, both platforms — no live sign-in completed
- `runRecurring()` / `runLoanAutoPost()` — no device has run either
- The Recurring and Statements screens — compiled, never opened
- Guest → account upgrade preserving local data

## Guards that exist because a mistake repeated

Not gaps — the opposite. Each of these was written after the same error reached CI twice.

| Guard | Catches | Where |
|---|---|---|
| `tools/parity/check-swift-traps.mjs` | `await` inside `??` (its RHS is an `@autoclosure`, so the compiler blames the `??` and the message names neither); `UUID().uuidString` on a persisted id (Swift's is UPPERCASE, SQLite compares TEXT case-sensitively) | `parity` CI job — seconds, not a 10-minute macOS build |
| `tools/parity/check-kotlin-imports.mjs` | A Kotlin symbol used without an import. Kotlin's error for this names an unrelated class: a missing `rememberSaveable` produced *"Cannot access 'fun WideNavigationRailValue.not()'"*, because an untyped `editing` resolved `!editing` against a Material3 extension. `rememberSaveable` is the specific trap — it is in `androidx.compose.runtime.saveable`, so the `runtime.*` wildcard most screens already have does **not** cover it | `parity` CI job |
| Schema generators in `parity` | `PocketCareSchema.kt/.swift` drifting from `packages/db`'s `AppSchema`. They were **not** in the job, which is how the native schema fell four migrations behind in silence | `parity` CI job |

---

*A ✅ here means the row is resolved, not that the feature was verified on a device — see the
section above for what that distinction costs.*
