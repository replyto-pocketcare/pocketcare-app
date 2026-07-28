# Diagnostics (on-device support log)

## Overview
On a laptop you can ask someone to open the console. On a phone you can't — so when sync fails, the app prints a perfectly clear PostgREST error to a place nobody can reach, the user reports *"syncing isn't working"*, and that is genuinely all anyone knows.

This captures errors on the device, **scrubs them**, and gets them to the admin panel — primarily **on their own**, without the user having to notice, care, or file anything.

## Three routes to the admin panel
| Route | Needs the user to… | Lands in |
|---|---|---|
| **Automatic error reporting** | nothing at all | `/admin/errors` |
| **Bug report attachment** | file a report (log attached by default) | `/admin/feedback` → "Device log" |
| **Share button** | tap Share in Settings → Diagnostics | wherever they send it |

The first is the one that matters. **Most users never file a bug report** — they say "it's not working", or say nothing and stop using the app. So errors report themselves.

### Automatic reporting
- **Sent directly over HTTP via the `report_client_error` RPC, NOT through PowerSync.** The failure most worth seeing is the sync queue being stuck; routing the report through that same queue would guarantee it never arrives.
- **Deduped by fingerprint** — scope + a message with ids, digits and quoted fragments normalised out. A retry loop is one row with `count: 412`, not 412 rows. `/admin/errors` groups further so one bug is one line with an **affected-users** count: many users = a regression, one user with a huge count = a retry loop.
- **Rate limited twice**: once per fingerprint per session and max 20 reports per session on the client, plus a 50-per-hour-per-user cap in the RPC. A client-side cap is a suggestion, not a guarantee.
- **Errors only**, never warnings. A noisy admin panel gets ignored, which is the same as not having one.
- Resolving an error re-opens it automatically if it recurs.

## What it captures
| Source | Examples |
|---|---|
| `console.error` / `console.warn` | wrapped, not replaced — devtools still behaves normally |
| `window.onerror` | script errors, with filename and line |
| `unhandledrejection` | rejected promises anywhere in the app |
| network events | went offline / back online |
| **structured sync failures** | table, operation, row count, PostgREST code, message, hint |

Entries carry the **route** they happened on. The buffer is 150 entries, mirrored to `localStorage` so it survives a reload or a crash.

## Redaction — the part that must not be wrong
This is a personal finance app; a support log must never become a leak of someone's spending. The rule: **keep what diagnoses, drop what describes a person's life.**

| Kept | Removed |
|---|---|
| table names, operations, error codes | amounts (every notation, incl. bare minor units) |
| row UUIDs (how you find the row) | descriptions, merchants, names, labels |
| routes, HTTP status codes, row counts | emails, UPI IDs |
| message structure | bearer tokens, JWTs, API keys |

Three passes, chosen deliberately:

- **`redactSecrets`** — credentials and contact details only, *never touches numbers*. Used for values under keys we already know aren't money, because a PostgREST code like `23514` is indistinguishable from an amount by shape alone and is the most useful field in a sync failure.
- **`redactText`** — secrets **plus** anything money-shaped. Used for free-text messages, where there's no key to say what a number means, so we assume the worst.
- **`redactDetail`** — key-based. Sensitive keys (`amount`, `description`, `merchant`, `email`, …) have their values replaced wholesale; free-text keys (`message`, `error`, `stack`, …) get the full `redactText` treatment; everything else gets `redactSecrets`.

UUIDs are stashed before every pass and restored after, so the number scrubber can't mangle them.

**Worked example** — the real error that prompted this feature:

```
in:  expense_items for 693e8c6d-4214-4b70-8bbe-88708a2601bd sum to 20000
     but the expense total is 1258784
out: expense_items for 693e8c6d-4214-4b70-8bbe-88708a2601bd sum to [amount]
     but the expense total is [amount]
     + detail: { table: pocketcare.expense_items, op: PUT, rows: 1, code: 23514 }
```

Everything needed to diagnose it; nothing about what was bought.

## User flow
```mermaid
flowchart TD
    E([Something fails]) --> Cap[Captured + redacted<br/>into the ring buffer]
    Cap --> Auto[Reported automatically<br/>deduped, rate limited]
    Auto --> AdminE[/admin/errors]
    Cap --> Where{User also does something?}
    Where -- files a bug report --> Bug[Log attached by default]
    Bug --> AdminF[/admin/feedback → Device log]
    Where -- opens Settings --> Panel[Diagnostics panel:<br/>status, queue depth, errors]
    Panel --> Share[Share → native share sheet]
    Where -- nothing --> AdminE
```

## The Diagnostics panel
Lives in Settings. Shows, at a glance and without reading a log:

- **Status** — connected / connecting / offline
- **Last synced** — the single most telling number when someone says "it's not updating"
- **Waiting to upload** — queue depth; non-zero and stuck is the signature of a rejected write
- **Errors logged** — count, highlighted when non-zero
- the raw sync error verbatim, when there is one
- the full log, expandable, newest first

## Key files
| Layer | File |
|---|---|
| Types + redaction (tested) | `packages/core/diagnostics/src/index.ts` |
| Capture + ring buffer | `apps/web/src/diagnostics/log.ts` |
| UI | `apps/web/src/diagnostics/DiagnosticsPanel.tsx` |
| Sync hook | `packages/db/src/connector.ts` — `setSyncDiagnosticSink` |
| Wiring | `apps/web/src/powersync.ts`, `apps/web/app/AppShell.tsx` |
| Report attachment | `apps/web/src/ui/BugReport.tsx` |
| Auto-reporting | `apps/web/src/diagnostics/report.ts` |
| Admin errors page | `apps/web/app/admin/errors/page.tsx` |
| Admin queries | `apps/web/src/admin-actions.ts` — `getAdminClientErrors`, `resolveAdminClientError` |

`packages/db` has **no dependency** on the app's diagnostics layer — it exposes a module-level sink and the app opts in at startup, so the connector neither knows nor cares whether anything is listening.

## Data touched
| Table / column | Migration | Notes |
|---|---|---|
| `bug_reports.diagnostics` | `0043` | Redacted log attached to a report. Mirrored in `AppSchema` — a column added only to Postgres fails at runtime with `table bug_reports has no column named diagnostics`. |
| `client_errors` | `0044` | Auto-reported errors, one row per (fingerprint, user) with `count` / `first_seen` / `last_seen`. **Not synced** — written by RPC, read by the admin panel's service-role client. `user_id` is `ON DELETE SET NULL`, so deleting an account doesn't erase evidence of a bug it hit. |

## Edge cases
| Case | Behaviour |
|---|---|
| localStorage full / private mode | The in-memory buffer still works for the session; persistence silently degrades. |
| Logging itself throws | Every entry point is wrapped — logging must never be what breaks the app. |
| A failure inside `console.error` | Entries starting `[diagnostics]` are skipped, so it can't loop. |
| `navigator.share` unavailable | Falls back to clipboard with a "Copied" confirmation. |
| Huge log on a bug report | Capped at 20 000 characters. |
| User declines to attach | Checkbox is opt-out, default on, and says why it matters. |
| Sync completely wedged | Auto-reports still arrive — they bypass PowerSync and go straight over HTTP. |
| Runaway error loop | One report per fingerprint per session, 20/session, 50/hour/user server-side. |
| User deletes their account | Error rows survive with `user_id` nulled; they hold no personal data. |

## Deliberate non-goals
- **No `console.log` capture.** A chatty log buries the signal and burns a 150-entry buffer in seconds.
- **No unredacted mode.** "Let the user review it first" sounds respectful, but nobody reads 150 lines before tapping Send. Redaction is unconditional instead.
- **No performance or usage analytics.** This reports *failures*, not behaviour. Widening it into product analytics is a different feature with a different consent conversation.

## A note on what is sent automatically
Errors do upload on their own — that is the point of the feature — so be straight about it. What leaves the device is: a redacted message, the error code, the table and operation, the route, app version and platform. What never leaves: amounts, descriptions, merchants, names, emails, payment handles. The privacy doc covers this in the same terms.
