import Foundation
import PowerSync
import Domain
import Factory

/**
 How much of the app this person has actually used, as one row of counts.

 Feeds `pickSuggestions()` (Domain), which is what decides the dashboard's "Worth
 a look" strip. Nothing here judges anything — the rules live in Domain under
 golden vectors, and this is only the SELECT.

 **One query with scalar subselects, not twelve watches.** Web says why in
 `Suggestions.tsx` and it holds harder here: twelve `db.watch` calls would open
 twelve subscriptions over the same tables to fetch twelve integers, and every
 write to any of them would wake all twelve.

 A note on the source. Web's version of this query ends `... AS creditCards,` —
 a trailing comma with nothing after it, which is not valid SQL. Its strip
 therefore never renders. The port fixes the comma rather than reproducing the
 outage; the defect is recorded in docs/mobile/PARITY_AUDIT.md's web-defects
 table.

 A second, separate defect in the same query: it filters `credit_card_details`
 on `deleted_at`, and that is the one table of the twelve here that does not
 HAVE that column (see `packages/db/src/index.ts`). SQLite raises `no such
 column`, so even with the comma fixed the stream would throw on its first
 evaluation. Both are fixed here, which makes this the first time the ranking
 has actually run anywhere.

 Mirrors apps/android/data/.../repository/SuggestionsRepository.kt.
 */
public final class SuggestionsRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    public init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    /// Web's own query, character for character apart from the two defects
    /// noted above. `IFNULL(kind,'real')` keeps the two virtual split accounts
    /// ("Owed to me" / "I owe") out of the account count: someone who has only
    /// those has not set anything up.
    private static let usageSql = """
        SELECT
          (SELECT COUNT(*) FROM accounts WHERE deleted_at IS NULL AND IFNULL(kind,'real')='real') AS accounts,
          (SELECT COUNT(*) FROM accounts WHERE deleted_at IS NULL AND type='credit_card') AS creditCardAccounts,
          (SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL) AS transactions,
          (SELECT COUNT(*) FROM subscriptions WHERE deleted_at IS NULL) AS subscriptions,
          (SELECT COUNT(*) FROM loans WHERE deleted_at IS NULL) AS loans,
          (SELECT COUNT(*) FROM budgets WHERE deleted_at IS NULL) AS budgets,
          (SELECT COUNT(*) FROM goals WHERE deleted_at IS NULL) AS goals,
          (SELECT COUNT(*) FROM split_groups WHERE deleted_at IS NULL) AS splitGroups,
          (SELECT COUNT(*) FROM receipt_scans WHERE deleted_at IS NULL) AS receipts,
          (SELECT COUNT(*) FROM recurring_items WHERE deleted_at IS NULL) AS recurring,
          (SELECT COUNT(*) FROM holdings WHERE deleted_at IS NULL) AS holdings,
          (SELECT COUNT(*) FROM credit_card_details) AS creditCards
        """

    public func watchUsageCounts() throws -> AsyncThrowingStream<UsageCounts, Error> {
        let upstream = try db.watch(
            sql: Self.usageSql,
            parameters: [],
            mapper: { cursor in
                UsageCounts(
                    accounts: Int(try cursor.getInt64(name: "accounts")),
                    transactions: Int(try cursor.getInt64(name: "transactions")),
                    subscriptions: Int(try cursor.getInt64(name: "subscriptions")),
                    loans: Int(try cursor.getInt64(name: "loans")),
                    budgets: Int(try cursor.getInt64(name: "budgets")),
                    goals: Int(try cursor.getInt64(name: "goals")),
                    splitGroups: Int(try cursor.getInt64(name: "splitGroups")),
                    receipts: Int(try cursor.getInt64(name: "receipts")),
                    recurring: Int(try cursor.getInt64(name: "recurring")),
                    holdings: Int(try cursor.getInt64(name: "holdings")),
                    creditCards: Int(try cursor.getInt64(name: "creditCards")),
                    creditCardAccounts: Int(try cursor.getInt64(name: "creditCardAccounts"))
                )
            }
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // An empty result is NOT "a user with nothing" — that is
                    // exactly the shape that makes the strip suggest a first
                    // budget to someone who has five. `pickSuggestions` returns
                    // nothing for an all-zero count, so it is silence rather
                    // than a wrong guess.
                    for try await rows in upstream { continuation.yield(rows.first ?? UsageCounts()) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public extension Container {
    /// Registered here rather than in `DI/DataModule.swift` so the repository and
    /// its wiring stay one file to read and one file to move.
    var suggestionsRepository: Factory<SuggestionsRepository> {
        self { SuggestionsRepository(db: self.powerSyncDatabase()) }.singleton
    }
}
