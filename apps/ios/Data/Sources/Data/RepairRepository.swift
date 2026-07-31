import Foundation
import PowerSync
import Domain

// Repair logic and dead-letter queue operations (P2.6b).
// Mirrors apps/web/src/sync/repair.ts and apps/web/src/sync/deadletter.ts.
// Mirrors apps/android/data/.../repository/RepairRepository.kt.

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
    "planned_cashflow",
    "holdings",
    "receipt_scans"
]

public struct StrandedRow: Sendable {
    public let table: String
    public let id: String
    public let label: String

    public init(table: String, id: String, label: String) {
        self.table = table
        self.id = id
        self.label = label
    }
}

public struct FailedWriteItem: Sendable {
    public let id: String
    public let table: String
    public let op: String
    public let rowId: String
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
        self.code = code
        self.message = message
        self.reason = reason
        self.attempts = attempts
        self.failedAt = failedAt
        self.label = label
        self.explanation = explanation
    }
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
    private let getUserId: @Sendable () -> String

    public init(db: PowerSyncDatabaseProtocol, getUserId: @escaping @Sendable () -> String) {
        self.db = db
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
                let label = describeRow(table: tableName, row: ["id": rowId])
                let explanation = message ?? code ?? "Write failed"

                return FailedWriteItem(
                    id: try cursor.getString(name: "id"),
                    table: tableName,
                    op: try cursor.getString(name: "op"),
                    rowId: rowId,
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
}
