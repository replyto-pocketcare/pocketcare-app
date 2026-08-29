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
| iOS `AssistantView` mic button | Toggled `isRecording`, swapped to a stop icon, turned accent — captured no audio | **Built for real 2026-08-27** — `SFSpeechRecognizer` on iOS, `SpeechRecognizer` on Android, both behind an interface that hides the button entirely when there is no recogniser | ✅ Done |

## Controls deliberately not built

| Screen | What's absent | Why |
|---|---|---|
| Recurring → direction | Web's **kebab menu** | Three actions on a card that has room for three buttons. Hiding them behind a third tap is worse than showing them |
| Recurring form | **Preset name chips** ("Salary", "Rent", "Electricity"…) | They only fill the name field — pure convenience, no hidden behaviour — and web's list is **hardcoded English** in `RecurringModal.tsx`. Porting it verbatim would put untranslated strings in a screen that is otherwise fully localised. It needs a catalogue entry first |
| ~~Recurring form~~ | ~~**Alert time**~~ | **Built on both, 2026-08-28.** The reasoning above was wrong about which end is load-bearing: `alert_time_utc` is what the engine reads to decide WHEN to nudge, so writing `null` did not defer a preference — it made every item created here permanently unremindable, and no later reminder feature could recover the time the user never got to set. It is now a time picker (Material 3's on Android, `DatePicker(.hourAndMinute)` on iOS), converted through the same `localToUtcTime` every other alert-carrying form uses | ✅ Done |
| Recurring form | A **date picker** for "First due" | Plain ISO text on both, same as Statements. SwiftUI has `DatePicker` and Compose does not; adopting it on one platform only would put the two screens out of step on a field the user rarely changes |
| Recurring overview + direction | The **shell's contextual "+"** | Web registers each screen's Add into the bottom bar via `useRegisterAddAction` — the overview registers a two-item menu (payment / income), the direction screen a single button. Both native shells have the mechanism (`AddAction`), **but no screen on either platform registers into it, and iOS's `.button` case in `AppShell.runAdd()` is literally `break`** — a no-op. Until that channel is wired end-to-end, Add is an in-page button on the direction screens and the overview has none. Tracked as its own task |
| ~~Dashboard → Spending tile `lend` exclusion~~ | The tile grouped transactions in Kotlin/Swift, so there was no subquery to hang web's exclusion on, and it counted money you had fronted for someone as your own spending | Grouped in SQL, exclusion applied, 2026-08-26. **Every spending query on the dashboard now carries it** | ✅ Done |
| Dashboard → month buckets | Correct handling of the **UTC/local boundary** | `strftime('%Y-%m', occurred_at)` and `date(occurred_at)` are evaluated by SQLite in UTC, while "this month" and "today" come from the local calendar. East of UTC, a transaction in the first hours of a day or month lands in the previous bucket. **This is web's behaviour, bug included** — every one of these queries is web's. Fixing it natively alone would make the browser and the phone disagree, which is worse than agreeing on something slightly wrong. For Akhilesh's list |
| Dashboard grid | **Drag to reorder** | Web offers drag AND Move-earlier / Move-later buttons. The buttons are the accessible path, behave identically on both platforms, and are what shipped. Drag is a nicety on top of a working reorder, not a prerequisite for one |
| Dashboard grid | Web's `grid-auto-flow: **row dense**` | Dense back-fills a gap with a LATER, smaller tile — so a tile the user dragged to the bottom can jump to the top because something above it happens to be four columns wide. On a screen whose whole point is that the user chooses the order, silently reordering it is wrong, and it would make a drag preview lie about where a tile lands. Both platforms keep the order and leave the gap. Vector-pinned in `dashboard-grid.json` |
| Dashboard grid | Web's **measured row heights** | Web gives each tile a row span measured by a `ResizeObserver` against `grid-auto-rows: 8px`. That needs rendered CSS pixels before layout, which neither Compose nor SwiftUI can produce. Native rows size to their tallest tile — which is also why native tiles need no equivalent of web's `useFitRows()` clipping |
| ~~Dashboard tiles~~ | Eleven of fourteen were absent from the Add-a-widget picker | **All fourteen render**, both platforms, 2026-08-26. `TileId.isBuilt` stays as an exhaustive `when`/`switch` with no fallthrough, so a fifteenth tile in web's catalog still fails the native build until somebody decides | ✅ Done |
| ~~Statements~~ | ~~Print~~ | **Replaced by Share, both platforms, 2026-08-28.** `window.print()` still has no phone equivalent, but the INTENT behind it — get this statement out of the app — does: `ACTION_SEND` on Android, `ShareLink` on iOS, both carrying the rendered statement as text. Deliberately text and not a file: an attachment needs a `FileProvider` in Android's manifest, and the text goes through `formatMoney`, so the hide-amounts toggle applies to what leaves the app | ✅ Done |
| ~~Auto-categorisation~~ | ~~**`learnFromSave`** — the write half~~ | **Built on both, 2026-08-27**, on the add-transaction save path AND on the edit screen's correction path (`learnFromThisSave`, both platforms, gated on `type != transfer && isPaid && categoryId != originalCategoryId` exactly as web gates it) | ✅ Done |
| Auto-categorisation | `autoJob.ts`, `anchors.ts`, `semantic.ts` | The background re-categorise job and the embedding-based fallback. Neither is reachable from any screen being ported now, and `semantic.ts` needs a model on device |
| ~~Statements~~ | ~~"Analyze" link~~ | **Built on both, 2026-08-27.** The screen is reachable from Statements exactly as on web | ✅ Done |
| `/statements/analyze` | ~~**PDF statements**~~ | **Closed 2026-08-27.** PDFBox-Android (Apache-2.0) on Android, PDFKit on iOS, both behind `PdfTextExtractor`, both feeding the same Domain parser. iText was rejected: AGPL-3.0 without a commercial licence, which on a closed-source app means publishing the app's source. The library stays optional — every failure degrades to "PDFs unavailable, use the CSV export" — see the note below |
| Statements | "Go Premium" button | Web links to `/settings`; there is **no native upgrade flow yet**, so the button would go nowhere |
| ~~First run, **both platforms**~~ | ~~The **walkthrough**~~ | **Built on both, 2026-08-23.** All 7 steps, both writes, and the `done`/`skipped` split, gated by `shouldShowWalkthrough()` in Domain under 103 vectors. iOS's orphaned 121-line half-draft is gone | ✅ Done |
| Pre-auth deck | The **"Install the app" chip** and `InstallGuide` modal | Web's deck ends with PWA install instructions — Add to Home Screen on iOS Safari, the install prompt on Chrome. On a phone running this app, the app IS installed. There is nothing for the chip to say and no honest destination for it |
| Pre-auth deck | Web's **`?mode=signin`** split between "Create an account" and "Sign in" | Both land on the same login screen. Android's has its own register/sign-in toggle and no entry parameter; iOS's is a single OTP-first form with no modes at all. Giving the deck two buttons that visibly do the same thing would be worse than saying so here. Closing it means adding a start-mode parameter to both login screens — and on iOS, the register mode itself |
| iOS deep links to a **detail** screen | Land on the PARENT list | `ContentView` maps a `NavTab` to a screen and nothing pushes a stack of its own — an account edit, a loan detail and a recurring direction are all local state inside their parent list. So `/accounts/<id>/edit` opens Accounts, and `/loans/<id>` opens Loans, one tap short of the record. Android navigates precisely because its graph has the routes. `/groups/<id>` is the exception and lands exactly, because `SplitsView` already takes an `openGroupId` for a just-accepted invite. Refusing these links instead would leave an action chip that does nothing, which is worse. Closing it means giving the iOS shell a router |
| Assistant, out of quota | The **credit-pack purchase** (three Razorpay top-ups) | There is no in-app purchase flow anywhere in this app — Settings' own "Upgrade" button is a documented no-op for the same reason. Three buttons that cannot charge anyone are worse than a card that states the situation and stops. Closing it means Play Billing + StoreKit + server-side verification, which is a project, not a control |
| Assistant prose | **Tappable markdown links** | A `[link](/budgets)` in the model's prose renders as underlined accent text and is not tappable; a `<ui>` action with the same `href` **is** a button and does navigate. The persona instructs the model to prefer the action, so the common path works. Closing it means an `AnnotatedString` link annotation on Android and an `AttributedString` link on iOS, both routed through `parseAppLink` — worth doing, but the half-built version (a link that looks tappable and is not) is exactly the dead control this file exists to prevent |
| Assistant thread | **Reopened threads forget their tool calls** | `assistant_messages` stores prose only; `tool_use` / `tool_result` blocks were never persisted. Reopening a thread rebuilds the model's context from the text transcript, so the assistant no longer remembers *how* it did something it did. **This is web's behaviour, and web's comment says so** — reproducing it keeps the two clients answering the same follow-up question the same way |
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

## PDF statement parsing — what is still absent, 2026-08-27

The parser is ported and shared. These are the deliberate limits inside it.

| Gap | Why |
| --- | --- |
| **Scanned PDFs** | No OCR. A scan has pages and no text layer, so the extractor returns no glyphs and Domain's own "this may be a scanned image (needs OCR)" warning fires. Web says exactly the same thing and also does no OCR. Closes if receipt-scan's ML Kit / Vision text recognisers are pointed at rendered PDF pages |
| **Cell boundaries differ from web's** | pdf.js hands back text RUNS; PDFBox and PDFKit hand back glyphs. `groupPdfGlyphs` rebuilds runs from glyphs identically on both phones, but its boundaries are not guaranteed to land where pdf.js's did — a narration can carry a space web does not have. Amounts, dates and signs are unaffected: those come from column x-positions, which all three agree on. **Android↔iOS parity is exact and vector-pinned**; browser↔phone parity on narration text alone is not |
| **PDFBox-Android's size** | ~10-16MB of font assets in the APK. It buys the screen's headline feature and it is the only Apache-licensed option, so it ships — but if APK size becomes the binding constraint, the fix is Play Feature Delivery (an on-demand dynamic feature module), not a different library. Not done now because on-demand delivery is a Play-Store-only mechanism and a build-system change, and it does nothing for reliability |
| **Password prompt is one-shot** | A wrong password shows the generic read-failure message rather than re-prompting. Web's `window.prompt` is also one-shot for the same reason: it cannot tell a wrong password from a corrupt file without a second attempt |
| **iOS surrogate pairs** | `characterBounds(at:)` is indexed in UTF-16, so an emoji or a rare CJK glyph in a narration would be split into two half-glyphs. Bank statements are Latin plus Devanagari, both of which are in the BMP. Left as-is rather than papered over with a grapheme walk that would then disagree with PDFBox |

## Invite links open the browser, not the app — 2026-08-27

`/join` is ported on both platforms and works. What does not work is the part
neither app can fix on its own: an `https://sanvya.app/join?token=…` link tapped
in WhatsApp opens Safari or Chrome, not the app.

Both apps' halves are done. Both **server** halves are placeholders that were
committed before anything consumed them:

| File | What it says now | What it needs |
| --- | --- | --- |
| `apps/web/public/.well-known/assetlinks.json` | `sha256_cert_fingerprints: ["00:00:…:00"]` — thirty-two zero bytes | The **release keystore's real SHA-256 fingerprint** (`keytool -list -v -keystore <release.jks>`, or Play Console → Setup → App signing if Play App Signing is on — in which case it is Google's key, not yours) |
| `apps/web/public/.well-known/apple-app-site-association` | `appID: "TEAMID.com.sanvya.app"` — the literal string TEAMID | The **Apple Developer Team ID** (10 characters, Developer portal → Membership) |

Both live under `apps/web`, which this porting effort does not touch, so they
are listed here rather than edited.

Until they are real:

* Android's `autoVerify="true"` filter simply does not bind — the OS checks the
  fingerprint at install time, fails, and leaves the link to the browser.
* iOS's `applinks:sanvya.app` entitlement is present but the CDN-fetched AASA
  names an app ID that does not exist, so the association never forms.

**What works today, with no server-side anything:** `com.sanvya.app://join?token=…`.
Android has its own intent filter for it; iOS already registers the scheme for
the OAuth callback. That is what makes the screen testable now:

    adb shell am start -a android.intent.action.VIEW -d "com.sanvya.app://join?token=TOKEN"
    xcrun simctl openurl booted "com.sanvya.app://join?token=TOKEN"

It is a fallback, not the feature. Nobody is going to paste a custom-scheme URL
into a chat.

**Also absent, and smaller:** web's `/join` is reachable by typing the URL;
neither app has a "paste an invite link" entry point. Worth adding if
verification stays blocked, and pointless once it isn't.

## The assistant's writes — what is deliberately not fixed, 2026-08-27

| Gap | Why |
| --- | --- |
| **An assistant-created subscription has no `next_renewal`** | Web's tool inserts null, so the subscription counts toward `fixedMonthlyObligations` but never appears in `upcoming` until the user fills the date in. Filling it in on mobile only would make the two clients disagree about what is coming up. Closes when web sets one |
| **`major()` keeps its hardcoded `/100`** | Web bug #8's SIXTH site, and the only one reproduced rather than fixed. The parser sites write to the DATABASE, where a JPY user's stored amount being wrong is a real defect. This number goes into a PROMPT: fixing it would make a JPY user's phone send a different snapshot than their browser for the same ledger, and the assistant would answer differently on each. The bug is shared on purpose |
| **`"Uncategorized"` here, `"Uncategorised"` in the analyzer** | Both are web's, in two different files. Reproduced as-is; making them agree is a change to `apps/web` |
| **`liquidSavings` counts only base-currency accounts** | Web's rule. A dollar balance summed into a rupee total would be a wrong number stated confidently, which is the worst kind for a model to reason from — but it also means a user whose savings are all in a second currency is told they have none |


## "Pay anyone" — dropped from the product, 2026-08-29

**Decision by the product owner: the feature is being removed from `apps/web`.
It will not be ported.**

What it was: `apps/web/app/friends/page.tsx:216` — a typed UPI ID or a camera QR
scan, validated through `parseUpiTarget`, that let you pay a shop or a
non-member. It was one of the two remaining Large gaps in the Splits slice.

This is **not** the same as the "Your UPI ID" panel, which stays on the list.
That one is about saving and disclosing your OWN handle so other members can pay
you; `parseUpiTarget` and the `payments` namespace it uses remain live for that
path and for in-group settle-up. Only the pay-an-arbitrary-target entry point
goes.

Recorded here rather than simply deleted from the register so that a later pass
does not "discover the gap again" and helpfully port it back. Removing it from
web is tracked as web item **R1** in `PARITY_AUDIT.md`.
