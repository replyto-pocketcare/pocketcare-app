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
| iOS `AssistantView` mic button | Toggled `isRecording`, swapped to a stop icon, turned accent — captured no audio | Removed with the rest of the view | With the assistant port. **Web does have voice** (`speech.ts` + `MicButton.tsx`) — an earlier audit entry claiming otherwise was wrong |

## Controls deliberately not built

| Screen | What's absent | Why |
|---|---|---|
| Recurring | Create/edit (web's `RecurringModal`) | Belongs to **W2.1** — full page below 600dp, dialog/side panel above, `.fullScreenCover` on iOS phones. A "+" opening nothing is the dead control this audit keeps finding |
| Recurring | Direction rows are **not tappable** | `/recurring/[direction]` is a separate web route with no native screen. A tappable row that goes nowhere is worse than a row that reads as a summary |
| Statements | Print | `window.print()` has no phone equivalent. Share/PDF export is a feature to design, not a button to add |
| Statements | "Analyze" link | Targets `/statements/analyze`, which does not exist natively (see `StatementImportView` above) |
| Statements | "Go Premium" button | Web links to `/settings`; there is **no native upgrade flow yet**, so the button would go nowhere |
| Login | Password reset / "forgot password" | Web has a 3-step recovery flow (`resetPasswordForEmail` → OTP → set password). Not ported; the entry point is absent rather than dead |

## Platform-honest divergences (present, but not web's implementation)

| What | Web | Native | Why |
|---|---|---|---|
| Date inputs (Statements) | `<input type="date">` → browser picker | ISO text field, **both platforms** | SwiftUI has `DatePicker`; Compose has no equivalent primitive. Taking it on iOS alone would put the two Statements screens out of step over a control neither spec has settled |
| Google sign-in | OAuth redirect via `/auth/callback` | Browser flow to a custom-scheme callback | A native app cannot host an HTTP route. `/auth/callback` **has no native equivalent and must not get one** |
| Google sign-in (guest) | `linkIdentity` | Same — browser flow, deliberately not the native picker | GoTrue has no ID-token equivalent of `linkIdentity`. Using the picker for a guest would orphan every row they entered |
| Catch-up engines | Both fired concurrently | Sequential | Both write transactions into the same local DB and nothing depends on overlap. Per-engine error isolation is kept |
| EMI occurrence timestamp | noon **local** | noon **UTC** | Web's is a different UTC instant per device; two phones in different zones would stamp the same EMI differently |
| Re-entrancy guard | `let running = false` | `Mutex.tryLock()` / actor isolation | Web's flag is safe only because the browser is single-threaded |
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

---

*A ✅ here means the row is resolved, not that the feature was verified on a device — see the
section above for what that distinction costs.*
