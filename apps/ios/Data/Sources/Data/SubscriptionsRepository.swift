import Foundation
import PowerSync

/// Read-only facade over `subscriptions` -- added 2026-08-06 for Insights'
/// genSubscriptions card (task #28), the first mobile reader of this table
/// (it has existed in AppSchema/migrations since the subscriptions feature
/// shipped on web, but no repository ever read it on mobile). Matches
/// useInsightStack.ts's subRows query exactly: only active, non-deleted
/// rows. Mirrors Android's SubscriptionsRepository.kt added the same
/// session.
public struct SubscriptionRow: Sendable {
    public let id: String
    public let name: String?
    public let amount: Int64
    public let currency: String
    public let billingCycle: String?
}

public final class SubscriptionsRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol

    public init(db: PowerSyncDatabaseProtocol) {
        self.db = db
    }

    public func watchActive() throws -> AsyncThrowingStream<[SubscriptionRow], Error> {
        try db.watch(
            sql: "SELECT id, name, amount, currency, billing_cycle FROM subscriptions WHERE deleted_at IS NULL AND is_active = 1",
            parameters: []
        ) { cursor in
            SubscriptionRow(
                id: try cursor.getString(name: "id"),
                name: try cursor.getStringOptional(name: "name"),
                amount: try cursor.getInt64(name: "amount"),
                currency: (try cursor.getStringOptional(name: "currency")) ?? "INR",
                billingCycle: try cursor.getStringOptional(name: "billing_cycle")
            )
        }
    }
}
