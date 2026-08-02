import Foundation

// Dead-letter queue for uploads the server will never accept.
//
// Ported from packages/db/src/quarantine.ts (P2.2b).
// Mirrors apps/android/data/.../sync/Quarantine.kt (P2.2a).
//
// THE PROBLEM THIS SOLVES: PowerSync uploads ps_crud strictly in order and
// retries forever. That is correct for a network blip and catastrophic for a
// rejected write — an op that can never succeed blocks every write queued
// behind it, indefinitely.
//
// After MAX_PERMANENT_ATTEMPTS (from the already-ported sync-policy domain),
// a failure classified permanent is **moved**, not deleted. The full payload
// goes to the local-only `failed_writes` table, the op leaves `ps_crud`, and
// the queue drains.
//
// Local-only on purpose: a synced quarantine table would put its own rows into
// the queue it exists to unblock.
//
// Database schema for the local-only tables (declared as local-only in the
// app's PowerSync schema via SanvyaSchema.swift):
//   sync_attempts(id TEXT PRIMARY KEY, attempts INTEGER, last_code TEXT, updated_at TEXT)
//   failed_writes(id TEXT PRIMARY KEY, table_name TEXT, op TEXT, row_id TEXT,
//                 payload TEXT, code TEXT, message TEXT, cls TEXT, reason TEXT,
//                 attempts INTEGER, failed_at TEXT, resolved_at TEXT, resolution TEXT)

import PowerSync
import Domain

// MARK: - opKey

/// Stable identity for one logical write, used as the retry-counter key.
///
/// Keyed on table + op + row id (not ps_crud row id), so the count survives
/// PowerSync re-deriving the queue and an app restart.
///
/// Identical to quarantine.ts: opKey(table, op, rowId) = "\(table)|\(op)|\(rowId)"
public func opKey(table: String, op: String, rowId: String) -> String {
    "\(table)|\(op)|\(rowId)"
}

// MARK: - bumpAttempts / clearAttempts

/// Read and increment the attempt count for an op. Missing row means attempt 1.
///
/// NOT INSERT OR REPLACE: PowerSync exposes every table as a VIEW backed by
/// INSTEAD OF triggers, and SQLite cannot UPSERT into a view. Same workaround
/// as the TS source.
public func bumpAttempts(
    db: PowerSyncDatabaseProtocol,
    key: String,
    code: String?
) async -> Int {
    do {
        // getOptional returns nil when no row matches.
        // PowerSync's SqlCursor has no getLong — the Int64 accessors are
        // getInt64(index:)/getInt64Optional(index:) (confirmed against the
        // real SDK's DocC index, powersync-ja.github.io/powersync-swift).
        let existing: Int64? = try await db.getOptional(
            sql: "SELECT attempts FROM sync_attempts WHERE id = ?",
            parameters: [key]
        ) { cursor in
            try cursor.getInt64(index: 0)
        }
        let attempts = Int((existing ?? 0) + 1)
        let now = ISO8601DateFormatter().string(from: Date())
        if existing != nil {
            // No `as Any` — Queries.execute's real signature is
            // `parameters: [Sendable?]?`, and `Any` does not conform to
            // `Sendable`, so casting to it (rather than just passing the
            // already-Sendable String?) was the actual compile error.
            try await db.execute(
                sql: "UPDATE sync_attempts SET attempts = ?, last_code = ?, updated_at = ? WHERE id = ?",
                parameters: [attempts, code, now, key]
            )
        } else {
            try await db.execute(
                sql: "INSERT INTO sync_attempts (id, attempts, last_code, updated_at) VALUES (?, ?, ?, ?)",
                parameters: [key, attempts, code, now]
            )
        }
        return attempts
    } catch {
        // If the counter table is unavailable, report attempt 1 so nothing is
        // ever quarantined on the strength of a broken counter.
        return 1
    }
}

public func clearAttempts(db: PowerSyncDatabaseProtocol, key: String) async {
    _ = try? await db.execute(
        sql: "DELETE FROM sync_attempts WHERE id = ?",
        parameters: [key]
    )
}

// MARK: - CrudOpSummary

/// Summary of a single CRUD entry for quarantine tracking. Extracted from
/// PowerSync's CrudEntry to avoid SDK type leakage into the quarantine layer.
public struct CrudOpSummary: Sendable {
    /// ps_crud row id (clientId) — stable across retries; nil if unavailable.
    public let clientId: Int64?
    public let table: String
    public let op: String
    public let id: String
    /// JSON-serialised payload for the dead-letter entry.
    public let payloadJson: String
}

/// Failure info extracted from an upload exception.
public struct FailureDetails: Sendable {
    public let code: String?
    public let message: String?
    public let status: Int?

    public init(code: String? = nil, message: String? = nil, status: Int? = nil) {
        self.code = code
        self.message = message
        self.status = status
    }
}

/// Return value from handleUploadFailure.
public struct UploadFailureResult: Sendable {
    public let quarantined: Bool
    public let classification: Classification
    public let attempts: Int
}

// MARK: - quarantineOps

/// Move a run of failed ops out of the upload queue and into `failed_writes`.
///
/// ORDER MATTERS: payload written first, queue entry deleted second. If the
/// process dies between the two, the op is still queued and will be quarantined
/// again — harmless (delete-then-insert keyed on clientId). The reverse order
/// would lose the write.
///
/// Identical crash-safety semantics as quarantine.ts.
public func quarantineOps(
    db: PowerSyncDatabaseProtocol,
    ops: [CrudOpSummary],
    failure: FailureDetails,
    classification: Classification,
    attempts: Int
) async throws -> Int {
    let now = ISO8601DateFormatter().string(from: Date())
    var ids: [Int64] = []

    for op in ops {
        let rowKey = op.clientId.map { String($0) } ?? "\(op.table):\(op.id)"
        // Delete-then-insert (PowerSync tables are VIEWs backed by INSTEAD OF
        // triggers — SQLite cannot UPSERT a view).
        try await db.execute(
            sql: "DELETE FROM failed_writes WHERE id = ?",
            parameters: [rowKey]
        )
        try await db.execute(
            sql: """
                INSERT INTO failed_writes
                (id, table_name, op, row_id, payload, code, message, cls, reason,
                 attempts, failed_at, resolved_at, resolution)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL)
                """,
            parameters: [
                rowKey,
                op.table,
                op.op,
                op.id,
                op.payloadJson,
                failure.code,
                failure.message,
                classification.cls,
                classification.reason,
                attempts,
                now,
            ]
        )
        if let cid = op.clientId { ids.append(cid) }
    }

    if !ids.isEmpty {
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        try await db.execute(
            sql: "DELETE FROM ps_crud WHERE id IN (\(placeholders))",
            parameters: ids.map { $0 as Sendable? }
        )
    }
    return ops.count
}

// MARK: - handleUploadFailure

/// Decide what to do about a failed run, and do it.
///
/// Returns quarantined=true when the run was moved to the dead-letter queue and
/// the caller should carry on with the rest of the batch; false when it should
/// rethrow so PowerSync retries.
///
/// Mirrors handleUploadFailure in quarantine.ts exactly.
public func handleUploadFailure(
    db: PowerSyncDatabaseProtocol,
    run: [CrudOpSummary],
    failure: FailureDetails,
    onBump: ((String) -> Void)? = nil
) async -> UploadFailureResult {
    let classification = classifyFailure(FailureInput(
        status: failure.status,
        code: failure.code,
        message: failure.message
    ))
    let head = run[0]
    let key = opKey(table: head.table, op: head.op, rowId: head.id)
    onBump?(key)
    let attempts = await bumpAttempts(db: db, key: key, code: failure.code)

    guard shouldQuarantine(classification, attempts) else {
        return UploadFailureResult(quarantined: false, classification: classification, attempts: attempts)
    }

    do {
        _ = try await quarantineOps(db: db, ops: run, failure: failure, classification: classification, attempts: attempts)
        await clearAttempts(db: db, key: key)
        return UploadFailureResult(quarantined: true, classification: classification, attempts: attempts)
    } catch {
        // If quarantining itself fails, retrying is strictly safer than
        // pretending we handled it.
        return UploadFailureResult(quarantined: false, classification: classification, attempts: attempts)
    }
}

// MARK: - encodePayload

/// Encode a [String: Any?] dictionary as compact JSON for dead-letter storage.
public func encodePayload(_ data: [String: Any?]?) -> String {
    guard let data else { return "{}" }
    var jsonDict: [String: Any] = [:]
    for (k, v) in data {
        switch v {
        case nil:
            jsonDict[k] = NSNull()
        case let s as String:
            jsonDict[k] = s
        case let n as NSNumber:
            jsonDict[k] = n
        case let b as Bool:
            jsonDict[k] = b
        default:
            jsonDict[k] = String(describing: v!)
        }
    }
    guard let data = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.sortedKeys]),
          let str = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return str
}
