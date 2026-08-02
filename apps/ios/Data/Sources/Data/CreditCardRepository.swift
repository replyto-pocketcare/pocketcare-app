import Foundation
import PowerSync
import Domain

// Credit-card details + bill settlement (P2.5). Mirrors
// packages/data/src/powersync-repositories.ts's PowerSyncCreditCardRepository
// exactly. Mirrors apps/android/data/.../repository/CreditCardRepository.kt.
//
// Table columns confirmed against SanvyaSchema.swift's
// credit_card_details entry and supabase/migrations/0001_init.sql +
// 0032_loans_investments_cards.sql.

public struct CreditCardDetails: Sendable {
    public let accountId: String
    public let statementDay: Int
    public let dueDay: Int
    public let creditLimit: Int64?
    public let cardLast4: String?

    public init(accountId: String, statementDay: Int, dueDay: Int, creditLimit: Int64?, cardLast4: String?) {
        self.accountId = accountId
        self.statementDay = statementDay
        self.dueDay = dueDay
        self.creditLimit = creditLimit
        self.cardLast4 = cardLast4
    }
}

public final class CreditCardRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol
    private let transactions: LedgerRepository

    public init(db: PowerSyncDatabaseProtocol, transactions: LedgerRepository) {
        self.db = db
        self.transactions = transactions
    }

    public func getDetails(accountId: String) async throws -> CreditCardDetails? {
        try await db.getOptional(
            sql: "SELECT account_id, statement_day, due_day, credit_limit, card_last4 FROM credit_card_details WHERE account_id = ?",
            parameters: [accountId]
        ) { cursor in
            CreditCardDetails(
                accountId: try cursor.getString(name: "account_id"),
                statementDay: Int((try cursor.getInt64Optional(name: "statement_day")) ?? 0),
                dueDay: Int((try cursor.getInt64Optional(name: "due_day")) ?? 0),
                creditLimit: try cursor.getInt64Optional(name: "credit_limit"),
                cardLast4: try cursor.getStringOptional(name: "card_last4")
            )
        }
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
