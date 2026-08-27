import Foundation
import PowerSync

/// Facade over `subscriptions` -- added 2026-08-06 for Insights'
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

    /**
     Insert a subscription. Matches web's `insertRow("subscriptions", …)` from
     the assistant's tool, including its defaults: active, with no purchase date
     and no next renewal.

     `next_renewal` being nil is not an oversight — web leaves it nil too, and
     the consequence is real: `buildFinancialSummary`'s "upcoming" list only
     shows renewals that HAVE a date, so an assistant-created subscription counts
     toward the monthly obligations total and never appears as an upcoming charge
     until the user fills the date in. Recorded in ABSENT-BY-DECISION rather than
     silently improved on.
     */
    public func create(
        userId: String,
        name: String,
        amount: Int64,
        currency: String,
        billingCycle: String,
        purchasedOn: String? = nil,
        nextRenewal: String? = nil,
        categoryId: String? = nil
    ) async throws -> String {
        let id = newId()
        let ts = nowIso()
        try await db.execute(
            sql: """
                INSERT INTO subscriptions
                (id,user_id,name,amount,currency,billing_cycle,purchased_on,next_renewal,category_id,is_active,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            parameters: [id, userId, name, amount, currency, billingCycle, purchasedOn, nextRenewal, categoryId, true, ts, ts]
        )
        return id
    }
}
