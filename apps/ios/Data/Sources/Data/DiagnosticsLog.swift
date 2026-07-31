import Foundation
import Domain

// In-memory rolling diagnostics log for the sync layer (P2.3, completing the
// piece of P2.2/P2.4's plan that wasn't wired yet: "diagnostics formatLog/
// makeEntry, already ported, log them").
//
// Before this file: SupabaseConnector.swift's failure path only did a raw
// `print(...)` and fed a separate `SyncDiagnostic` struct (an app-level hook
// for e.g. a status bar or crash-reporting breadcrumb — kept, different
// purpose). Neither of those touched the already-ported `diagnostics` domain
// (Diagnostics.swift, P1.6b) at all, so there was no way to actually produce
// the human-readable, REDACTED report `formatLog` exists to generate for a
// "share diagnostics" support flow (Phase 3+ UI, not built yet).
//
// This module is that missing wiring point: every sync failure is fed
// through `makeEntry` (which redacts money/secrets/PII on the way in, per
// Diagnostics.swift's whole reason for existing) and appended to a capped
// ring buffer, so `diagnosticsReport()` can produce `formatLog`'s plain-text
// output on demand.
//
// Capped ring buffer, not persisted to disk or synced: this is a debugging
// aid, not an audit trail. The real audit trail is the append-only ledger
// (golden rule #2) plus the `failed_writes` table Quarantine.swift already
// persists — this log exists purely so a human support flow has something
// readable to paste into a bug report.

private let maxDiagnosticsEntries = 200

nonisolated(unsafe) private var diagnosticsEntries: [LogEntry] = []
private let diagnosticsLock = NSLock()

/// Record one sync-layer event through the diagnostics domain's redaction
/// pipeline. Safe to call with raw failure messages/details — `makeEntry`
/// scrubs money-shaped numbers, emails, VPAs and secrets before storing.
public func logDiagnostic(
    level: String,
    scope: String,
    message: String,
    route: String? = nil,
    detail: DetailValue? = nil
) {
    let entry = makeEntry(level: level, scope: scope, message: message, route: route, detail: detail)
    diagnosticsLock.lock()
    diagnosticsEntries.append(entry)
    if diagnosticsEntries.count > maxDiagnosticsEntries {
        diagnosticsEntries.removeFirst(diagnosticsEntries.count - maxDiagnosticsEntries)
    }
    diagnosticsLock.unlock()
}

/// Snapshot of everything currently buffered, oldest first.
public func currentDiagnosticsEntries() -> [LogEntry] {
    diagnosticsLock.lock()
    defer { diagnosticsLock.unlock() }
    return diagnosticsEntries
}

/// Plain-text report for copy/share, via the diagnostics domain's formatLog.
public func diagnosticsReport(context: [(key: String, value: String?)] = []) -> String {
    formatLog(currentDiagnosticsEntries(), context)
}

/// Test/debug-only: drop everything buffered so far.
public func clearDiagnosticsLog() {
    diagnosticsLock.lock()
    diagnosticsEntries.removeAll()
    diagnosticsLock.unlock()
}
