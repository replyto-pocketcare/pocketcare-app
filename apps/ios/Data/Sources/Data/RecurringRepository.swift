import Foundation
import Domain
import PowerSync

/// Recurring commitments — the port of apps/web/src/recurring/engine.ts.
/// Mirrors apps/android/data/.../repository/RecurringRepository.kt.
///
/// A commitment is one row of `recurring_items`, the table migration 0060
/// consolidated `planned_cashflow` + `recurring_rules` + `transaction_templates`
/// into. Everything an occurrence needs to become a transaction lives on that
/// one row.
///
/// Two things about this port are worth stating up front.
///
/// **`next_due` is the cursor, and it is authoritative.** Posting an occurrence
/// and advancing `next_due` are a pair; if the post fails, `next_due` stays put
/// so the item still reads as due and will be retried on the next run. That is
/// why the catch-up loop below breaks rather than continuing on failure — an
/// overdraft-blocked auto-post must not silently skip a month.
///
/// **Nothing here reads a clock or a preference.** `todayIso` and
/// `baseCurrency` are parameters. `Data` cannot see the App target's `Prefs`,
/// and duplicating the UserDefaults read here would create a second source of
/// truth for a user-visible setting. `Finance.swift` already takes `asOfIso`
/// for the same reason.
public final class RecurringRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol
    private let ledger: LedgerRepository
    private let splits: SplitsRepository

    public init(db: PowerSyncDatabaseProtocol, ledger: LedgerRepository, splits: SplitsRepository) {
        self.db = db
        self.ledger = ledger
        self.splits = splits
    }

    /// One row of `recurring_items`, as the engine reads it.
    public struct Item: Sendable {
        public let id: String
        public let direction: String
        public let name: String
        public let amount: Int64?
        public let currency: String?
        public let frequency: String
        public let intervalCount: Int?
        public let nextDue: String
        public let accountId: String?
        public let toAccountId: String?
        public let categoryId: String?
        public let autoPost: Bool
        public let active: Bool
        public let alertTimeUtc: String?
        public let description: String?
        public let note: String?
        public let paymentMethod: String?
        public let labels: String?
        public let splitGroupId: String?
    }

    /// Mirrors web's RECURRING_COLUMNS, column for column.
    private static let columns = """
        id, direction, name, amount, currency, frequency, interval_count, next_due, \
        account_id, to_account_id, category_id, auto_post, active, alert_time_utc, \
        description, note, payment_method, labels, split_group_id
        """

    /// Catching up more than two years of missed occurrences in one run is a
    /// bug, not a feature. Same guard value web uses.
    private static let maxCatchUpPerItem = 24

    /// Noon UTC, not midnight. An occurrence dated `T00:00:00Z` lands on the
    /// previous day for anyone west of Greenwich, which silently shifts it into
    /// the wrong month for month-boundary commitments. Web's `dueIso` does the
    /// same thing for the same reason.
    private static func dueIso(_ day: String) -> String { "\(day)T12:00:00.000Z" }

    private func map(cursor: SqlCursor) throws -> Item {
        Item(
            id: try cursor.getString(name: "id"),
            direction: try cursor.getStringOptional(name: "direction") ?? "expense",
            name: try cursor.getStringOptional(name: "name") ?? "",
            amount: try cursor.getInt64Optional(name: "amount"),
            currency: try cursor.getStringOptional(name: "currency"),
            frequency: try cursor.getStringOptional(name: "frequency") ?? "monthly",
            intervalCount: (try cursor.getInt64Optional(name: "interval_count")).map(Int.init),
            nextDue: try cursor.getStringOptional(name: "next_due") ?? "",
            accountId: try cursor.getStringOptional(name: "account_id"),
            toAccountId: try cursor.getStringOptional(name: "to_account_id"),
            categoryId: try cursor.getStringOptional(name: "category_id"),
            autoPost: ((try cursor.getInt64Optional(name: "auto_post")) ?? 0) != 0,
            active: ((try cursor.getInt64Optional(name: "active")) ?? 0) != 0,
            alertTimeUtc: try cursor.getStringOptional(name: "alert_time_utc"),
            description: try cursor.getStringOptional(name: "description"),
            note: try cursor.getStringOptional(name: "note"),
            paymentMethod: try cursor.getStringOptional(name: "payment_method"),
            labels: try cursor.getStringOptional(name: "labels"),
            splitGroupId: try cursor.getStringOptional(name: "split_group_id")
        )
    }

    /// The transaction type a direction posts.
    ///
    /// Savings are a transfer into the target account; payments are expenses;
    /// income is income. Web routes this through two helpers (`directionOf`
    /// then `typeForDirection`) because its UI says "payment" where the column
    /// says "expense" — a translation that only exists to keep the UI's word
    /// out of the check constraint 0060 defined. Native has no such vocabulary
    /// split, so the round trip collapses to this.
    private func typeFor(_ direction: String) -> String {
        switch direction {
        case "income": "income"
        case "saving": "transfer"
        default: "expense"
        }
    }

    /// Every active commitment, for the Recurring screen's monthly summary.
    ///
    /// Mirrors web's `useRecurringItems()` — `active = 1`, ordered by
    /// `next_due`, and NOT filtered by direction, because savings are excluded
    /// by the summary rather than by the query (they still post, and still
    /// appear under "Due now"; they simply have no browsable list here).
    /**
     Active recurring PAYMENTS filed under the Subscriptions category.

     Both spellings are matched because the seed taxonomy says "Subscriptions"
     while an older recurring group said "Subscription", and a user who typed
     either meant the same thing. Web's comment says exactly that, and the query
     is web's.

     `i.*`, not the shared column list: that list is unqualified column names and
     this query joins `categories`, where a bare `id` is ambiguous. The mapper
     reads by name, so the extra columns cost nothing.
     */
    public func watchSubscriptions() throws -> AsyncThrowingStream<[Item], Error> {
        try db.watch(
            sql: """
                SELECT i.*
                  FROM recurring_items i
                  JOIN categories c ON c.id = i.category_id
                 WHERE i.deleted_at IS NULL AND c.deleted_at IS NULL
                   AND i.active = 1 AND i.direction = 'expense'
                   AND lower(c.name) IN ('subscription', 'subscriptions')
                 ORDER BY i.next_due
                """,
            parameters: [],
            mapper: map
        )
    }

    public func watchActiveItems() throws -> AsyncThrowingStream<[Item], Error> {
        try db.watch(
            sql: """
                SELECT \(Self.columns) FROM recurring_items
                 WHERE deleted_at IS NULL AND active = 1
                 ORDER BY next_due
                """,
            parameters: [],
            mapper: map
        )
    }

    /// Items due today or earlier that do NOT auto-post — the ones asking to be confirmed.
    public func watchDueItems(todayIso: String) throws -> AsyncThrowingStream<[Item], Error> {
        try db.watch(
            sql: """
                SELECT \(Self.columns) FROM recurring_items
                 WHERE deleted_at IS NULL AND active = 1 AND auto_post = 0 AND next_due <= ?
                 ORDER BY next_due
                """,
            parameters: [todayIso],
            mapper: map
        )
    }

    private func byId(_ id: String) async throws -> Item? {
        try await db.getOptional(
            sql: "SELECT \(Self.columns) FROM recurring_items WHERE id = ? AND deleted_at IS NULL",
            parameters: [id],
            mapper: map
        )
    }

    /// Turn one due occurrence into a real transaction.
    ///
    /// Carries description, note, payment method, labels, transfer destination
    /// and the recurring split, so moving off templates does not quietly strip
    /// detail from posted transactions.
    public func materialize(
        item: Item,
        occurredAtIso: String,
        userId: String,
        baseCurrency: String
    ) async throws {
        let currency = item.currency ?? baseCurrency
        let total = money(item.amount ?? 0, currency)

        // Recurring split: equal split among the group's CURRENT members, you
        // pay. Fewer than two members is not a split -- it falls through to a
        // plain transaction rather than creating a one-person expense.
        if let groupId = item.splitGroupId, let accountId = item.accountId {
            let memberIds: [String] = try await db.getAll(
                sql: "SELECT user_id FROM split_group_members WHERE group_id = ? AND deleted_at IS NULL",
                parameters: [groupId],
                mapper: { cursor in try cursor.getString(name: "user_id") }
            )
            if memberIds.count >= 2 {
                _ = try await splits.createSplitExpense(
                    userId: userId,
                    input: SplitExpenseInput(
                        groupId: groupId,
                        mode: "equal",
                        total: total,
                        participants: memberIds.map { ParticipantInput(userId: $0) },
                        payers: [PayerInput(userId: userId, paid: total.amount, accountId: accountId)],
                        categoryId: item.categoryId,
                        description: item.description,
                        note: item.note,
                        occurredAt: occurredAtIso
                    )
                )
                return
            }
        }

        let type = typeFor(item.direction)
        if type == "transfer", let toAccountId = item.toAccountId, let accountId = item.accountId {
            // Deliberately no category/description/labels and no toAmount --
            // matching web exactly. A nil to_amount leaves fx_rate nil, which is
            // correct for a same-currency transfer and is what web produces.
            _ = try await ledger.createTransaction(
                userId: userId,
                accountId: accountId,
                type: "transfer",
                amount: total,
                occurredAt: occurredAtIso,
                note: item.note,
                toAccountId: toAccountId
            )
        } else if let accountId = item.accountId {
            let labels = item.labels?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
            _ = try await ledger.createTransaction(
                userId: userId,
                accountId: accountId,
                type: type == "income" ? "income" : "expense",
                amount: total,
                occurredAt: occurredAtIso,
                categoryId: item.categoryId,
                labels: labels,
                note: item.note,
                description: item.description,
                paymentMethod: item.paymentMethod
            )
        }
        // No account_id: nothing to post against. Web falls through silently
        // too -- the row is a plan, not yet a chargeable commitment.
    }

    /// Post every auto-post item that has come due, catching up missed occurrences.
    /// - Returns: how many transactions were posted.
    @discardableResult
    public func runRecurring(userId: String, todayIso: String, baseCurrency: String) async throws -> Int {
        let items: [Item] = try await db.getAll(
            sql: """
                SELECT \(Self.columns) FROM recurring_items
                 WHERE deleted_at IS NULL AND active = 1 AND auto_post = 1 AND next_due <= ?
                """,
            parameters: [todayIso],
            mapper: map
        )

        var posted = 0
        for item in items {
            var due = item.nextDue
            var guardCount = 0
            while due <= todayIso, guardCount < Self.maxCatchUpPerItem {
                guardCount += 1
                do {
                    try await materialize(
                        item: item, occurredAtIso: Self.dueIso(due),
                        userId: userId, baseCurrency: baseCurrency
                    )
                } catch {
                    // e.g. an overdraft-blocked auto-post. Leave next_due where
                    // it is so the item still reads as due, and move on to the
                    // next item instead of stalling every one behind it.
                    break
                }
                let next = try advance(due, item.frequency, item.intervalCount ?? 1)
                try await updateRow(
                    db: db, table: "recurring_items", id: item.id,
                    values: ["next_due": next, "last_generated": due]
                )
                due = next
                posted += 1
            }
        }
        return posted
    }

    /// Post one occurrence now and advance ("Post now" / confirming a due item).
    public func postOnce(id: String, userId: String, baseCurrency: String) async throws {
        guard let item = try await byId(id) else { return }
        try await materialize(
            item: item, occurredAtIso: Self.dueIso(item.nextDue),
            userId: userId, baseCurrency: baseCurrency
        )
        try await updateRow(
            db: db, table: "recurring_items", id: id,
            values: [
                "next_due": try advance(item.nextDue, item.frequency, item.intervalCount ?? 1),
                "last_generated": item.nextDue,
            ]
        )
    }

    /// What the create/edit form supplies. Mirrors web's `RecurringInput`, with
    /// one deliberate difference: `amountMinor` is already in minor units.
    ///
    /// Web's `toRow` does `Math.round(inp.amount * 100)` — a hardcoded ×100,
    /// which is wrong for every currency that is not two-decimal (JPY has none,
    /// BHD has three) and against this repo's own golden rule 1. The conversion
    /// happens in the view model here, through `fromMajor`, which asks
    /// `minorUnits(currency)`.
    public struct Input: Sendable {
        public let direction: String
        public let name: String
        public let amountMinor: Int64
        public let currency: String
        public let accountId: String?
        public let toAccountId: String?
        public let categoryId: String?
        public let frequency: String
        public let firstDue: String
        public let autoPost: Bool
        public let alertTimeUtc: String?

        public init(
            direction: String, name: String, amountMinor: Int64, currency: String,
            accountId: String?, toAccountId: String? = nil, categoryId: String? = nil,
            frequency: String, firstDue: String, autoPost: Bool, alertTimeUtc: String? = nil
        ) {
            self.direction = direction
            self.name = name
            self.amountMinor = amountMinor
            self.currency = currency
            self.accountId = accountId
            self.toAccountId = toAccountId
            self.categoryId = categoryId
            self.frequency = frequency
            self.firstDue = firstDue
            self.autoPost = autoPost
            self.alertTimeUtc = alertTimeUtc
        }

        var row: [String: Sendable?] {
            [
                "direction": direction,
                "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
                "amount": amountMinor,
                "currency": currency,
                "frequency": frequency,
                // Web hardcodes 1 here too. Every interval in the UI is "every
                // 1 <frequency>"; the column exists for a multiplier no screen
                // offers yet.
                "interval_count": Int64(1),
                "next_due": firstDue,
                "account_id": accountId,
                "to_account_id": toAccountId,
                "category_id": categoryId,
                // Booleans are INTEGER 0/1 in this schema.
                "auto_post": Int64(autoPost ? 1 : 0),
                "alert_time_utc": alertTimeUtc,
            ]
        }
    }

    /// New commitment. `active = 1`, nothing generated yet.
    @discardableResult
    public func create(userId: String, input: Input) async throws -> String {
        var values = input.row
        values["active"] = Int64(1)
        values["last_generated"] = nil
        return try await insertRow(db: db, table: "recurring_items", userId: userId, values: values)
    }

    /// Edit an existing one.
    ///
    /// `last_generated` is deliberately untouched: editing the amount of a rent
    /// commitment does not un-post the months already posted, and clearing it
    /// would make the engine's history read as if nothing had ever run.
    public func update(id: String, input: Input) async throws {
        try await updateRow(db: db, table: "recurring_items", id: id, values: input.row)
    }

    /// Stop a commitment.
    ///
    /// A soft delete (`deleted_at`), like every other removal in this app —
    /// `active = 0` would also hide it from the lists, but the row would keep
    /// syncing and keep answering queries that filter only on `deleted_at`.
    /// Web's `removeRecurring` soft-deletes for the same reason.
    public func remove(id: String) async throws {
        try await softDelete(db: db, table: "recurring_items", id: id)
    }

    /// Skip one occurrence without posting.
    ///
    /// `last_generated` is deliberately NOT touched, matching web: nothing was
    /// generated, and writing it here would make a skipped month look posted.
    public func skipOnce(id: String) async throws {
        guard let item = try await byId(id) else { return }
        try await updateRow(
            db: db, table: "recurring_items", id: id,
            values: ["next_due": try advance(item.nextDue, item.frequency, item.intervalCount ?? 1)]
        )
    }
}
