import Foundation
import PowerSync
import Domain
import Supabase

// Repair logic and dead-letter queue operations (P2.6b, extended for the
// Settings screen pass to add the network-facing half: scanForStranded/
// repairStranded/retryFailedWrite/discardFailedWrite).
// Mirrors apps/web/src/sync/repair.ts and apps/web/src/sync/deadletter.ts.
// Mirrors apps/android/data/.../repository/RepairRepository.kt.
//
// Re-upload/retry go DIRECT via Supabase, not by tricking PowerSync into
// re-queueing -- we hold the complete row and control ordering, so an
// upsert states the intended end state plainly.

/// Postgres schema every table/RPC lives in (matches SupabaseConnector.swift's DB_SCHEMA).
private let repairSchema = "pocketcare"

public let REPAIR_ORDER: [String] = [
    "accounts",
    "categories",
    "labels",
    "budgets",
    "goals",
    "transactions",
    "transaction_items",
    "transaction_labels",
    "split_groups",
    "split_group_members",
    "expenses",
    "expense_participants",
    "expense_items",
    "expense_item_shares",
    "settlements",
    "expense_postings",
    "goal_allocations",
    "loans",
    "subscriptions",
    "recurring_commitments",
    // "planned_cashflow" was here and is not in web's REPAIR_ORDER
    // (apps/web/src/sync/repair.ts). Migration 0060 folded that table into
    // recurring_items; web dropped it, both native copies kept it. Harmless
    // while the native schema was stale enough to still declare the table --
    // and a query against a view PowerSync no longer creates the moment the
    // schema caught up.
    "holdings",
    "receipt_scans"
]

public struct StrandedRow: Sendable {
    public let table: String
    public let id: String
    public let label: String
    /// The full local row -- needed to re-upload it (repairStranded's upsert).
    public let row: [String: Sendable?]

    public init(table: String, id: String, label: String, row: [String: Sendable?] = [:]) {
        self.table = table
        self.id = id
        self.label = label
        self.row = row
    }
}

public struct FailedWriteItem: Sendable {
    public let id: String
    public let table: String
    public let op: String
    public let rowId: String
    /// Parsed from failed_writes.payload (produced by encodePayload) -- the
    /// full row that failed to upload, used for retry (upsert) and export.
    public let payload: [String: Sendable?]
    public let code: String?
    public let message: String?
    public let reason: String?
    public let attempts: Int
    public let failedAt: String
    public let label: String
    public let explanation: String

    public init(
        id: String,
        table: String,
        op: String,
        rowId: String,
        payload: [String: Sendable?] = [:],
        code: String?,
        message: String?,
        reason: String?,
        attempts: Int,
        failedAt: String,
        label: String,
        explanation: String
    ) {
        self.id = id
        self.table = table
        self.op = op
        self.rowId = rowId
        self.payload = payload
        self.code = code
        self.message = message
        self.reason = reason
        self.attempts = attempts
        self.failedAt = failedAt
        self.label = label
        self.explanation = explanation
    }
}

/// Parse a failed_writes.payload JSON string (produced by encodePayload) back to a dictionary.
private func parsePayloadJson(_ json: String?) -> [String: Sendable?] {
    guard let json, let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    var out: [String: Sendable?] = [:]
    for (k, v) in obj {
        switch v {
        case is NSNull: out[k] = nil
        case let s as String: out[k] = s
        case let n as NSNumber: out[k] = n.int64Value
        default: out[k] = String(describing: v)
        }
    }
    return out
}

public func describeRow(table: String, row: [String: Sendable?]) -> String {
    switch table {
    case "transactions":
        let desc = ((row["description"] as? String) ?? "").isEmpty ? "Transaction" : ((row["description"] as? String) ?? "Transaction")
        let amt = (row["amount"] as? Int64) ?? 0
        let curr = (row["currency"] as? String) ?? "INR"
        let dt = String(((row["occurred_at"] as? String) ?? "").prefix(10))
        return "\(desc) · \(curr) \(Double(amt) / 100.0) · \(dt)"
    case "expenses":
        let desc = ((row["description"] as? String) ?? "").isEmpty ? "Shared expense" : ((row["description"] as? String) ?? "Shared expense")
        let amt = (row["amount"] as? Int64) ?? 0
        let curr = (row["currency"] as? String) ?? "INR"
        let dt = String(((row["occurred_at"] as? String) ?? "").prefix(10))
        return "\(desc) · \(curr) \(Double(amt) / 100.0) · \(dt)"
    case "accounts":
        return "Account “\((row["name"] as? String) ?? "")”"
    case "split_groups":
        return "Group “\((row["name"] as? String) ?? "")”"
    case "budgets":
        return "Budget “\((row["name"] as? String) ?? "")”"
    case "goals":
        return "Goal “\((row["name"] as? String) ?? "")”"
    case "settlements":
        let amt = (row["amount"] as? Int64) ?? 0
        let curr = (row["currency"] as? String) ?? "INR"
        return "Settlement · \(curr) \(Double(amt) / 100.0)"
    case "categories":
        return "Category “\((row["name"] as? String) ?? "")”"
    case "labels":
        return "Label “\((row["name"] as? String) ?? "")”"
    default:
        return "\(table.replacingOccurrences(of: "_", with: " ")) entry"
    }
}

public final class RepairRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol
    private let client: SupabaseClient
    private let getUserId: @Sendable () -> String

    public init(db: PowerSyncDatabaseProtocol, client: SupabaseClient, getUserId: @escaping @Sendable () -> String) {
        self.db = db
        self.client = client
        self.getUserId = getUserId
    }

    public func listFailedWrites(limit: Int = 100) async throws -> [FailedWriteItem] {
        do {
            return try await db.getAll(
                sql: "SELECT * FROM failed_writes WHERE resolved_at IS NULL ORDER BY failed_at DESC LIMIT ?",
                parameters: [limit]
            ) { cursor in
                let tableName = try cursor.getString(name: "table_name")
                let rowId = try cursor.getString(name: "row_id")
                let code = try cursor.getStringOptional(name: "code")
                let message = try cursor.getStringOptional(name: "message")
                let reason = try cursor.getStringOptional(name: "reason")
                let attempts = Int((try cursor.getInt64Optional(name: "attempts")) ?? 0)
                let failedAt = try cursor.getString(name: "failed_at")
                let payloadJson = try cursor.getStringOptional(name: "payload")
                var payload = parsePayloadJson(payloadJson)
                payload["id"] = rowId
                let label = describeRow(table: tableName, row: payload)
                let explanation = explainForUser(FailureInput(code: code, message: message))

                return FailedWriteItem(
                    id: try cursor.getString(name: "id"),
                    table: tableName,
                    op: try cursor.getString(name: "op"),
                    rowId: rowId,
                    payload: payload,
                    code: code,
                    message: message,
                    reason: reason,
                    attempts: attempts,
                    failedAt: failedAt,
                    label: label,
                    explanation: explanation
                )
            }
        } catch {
            return []
        }
    }

    public func markResolved(id: String, resolution: String) async throws {
        let ts = ISO8601DateFormatter().string(from: Date())
        try await db.execute(
            sql: "UPDATE failed_writes SET resolved_at = ?, resolution = ? WHERE id = ?",
            parameters: [ts, resolution, id]
        )
    }

    public func exportStrandedJson(rows: [StrandedRow]) -> String {
        """
        {
          "exportedAt": "\(ISO8601DateFormatter().string(from: Date()))",
          "user": "\(getUserId())",
          "note": "Unsynced local rows",
          "count": \(rows.count)
        }
        """
    }

    /// Full, unredacted JSON of quarantined writes -- this is the user's own
    /// data being handed back to them, not a support log. Mirrors
    /// exportFailedWrites in deadletter.ts.
    public func exportFailedWritesJson(items: [FailedWriteItem]) -> String {
        let itemsJson = items.map { i -> [String: Any] in
            [
                "table": i.table,
                "operation": i.op,
                "id": i.rowId,
                "label": i.label,
                "failedAt": i.failedAt,
                "why": i.explanation,
                "technical": [
                    "code": i.code as Any? ?? NSNull(),
                    "message": i.message as Any? ?? NSNull(),
                    "reason": i.reason as Any? ?? NSNull(),
                    "attempts": i.attempts,
                ],
                "data": i.payload.mapValues { $0 as Any? ?? NSNull() },
            ]
        }
        let root: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "note": "Changes made on this device that the server would not accept.",
            "items": itemsJson,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    /// Try the write again, directly. Direct rather than re-queued: we hold
    /// the complete row, so an upsert states the intended end state plainly.
    /// Mirrors retryFailedWrite in deadletter.ts.
    @discardableResult
    public func retryFailedWrite(_ item: FailedWriteItem) async -> Bool {
        do {
            let rel = client.schema(repairSchema).from(item.table)
            if item.op.uppercased() == "DELETE" {
                try await rel.delete().eq("id", value: item.rowId).execute()
            } else {
                var row = item.payload
                row["id"] = item.rowId
                let jsonRow = row.mapValues { sendableToAnyJSON($0) }
                try await rel.upsert(jsonRow).execute()
            }
            try await markResolved(id: item.id, resolution: "retried")
            logDiagnostic(level: "info", scope: "sync", message: "retry succeeded for \(item.table)")
            return true
        } catch {
            logDiagnostic(level: "warn", scope: "sync", message: "retry still failing for \(item.table): \(error.localizedDescription)")
            return false
        }
    }

    /// Give up on a write. Callers must export first (the UI enforces this).
    public func discardFailedWrite(_ item: FailedWriteItem) async {
        try? await markResolved(id: item.id, resolution: "discarded")
        logDiagnostic(level: "warn", scope: "sync", message: "discarded a failed write to \(item.table) (exported first)")
    }

    /// Diff local rows against the server. Requires a connection. Mirrors
    /// scanForStranded in repair.ts, including its 100-id `in.()` chunking.
    public func scanForStranded(limitPerTable: Int = 500) async -> RepairScanResult {
        var stranded: [StrandedRow] = []
        var unchecked: [String] = []
        let chunkSize = 100

        for table in REPAIR_ORDER {
            let local: [[String: Sendable?]]
            do {
                local = try await db.getAll(
                    sql: "SELECT * FROM \(table) WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT ?",
                    parameters: [limitPerTable]
                ) { cursor in try rowToDict(cursor) }
            } catch {
                continue // table not in this build's schema
            }
            if local.isEmpty { continue }

            let ids = local.compactMap { $0["id"] as? String }
            var present = Set<String>()
            var failed = false

            var i = 0
            while i < ids.count {
                let chunk = Array(ids[i..<min(i + chunkSize, ids.count)])
                do {
                    let rows: [[String: String]] = try await client.schema(repairSchema).from(table)
                        .select("id")
                        .in("id", value: chunk)
                        .execute()
                        .value
                    for row in rows { if let id = row["id"] { present.insert(id) } }
                } catch {
                    failed = true
                    break
                }
                i += chunkSize
            }

            if failed {
                unchecked.append(table)
                continue
            }

            for row in local {
                guard let id = row["id"] as? String else { continue }
                if !present.contains(id) {
                    stranded.append(StrandedRow(table: table, id: id, label: describeRow(table: table, row: row), row: row))
                }
            }
        }

        if !stranded.isEmpty {
            logDiagnostic(level: "warn", scope: "repair", message: "found \(stranded.count) row(s) never uploaded")
        }
        return RepairScanResult(stranded: stranded, unchecked: unchecked)
    }

    /// Re-upload stranded rows, parents first. One row at a time: a batch
    /// that fails tells us nothing about WHICH row was bad. Mirrors repairStranded.
    public func repairStranded(_ rows: [StrandedRow]) async -> (uploaded: Int, failed: [(table: String, id: String, error: String)]) {
        var uploaded = 0
        var failed: [(table: String, id: String, error: String)] = []

        for table in REPAIR_ORDER {
            let forTable = rows.filter { $0.table == table }
            if forTable.isEmpty { continue }
            for item in forTable {
                do {
                    let jsonRow = item.row.mapValues { sendableToAnyJSON($0) }
                    try await client.schema(repairSchema).from(table).upsert(jsonRow).execute()
                    uploaded += 1
                } catch {
                    failed.append((table: table, id: item.id, error: error.localizedDescription))
                }
            }
        }

        logDiagnostic(
            level: failed.isEmpty ? "info" : "warn", scope: "repair",
            message: "re-uploaded \(uploaded) row(s), \(failed.count) still failing"
        )
        return (uploaded, failed)
    }
}

public struct RepairScanResult: Sendable {
    public let stranded: [StrandedRow]
    public let unchecked: [String]
}

/// Convert a dynamically-typed value (from a generic row read) to an
/// `AnyJSON` case -- `AnyJSON` is a closed enum with no `init(Any)`, so this
/// has to switch on the runtime type rather than construct one directly.
private func sendableToAnyJSON(_ v: Sendable?) -> AnyJSON {
    switch v {
    case nil: return .null
    case let s as String: return .string(s)
    case let i as Int: return .integer(i)
    case let i as Int64: return .integer(Int(i))
    case let d as Double: return .double(d)
    case let b as Bool: return .bool(b)
    default: return .string(String(describing: v!))
    }
}

/// Read every column of the current cursor row into a dictionary, for a
/// table whose columns aren't known ahead of time (repair needs the WHOLE
/// row to re-upload it). Mirrors RepairRepository.kt's rowToMap -- same
/// caveat: this is new API surface (`columnNames` / generic column read) no
/// other repository exercises, so it's the riskiest guess in this file.
private func rowToDict(_ cursor: SqlCursor) throws -> [String: Sendable?] {
    var out: [String: Sendable?] = [:]
    for name in cursor.columnNames.keys {
        out[name] = try? cursor.getStringOptional(name: name)
    }
    return out
}
