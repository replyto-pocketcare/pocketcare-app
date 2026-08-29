import Foundation
import PowerSync
import Domain

// Credit-card details + bill settlement (P2.5). Mirrors
// packages/data/src/powersync-repositories.ts's PowerSyncCreditCardRepository
// exactly. Mirrors apps/android/data/.../repository/CreditCardRepository.kt.
//
// Table columns confirmed against PocketCareSchema.swift's
// credit_card_details entry and supabase/migrations/0001_init.sql +
// 0032_loans_investments_cards.sql. Extended 2026-08-06 (task #29,
// Credit Cards) with watchAllDetails/cycleSpend/setCycleDetails --
// pending_due/due_on are written via the latter, matching web's
// `saveCycle()`, which updates them with a raw SQL statement separate
// from upsertDetails.

public struct CreditCardDetails: Sendable {
    public let accountId: String
    public let statementDay: Int
    public let dueDay: Int
    public let creditLimit: Int64?
    public let cardLast4: String?
    /// The user's own typed "amount due this statement" -- set by the edit
    /// form, not derived from transactions. Nil until first configured.
    public let pendingDue: Int64?
    /// Due date (YYYY-MM-DD) for `pendingDue`, recomputed from the cycle
    /// whenever the details are saved.
    public let dueOn: String?

    public init(accountId: String, statementDay: Int, dueDay: Int, creditLimit: Int64?, cardLast4: String?, pendingDue: Int64? = nil, dueOn: String? = nil) {
        self.accountId = accountId
        self.statementDay = statementDay
        self.dueDay = dueDay
        self.creditLimit = creditLimit
        self.cardLast4 = cardLast4
        self.pendingDue = pendingDue
        self.dueOn = dueOn
    }
}

/// One charge behind a card's outstanding balance, for the "View
/// transactions" list. Deliberately a narrow row rather than a full
/// `TransactionRow`: the list shows a description, a date and an amount, and
/// web's query (`SELECT id, description, amount, occurred_at`) selects exactly
/// those four. Mirrors Android's `CardCharge`.
public struct CardCharge: Identifiable, Sendable {
    public let id: String
    public let description: String?
    public let amount: Int64
    public let occurredAt: String

    public init(id: String, description: String?, amount: Int64, occurredAt: String) {
        self.id = id
        self.description = description
        self.amount = amount
        self.occurredAt = occurredAt
    }
}

/// Web caps the charges list at 200 rows (`LIMIT 200` in cards/page.tsx); the
/// running total is the total of what is listed, so the cap has to match or the
/// two clients would print different totals for the same card.
public let cardChargesLimit = 200

public final class CreditCardRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol
    private let transactions: LedgerRepository

    public init(db: PowerSyncDatabaseProtocol, transactions: LedgerRepository) {
        self.db = db
        self.transactions = transactions
    }

    private func detailsMapper(cursor: SqlCursor) throws -> CreditCardDetails {
        CreditCardDetails(
            accountId: try cursor.getString(name: "account_id"),
            statementDay: Int((try cursor.getInt64Optional(name: "statement_day")) ?? 0),
            dueDay: Int((try cursor.getInt64Optional(name: "due_day")) ?? 0),
            creditLimit: try cursor.getInt64Optional(name: "credit_limit"),
            cardLast4: try cursor.getStringOptional(name: "card_last4"),
            pendingDue: try cursor.getInt64Optional(name: "pending_due"),
            dueOn: try cursor.getStringOptional(name: "due_on")
        )
    }

    public func getDetails(accountId: String) async throws -> CreditCardDetails? {
        try await db.getOptional(
            sql: "SELECT account_id, statement_day, due_day, credit_limit, card_last4, pending_due, due_on FROM credit_card_details WHERE account_id = ?",
            parameters: [accountId],
            mapper: detailsMapper
        )
    }

    /// Live version of `getDetails` for every card at once -- reacts to
    /// edits from any screen/device, matches web's `useQuery` over the
    /// whole table (not per-card).
    public func watchAllDetails() throws -> AsyncThrowingStream<[CreditCardDetails], Error> {
        try db.watch(
            sql: "SELECT account_id, statement_day, due_day, credit_limit, card_last4, pending_due, due_on FROM credit_card_details",
            parameters: [],
            mapper: detailsMapper
        )
    }

    /// New spend posted to this card SINCE `cycleStartIso` -- an EMI
    /// charged to the card, a purchase, anything. Deliberately separate
    /// from `pending_due` (the statement amount the user typed): a charge
    /// made today lands on the NEXT statement on a real card, so folding
    /// it into "due this cycle" would overstate what's actually payable by
    /// the due date.
    ///
    /// One-shot, not a live `db.watch()` -- see Android's `cycleSpend()`
    /// doc comment for why (same simplification, both platforms).
    public func cycleSpend(accountId: String, cycleStartIso: String) async throws -> Int64 {
        let row: Int64? = try await db.getOptional(
            sql: """
                SELECT COALESCE(SUM(amount), 0) AS total FROM transactions
                WHERE account_id = ? AND deleted_at IS NULL AND type = 'expense' AND occurred_at >= ?
                """,
            parameters: [accountId, cycleStartIso]
        ) { cursor in (try cursor.getInt64Optional(name: "total")) ?? 0 }
        return row ?? 0
    }

    /// Writes the user's typed statement amount + its due date directly --
    /// `pending_due`/`due_on` aren't part of `upsertDetails`'s field set
    /// (matches web's `saveCycle()`, which updates them via a separate raw
    /// SQL statement after `upsertDetails`).
    public func setCycleDetails(accountId: String, pendingDue: Int64?, dueOnIso: String?) async throws {
        try await db.execute(
            sql: "UPDATE credit_card_details SET pending_due = ?, due_on = ?, updated_at = ? WHERE account_id = ?",
            parameters: [pendingDue, dueOnIso, nowIso(), accountId]
        )
    }

    public func upsertDetails(userId: String, details: CreditCardDetails) async throws {
        let ts = nowIso()
        let existing = try await getDetails(accountId: details.accountId)
        if existing != nil {
            try await db.execute(
                sql: "UPDATE credit_card_details SET statement_day = ?, due_day = ?, credit_limit = ?, card_last4 = ?, updated_at = ? WHERE account_id = ?",
                parameters: [details.statementDay, details.dueDay, details.creditLimit, details.cardLast4, ts, details.accountId]
            )
        } else {
            try await db.execute(
                sql: """
                    INSERT INTO credit_card_details (id,user_id,account_id,statement_day,due_day,credit_limit,card_last4,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?)
                    """,
                parameters: [newId(), userId, details.accountId, details.statementDay, details.dueDay, details.creditLimit, details.cardLast4, ts, ts]
            )
        }
    }

    /// The charges that add up to this card's outstanding balance, newest
    /// first -- web's second `useQuery` in `CardPanel`.
    ///
    /// `type = 'expense'` only, matching web: a settlement is a TRANSFER, and
    /// listing it here would show a payment as though it were another charge.
    ///
    /// One-shot rather than a live `db.watch()` for the same reason
    /// `cycleSpend` is -- see its doc comment (same simplification, both
    /// platforms).
    public func charges(accountId: String, limit: Int = cardChargesLimit) async throws -> [CardCharge] {
        try await db.getAll(
            sql: """
                SELECT id, description, amount, occurred_at FROM transactions
                WHERE account_id = ? AND deleted_at IS NULL AND type = 'expense'
                ORDER BY occurred_at DESC LIMIT ?
                """,
            parameters: [accountId, limit],
            mapper: { cursor in
                CardCharge(
                    id: try cursor.getString(name: "id"),
                    description: try cursor.getStringOptional(name: "description"),
                    amount: (try cursor.getInt64Optional(name: "amount")) ?? 0,
                    occurredAt: try cursor.getString(name: "occurred_at")
                )
            }
        )
    }

    /// How many charges `charges` would return, so the screen can hide the
    /// "View transactions" control when there are none -- web's
    /// `cardTxns.length > 0` guard. Counting is far cheaper than fetching 200
    /// rows per card on every rebuild.
    public func chargeCount(accountId: String, limit: Int = cardChargesLimit) async throws -> Int {
        let row: Int64? = try await db.getOptional(
            sql: """
                SELECT COUNT(*) AS n FROM (
                    SELECT id FROM transactions
                    WHERE account_id = ? AND deleted_at IS NULL AND type = 'expense'
                    LIMIT ?
                )
                """,
            parameters: [accountId, limit]
        ) { cursor in (try cursor.getInt64Optional(name: "n")) ?? 0 }
        return Int(row ?? 0)
    }

    /// Settle the bill = record a transfer from the chosen account to the card.
    public func settle(userId: String, fromAccountId: String, cardAccountId: String, amount: Money, toAmount: Money? = nil, occurredAt: String) async throws {
        try await transactions.createTransaction(
            userId: userId,
            accountId: fromAccountId,
            type: "transfer",
            amount: amount,
            occurredAt: occurredAt,
            note: "Credit card settlement",
            toAccountId: cardAccountId,
            toAmount: toAmount
        )
    }
}
