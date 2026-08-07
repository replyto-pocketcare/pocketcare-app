import Foundation
import PowerSync
import Domain

// Inspecting and repairing the pending-upload queue, from inside the app.
//
// Ported from apps/web/src/diagnostics/queue.ts (Settings screen pass).
// Mirrors apps/android/data/.../diagnostics/Queue.kt exactly.
//
// THE FAILURE MODE THIS TARGETS: PowerSync uploads the queue in order and
// retries forever on failure. If a queued row references a parent row that
// never reached the server, its INSERT can never succeed -- foreign key or
// RLS, either way it's permanent -- and everything queued behind it is
// blocked. One orphaned row silently freezes all of a user's writes.
//
// Reads `ps_crud` directly: PowerSync's own batch API caps at a batch size
// and gives no row ids to delete, so it can't drive a repair UI.

private struct ForeignKey {
    let column: String
    let parentTable: String
}

private let FOREIGN_KEYS: [String: ForeignKey] = [
    "split_group_members": ForeignKey(column: "group_id", parentTable: "split_groups"),
    "expenses": ForeignKey(column: "group_id", parentTable: "split_groups"),
    "expense_participants": ForeignKey(column: "expense_id", parentTable: "expenses"),
    "expense_items": ForeignKey(column: "expense_id", parentTable: "expenses"),
    "expense_item_shares": ForeignKey(column: "item_id", parentTable: "expense_items"),
    "settlements": ForeignKey(column: "group_id", parentTable: "split_groups"),
    "transaction_items": ForeignKey(column: "transaction_id", parentTable: "transactions"),
    "transaction_labels": ForeignKey(column: "transaction_id", parentTable: "transactions"),
]

public struct QueuedOp: Sendable {
    /// ps_crud row id -- what we delete to discard the op.
    public let id: Int64
    public let table: String
    public let op: String
    public let rowId: String
    /// True when this op cannot upload: it's the one the server keeps rejecting.
    public let orphaned: Bool
    public let reason: String?

    public init(id: Int64, table: String, op: String, rowId: String, orphaned: Bool, reason: String? = nil) {
        self.id = id
        self.table = table
        self.op = op
        self.rowId = rowId
        self.orphaned = orphaned
        self.reason = reason
    }
}

/// `sanvya.split_group_members` -> `split_group_members`.
public func stripSchema(_ table: String) -> String {
    if let range = table.range(of: ".", options: .backwards) {
        return String(table[range.upperBound...])
    }
    return table
}

/// Read the pending queue and flag orphans. See queue.ts's own note on why
/// the failing-table signal (not a local FK check) is the reliable one --
/// the parent row is missing on the SERVER, which a client can't see for a
/// row that never uploaded.
public func inspectQueue(
    db: PowerSyncDatabaseProtocol,
    failingTable: String? = nil,
    limit: Int = 200
) async -> [QueuedOp] {
    struct Row { let id: Int64; let data: String }
    let rows: [Row]
    do {
        rows = try await db.getAll(
            sql: "SELECT id, data FROM ps_crud ORDER BY id LIMIT ?",
            parameters: [limit]
        ) { cursor in
            // getInt64 is index-based, not name-based (established constraint,
            // see Quarantine.swift's bumpAttempts comment) -- id is column 0
            // in this query's own SELECT list.
            Row(id: try cursor.getInt64(index: 0), data: try cursor.getString(name: "data"))
        }
    } catch {
        return []
    }

    var out: [QueuedOp] = []
    for row in rows {
        guard let jsonData = row.data.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }
        let table = (parsed["type"] as? String) ?? ""
        let op = (parsed["op"] as? String) ?? ""
        let opRowId = (parsed["id"] as? String) ?? ""

        var orphaned = false
        var reason: String?

        if let failingTable, table == stripSchema(failingTable) {
            orphaned = true
            reason = "the server keeps rejecting this"
        }

        if let fk = FOREIGN_KEYS[table], op.uppercased() == "PUT" {
            let opData = parsed["data"] as? [String: Any]
            if let parentId = opData?[fk.column] as? String, !parentId.isEmpty {
                let parent = try? await db.getOptional(
                    sql: "SELECT id FROM \(fk.parentTable) WHERE id = ?",
                    parameters: [parentId]
                ) { c in try c.getString(name: "id") }
                if (parent ?? nil) == nil {
                    orphaned = true
                    reason = "\(fk.parentTable) row is missing"
                }
            }
        }

        out.append(QueuedOp(id: row.id, table: table, op: op, rowId: opRowId, orphaned: orphaned, reason: reason))
    }
    return out
}

/// Delete specific queued ops. Destructive and deliberately narrow: callers
/// should only ever pass ids that have been PROVEN orphaned.
@discardableResult
public func discardOps(db: PowerSyncDatabaseProtocol, ids: [Int64]) async -> Int {
    guard !ids.isEmpty else { return 0 }
    let placeholders = ids.map { _ in "?" }.joined(separator: ",")
    _ = try? await db.execute(
        sql: "DELETE FROM ps_crud WHERE id IN (\(placeholders))",
        parameters: ids.map { $0 as Sendable? }
    )
    logDiagnostic(level: "info", scope: "sync", message: "discarded \(ids.count) stuck change(s) from the upload queue")
    return ids.count
}

/// Compact summary for the shared log and for auto-reports.
public func summarizeQueue(_ ops: [QueuedOp]) -> String {
    if ops.isEmpty { return "empty" }
    var byTable: [String: Int] = [:]
    var order: [String] = []
    for o in ops {
        if byTable[o.table] == nil { order.append(o.table) }
        byTable[o.table, default: 0] += 1
    }
    let orphans = ops.filter { $0.orphaned }
    let parts = order.map { "\($0)×\(byTable[$0] ?? 0)" }.joined(separator: ", ")
    if !orphans.isEmpty {
        var seen = Set<String>()
        var distinctLines: [String] = []
        for o in orphans {
            let line = "\(o.table) (\(o.reason ?? ""))"
            if !seen.contains(line) { seen.insert(line); distinctLines.append(line) }
        }
        return "\(ops.count) pending (\(parts)) — \(orphans.count) STUCK: \(distinctLines.joined(separator: "; "))"
    }
    return "\(ops.count) pending (\(parts))"
}

/// Pull the failing table out of the most recent sync error.
public func failingTableFrom(_ entries: [LogEntry]) -> String? {
    for e in entries.reversed() {
        guard e.scope == "sync" || e.scope == "console" else { continue }
        if case let .obj(entries)? = e.detail,
           let tableEntry = entries.first(where: { $0.key == "table" }),
           case let .str(table) = tableEntry.value, !table.isEmpty {
            return stripSchema(table)
        }
        if let range = e.message.range(of: "upload failed for ([\\w.]+)", options: .regularExpression) {
            let match = String(e.message[range])
            if let tableRange = match.range(of: "([\\w.]+)$", options: .regularExpression) {
                return stripSchema(String(match[tableRange]))
            }
        }
    }
    return nil
}
