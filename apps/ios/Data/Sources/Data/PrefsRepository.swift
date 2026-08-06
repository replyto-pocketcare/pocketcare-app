import Foundation
import PowerSync
import Domain

// Rewritten 2026-08-05: this file used to `import GRDB` and lean on GRDB's
// FetchableRecord/PersistableRecord/`db.write { db in try db.execute(...) }`
// API -- but GRDB is NOT one of this package's declared dependencies
// (Package.swift's approved irreducible set is PowerSync + supabase-swift +
// Factory; GRDB.swift only appears in Package.resolved as powersync-swift's
// own internal SQLite driver, not something this target may import). Trying
// to `import GRDB` directly from a target that doesn't declare it as a
// product dependency is what produced the real Xcode error "Missing
// required module 'GRDBSQLite'" (GRDB's internal C target isn't exposed to
// non-declaring targets). Rewritten to the same PowerSync `Queries`
// convention every other file in this package already uses
// (LedgerRepository.swift): `db.watch/getOptional(sql:parameters:mapper:)`
// and `db.writeTransaction { tx in try tx.execute(sql:parameters:) }`.
public struct NotificationPrefs: Codable, Sendable {
    public var user_id: String
    public var push_enabled: Int
    public var emi_due: Int
    public var budget: Int
    public var low_balance: Int
    public var outlier: Int
    public var group_invite: Int
    public var group_expense: Int
    public var low_balance_threshold: Int
    public var emi_lead_days: Int

    public init(user_id: String, push_enabled: Int = 0, emi_due: Int = 1, budget: Int = 1, low_balance: Int = 1, outlier: Int = 1, group_invite: Int = 1, group_expense: Int = 1, low_balance_threshold: Int = 500, emi_lead_days: Int = 3) {
        self.user_id = user_id
        self.push_enabled = push_enabled
        self.emi_due = emi_due
        self.budget = budget
        self.low_balance = low_balance
        self.outlier = outlier
        self.group_invite = group_invite
        self.group_expense = group_expense
        self.low_balance_threshold = low_balance_threshold
        self.emi_lead_days = emi_lead_days
    }
}

private func notificationPrefsMapper(cursor: SqlCursor) throws -> NotificationPrefs {
    NotificationPrefs(
        user_id: try cursor.getString(name: "user_id"),
        push_enabled: Int((try cursor.getInt64Optional(name: "push_enabled")) ?? 0),
        emi_due: Int((try cursor.getInt64Optional(name: "emi_due")) ?? 1),
        budget: Int((try cursor.getInt64Optional(name: "budget")) ?? 1),
        low_balance: Int((try cursor.getInt64Optional(name: "low_balance")) ?? 1),
        outlier: Int((try cursor.getInt64Optional(name: "outlier")) ?? 1),
        group_invite: Int((try cursor.getInt64Optional(name: "group_invite")) ?? 1),
        group_expense: Int((try cursor.getInt64Optional(name: "group_expense")) ?? 1),
        low_balance_threshold: Int((try cursor.getInt64Optional(name: "low_balance_threshold")) ?? 500),
        emi_lead_days: Int((try cursor.getInt64Optional(name: "emi_lead_days")) ?? 3)
    )
}

public final class PrefsRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol

    public init(db: PowerSyncDatabaseProtocol) {
        self.db = db
    }

    public func watchNotificationPrefs(userId: String) throws -> AsyncThrowingStream<NotificationPrefs?, Error> {
        let upstream = try db.watch(
            sql: "SELECT * FROM notification_prefs WHERE user_id = ?",
            parameters: [userId],
            mapper: notificationPrefsMapper
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await rows in upstream {
                        continuation.yield(rows.first)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func getNotificationPrefs(userId: String) async throws -> NotificationPrefs? {
        try await db.getOptional(
            sql: "SELECT * FROM notification_prefs WHERE user_id = ?",
            parameters: [userId],
            mapper: notificationPrefsMapper
        )
    }

    public func updateNotificationPrefs(userId: String, prefs: NotificationPrefs) async throws {
        let sql = """
            INSERT INTO notification_prefs
            (user_id, push_enabled, emi_due, budget, low_balance, outlier, group_invite, group_expense, low_balance_threshold, emi_lead_days)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (user_id) DO UPDATE SET
            push_enabled = excluded.push_enabled,
            emi_due = excluded.emi_due,
            budget = excluded.budget,
            low_balance = excluded.low_balance,
            outlier = excluded.outlier,
            group_invite = excluded.group_invite,
            group_expense = excluded.group_expense,
            low_balance_threshold = excluded.low_balance_threshold,
            emi_lead_days = excluded.emi_lead_days
            """
        try await db.writeTransaction { tx in
            try tx.execute(sql: sql, parameters: [
                userId, prefs.push_enabled, prefs.emi_due, prefs.budget, prefs.low_balance,
                prefs.outlier, prefs.group_invite, prefs.group_expense, prefs.low_balance_threshold, prefs.emi_lead_days
            ])
        }
    }
}
