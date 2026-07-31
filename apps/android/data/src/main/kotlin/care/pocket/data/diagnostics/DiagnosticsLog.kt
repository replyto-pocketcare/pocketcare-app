package care.pocket.data.diagnostics

/**
 * In-memory rolling diagnostics log for the sync layer (P2.3, completing the
 * piece of P2.2/P2.4's plan that wasn't wired yet: "diagnostics formatLog/
 * makeEntry, already ported, log them").
 *
 * Before this file: SupabaseConnector.kt's failure path only did a raw
 * `android.util.Log.e(...)` and fed a separate `SyncDiagnostic` data class
 * (an app-level hook for e.g. a status bar or crash-reporting breadcrumb —
 * kept, different purpose). Neither of those touched the already-ported
 * `diagnostics` domain (Diagnostics.kt, P1.6a) at all, so there was no way
 * to actually produce the human-readable, REDACTED report `formatLog`
 * exists to generate for a "share diagnostics" support flow (Phase 3+ UI,
 * not built yet).
 *
 * This module is that missing wiring point: every sync failure is fed
 * through `makeEntry` (which redacts money/secrets/PII on the way in, per
 * Diagnostics.kt's whole reason for existing) and appended to a capped ring
 * buffer, so `diagnosticsReport()` can produce `formatLog`'s plain-text
 * output on demand. Mirrors apps/ios/Data/.../DiagnosticsLog.swift exactly.
 *
 * Capped ring buffer, not persisted to disk or synced: this is a debugging
 * aid, not an audit trail. The real audit trail is the append-only ledger
 * (golden rule #2) plus the `failed_writes` table Quarantine.kt already
 * persists — this log exists purely so a human support flow has something
 * readable to paste into a bug report.
 */

import care.pocket.domain.diagnostics.DetailValue
import care.pocket.domain.diagnostics.LogEntry
import care.pocket.domain.diagnostics.formatLog
import care.pocket.domain.diagnostics.makeEntry

private const val MAX_DIAGNOSTICS_ENTRIES = 200

private val entries = ArrayDeque<LogEntry>()

/**
 * Record one sync-layer event through the diagnostics domain's redaction
 * pipeline. Safe to call with raw failure messages/details — `makeEntry`
 * scrubs money-shaped numbers, emails, VPAs and secrets before storing.
 */
@Synchronized
fun logDiagnostic(
    level: String,
    scope: String,
    message: String,
    route: String? = null,
    detail: DetailValue.Obj? = null,
) {
    entries.addLast(makeEntry(level = level, scope = scope, message = message, route = route, detail = detail))
    while (entries.size > MAX_DIAGNOSTICS_ENTRIES) {
        entries.removeFirst()
    }
}

/** Snapshot of everything currently buffered, oldest first. */
@Synchronized
fun currentDiagnosticsEntries(): List<LogEntry> = entries.toList()

/** Plain-text report for copy/share, via the diagnostics domain's formatLog. */
fun diagnosticsReport(context: Map<String, String?> = emptyMap()): String =
    formatLog(currentDiagnosticsEntries(), context)

/** Test/debug-only: drop everything buffered so far. */
@Synchronized
fun clearDiagnosticsLog() {
    entries.clear()
}
