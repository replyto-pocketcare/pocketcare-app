import Foundation
import PowerSync
import Domain
import GRDB

public struct NotificationPrefs: Codable, FetchableRecord, PersistableRecord {
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

public class PrefsRepository {
    private let db: PowerSyncDatabase
    
    public init(db: PowerSyncDatabase) {
        self.db = db
    }
    
    public func watchNotificationPrefs(userId: String) -> AsyncStream<NotificationPrefs?> {
        let sql = "SELECT * FROM notification_prefs WHERE user_id = ?"
        return db.watch(sql: sql, arguments: [userId], mapper: { cursor in
            return try NotificationPrefs(row: cursor.next()!)
        })
    }
    
    public func getNotificationPrefs(userId: String) async throws -> NotificationPrefs? {
        let sql = "SELECT * FROM notification_prefs WHERE user_id = ?"
        return try await db.getOptional(sql: sql, arguments: [userId]) { cursor in
            return try NotificationPrefs(row: cursor.next()!)
        }
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
        try await db.write { db in
            try db.execute(sql: sql, arguments: [
                userId, prefs.push_enabled, prefs.emi_due, prefs.budget, prefs.low_balance,
                prefs.outlier, prefs.group_invite, prefs.group_expense, prefs.low_balance_threshold, prefs.emi_lead_days
            ])
        }
    }
}
