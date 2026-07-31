import Foundation
import PowerSync
import Domain

// Read/write facade over the local PowerSync SQLite DB for accounts and
// transactions (P2.5). Mirrors apps/web/src/hooks.ts's useAccountBalances/
// useNetWorth/useRates: query raw rows, then call the already-ported pure
// domain functions (deriveBalance, aggregateNetWorth -- money+ledger domain,
// P1.1/P1.2) for any derived value, rather than recomputing balance logic
// here. Mirrors apps/android/data/.../repository/LedgerRepository.kt.
//
// Table columns confirmed against the generated schema descriptor
// (PocketCareSchema.swift, P2.1) rather than assumed.
//
// REACTIVITY NOTE (a real, deliberate platform asymmetry vs Android): iOS's
// Queries.watch returns AsyncThrowingStream<[RowType], Error>, which -- unlike
// Kotlin's kotlinx.coroutines.flow.Flow -- has no built-in combine/combineLatest
// operator. Multiplexing 2-3 independent AsyncThrowingStreams (accounts +
// transactions + rates + blocked-amounts) into one derived reactive stream
// would need a hand-rolled AsyncSequence merge or a custom Combine bridge --
// real, uncompiler-checked complexity disproportionate to Phase 2's actual
// Done-when (TP L3 sync correctness, not UI reactivity). So: single-table
// reads are exposed as real watch() streams; the DERIVED/composed views
// (accountBalances, netWorth) are one-shot async snapshot functions instead
// of reactive streams. Building a proper multi-stream reactive combinator for
// these is left for Phase 3+ UI wiring, where the actual UI framework choice
// (SwiftUI + Combine vs async/await + @Observable) will determine the right
// shape anyway -- documented here rather than silently deferred.

public struct Account: Sendable {
    public let id: String
    public let userId: String?
    public let name: String
    public let type: String
    public let currency: String
    public let icon: String?
    public let color: String?
    public let isArchived: Bool
    public let includeInNetWorth: Bool
    public let allowNegative: Bool
    /// Virtual split accounts (receivable/payable) use "split"; "real" otherwise.
    public let kind: String
    public let createdAt: String
    public let updatedAt: String
}

public struct TransactionRow: Sendable {
    public let id: String
    public let accountId: String
    public let type: String
    public let amount: Int64
    public let currency: String
    public let categoryId: String?
    public let note: String?
    public let description: String?
    public let paymentMethod: String?
    public let occurredAt: String
    public let transferGroupId: String?
    public let toAccountId: String?
    public let toAmount: Int64?
    public let fxRate: Double?
}

public struct AccountWithBalance: Sendable {
    public let account: Account
    public let balance: Money
}

public struct NetWorth: Sendable {
    public let total: Money
    public let available: Money
    public let base: String
}

private func accountMapper(_ cursor: SqlCursor) throws -> Account {
    Account(
        id: try cursor.getString(name: "id"),
        userId: try cursor.getStringOptional(name: "user_id"),
        name: try cursor.getString(name: "name"),
        type: try cursor.getString(name: "type"),
        currency: try cursor.getString(name: "currency"),
        icon: try cursor.getStringOptional(name: "icon"),
        color: try cursor.getStringOptional(name: "color"),
        // IFNULL-style defaults matching apps/web/src/hooks.ts's exact
        // semantics: missing/older rows are treated as not-archived,
        // included in net worth, and a "real" (non-split) account.
        isArchived: (try cursor.getBooleanOptional(name: "is_archived")) ?? false,
        includeInNetWorth: (try cursor.getBooleanOptional(name: "include_in_net_worth")) ?? true,
        allowNegative: (try cursor.getBooleanOptional(name: "allow_negative")) ?? false,
        kind: (try cursor.getStringOptional(name: "kind")) ?? "real",
        createdAt: try cursor.getString(name: "created_at"),
        updatedAt: try cursor.getString(name: "updated_at")
    )
}

private func transactionMapper(_ cursor: SqlCursor) throws -> TransactionRow {
    TransactionRow(
        id: try cursor.getString(name: "id"),
        accountId: try cursor.getString(name: "account_id"),
        type: try cursor.getString(name: "type"),
        amount: try cursor.getInt64(name: "amount"),
        currency: try cursor.getString(name: "currency"),
        categoryId: try cursor.getStringOptional(name: "category_id"),
        note: try cursor.getStringOptional(name: "note"),
        description: try cursor.getStringOptional(name: "description"),
        paymentMethod: try cursor.getStringOptional(name: "payment_method"),
        occurredAt: try cursor.getString(name: "occurred_at"),
        transferGroupId: try cursor.getStringOptional(name: "transfer_group_id"),
        toAccountId: try cursor.getStringOptional(name: "to_account_id"),
        toAmount: try cursor.getInt64Optional(name: "to_amount"),
        fxRate: try cursor.getDoubleOptional(name: "fx_rate")
    )
}

private func ledgerEntryMapper(_ cursor: SqlCursor) throws -> LedgerEntry {
    LedgerEntry(
        type: try cursor.getString(name: "type"),
        accountId: try cursor.getString(name: "account_id"),
        amount: try cursor.getInt64(name: "amount"),
        toAccountId: try cursor.getStringOptional(name: "to_account_id"),
        toAmount: try cursor.getInt64Optional(name: "to_amount")
    )
}

public final class LedgerRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol

    public init(db: PowerSyncDatabaseProtocol) {
        self.db = db
    }

    // ---- reads (reactive, single table) ----

    /// All accounts (reactive). Archived accounts excluded unless [includeArchived].
    public func watchAccounts(includeArchived: Bool = false) throws -> AsyncThrowingStream<[Account], Error> {
        let where_ = includeArchived
            ? "deleted_at IS NULL AND IFNULL(kind,'real') = 'real'"
            : "deleted_at IS NULL AND IFNULL(is_archived, 0) = 0 AND IFNULL(kind,'real') = 'real'"
        return try db.watch(sql: "SELECT * FROM accounts WHERE \(where_) ORDER BY created_at", parameters: [], mapper: accountMapper)
    }

    /// Full transaction rows for one account, newest first (for a ledger/list UI).
    public func watchTransactions(accountId: String) throws -> AsyncThrowingStream<[TransactionRow], Error> {
        try db.watch(
            sql: "SELECT * FROM transactions WHERE deleted_at IS NULL AND account_id = ? ORDER BY occurred_at DESC",
            parameters: [accountId],
            mapper: transactionMapper
        )
    }

    // ---- reads (one-shot snapshots; see REACTIVITY NOTE above) ----

    /// Minimal ledger-entry projection for balance derivation -- matches
    /// hooks.ts's useAccountBalances query exactly (5 columns, all
    /// non-deleted transactions, no account filter -- deriveBalance itself
    /// filters by accountId as it folds).
    public func ledgerEntries() async throws -> [LedgerEntry] {
        try await db.getAll(
            sql: "SELECT type, account_id, amount, to_account_id, to_amount FROM transactions WHERE deleted_at IS NULL",
            parameters: [],
            mapper: ledgerEntryMapper
        )
    }

    /// All accounts with their ledger-derived balances, as of now.
    public func accountBalances(includeArchived: Bool = false) async throws -> [AccountWithBalance] {
        let where_ = includeArchived
            ? "deleted_at IS NULL AND IFNULL(kind,'real') = 'real'"
            : "deleted_at IS NULL AND IFNULL(is_archived, 0) = 0 AND IFNULL(kind,'real') = 'real'"
        let accounts = try await db.getAll(sql: "SELECT * FROM accounts WHERE \(where_) ORDER BY created_at", parameters: [], mapper: accountMapper)
        let entries = try await ledgerEntries()
        return accounts.map { account in
            AccountWithBalance(account: account, balance: deriveBalance(account.id, account.currency, entries))
        }
    }

    /// Amount blocked per account toward goals, excluding the emergency fund
    /// (which stays liquid). Matches hooks.ts's useBlockedByAccount exactly.
    public func blockedByAccount() async throws -> [String: Int64] {
        let rows = try await db.getAll(
            sql: """
                SELECT source_account_id, amount_blocked FROM goal_allocations
                WHERE deleted_at IS NULL
                  AND goal_id NOT IN (SELECT id FROM goals WHERE is_emergency_fund = 1 AND deleted_at IS NULL)
                """,
            parameters: []
        ) { cursor in
            (try cursor.getString(name: "source_account_id"), try cursor.getInt64(name: "amount_blocked"))
        }
        var m: [String: Int64] = [:]
        for (accountId, amount) in rows { m[accountId, default: 0] += amount }
        return m
    }

    /// Latest FX rate per currency pair, as of now, as a RateLookup for aggregateNetWorth.
    public func rates() async throws -> RateLookup {
        let rows = try await db.getAll(
            sql: "SELECT base_currency, quote_currency, rate, as_of FROM exchange_rates ORDER BY as_of DESC",
            parameters: []
        ) { cursor in
            (try cursor.getString(name: "base_currency"), try cursor.getString(name: "quote_currency"), (try cursor.getDoubleOptional(name: "rate")) ?? 1.0)
        }
        var rateMap: [String: Double] = [:]
        for (base, quote, rate) in rows {
            let key = "\(base)->\(quote)"
            if rateMap[key] == nil { rateMap[key] = rate } // first = latest (query is ORDER BY as_of DESC)
        }
        return { from, to in
            if from == to { return 1.0 }
            if let direct = rateMap["\(from)->\(to)"] { return direct }
            if let inverse = rateMap["\(to)->\(from)"] { return 1.0 / inverse }
            return 1.0 // fallback: treat as par if no rate known yet
        }
    }

    /// Net worth in [base] currency, with and without blocked amounts, as of now.
    public func netWorth(base: String) async throws -> NetWorth {
        let balances = try await accountBalances()
        let blocked = try await blockedByAccount()
        let rateLookup = try await rates()
        // No `try` on this chain -- money(Int64, String) and AccountBalance's
        // init are both non-throwing. Int64(0), not the bare literal 0, for
        // the same reason as Ledger.swift's aggregateNetWorth: an untyped
        // literal passed toward an overloaded function (money has both a
        // non-throwing Int64 overload and a throwing Double one) can be
        // ambiguous, even though it's nested inside `?? ` here.
        let accountBalances: [AccountBalance] = balances
            .filter { $0.account.includeInNetWorth }
            .map { entry in
                AccountBalance(balance: entry.balance, blocked: money(blocked[entry.account.id] ?? Int64(0), entry.account.currency))
            }
        return NetWorth(
            total: try aggregateNetWorth(accountBalances, base: base, getRate: rateLookup, includeBlocked: true),
            available: try aggregateNetWorth(accountBalances, base: base, getRate: rateLookup, includeBlocked: false),
            base: base
        )
    }

    // ---- writes ----

    /// Create a real account. Virtual split accounts (receivable/payable) are
    /// owned by the splits domain, a later P2.5 slice, not this repository.
    @discardableResult
    public func createAccount(
        userId: String,
        name: String,
        type: String,
        currency: String,
        icon: String? = nil,
        color: String? = nil,
        includeInNetWorth: Bool = true,
        allowNegative: Bool = false
    ) async throws -> String {
        try await insertRow(
            db: db, table: "accounts", userId: userId,
            values: [
                "name": name,
                "type": type,
                "currency": currency,
                "icon": icon,
                "color": color,
                "is_archived": false,
                "include_in_net_worth": includeInNetWorth,
                "allow_negative": allowNegative,
                "kind": "real",
            ]
        )
    }

    public func updateAccount(id: String, values: [String: Sendable?]) async throws {
        try await updateRow(db: db, table: "accounts", id: id, values: values)
    }

    public func setAccountArchived(id: String, archived: Bool) async throws {
        try await updateRow(db: db, table: "accounts", id: id, values: ["is_archived": archived])
    }

    public func deleteAccount(id: String) async throws {
        try await softDelete(db: db, table: "accounts", id: id)
    }

    /// Create a non-transfer transaction (income/expense/opening_balance/adjustment).
    @discardableResult
    public func createTransaction(
        userId: String,
        accountId: String,
        type: String,
        amount: Int64,
        currency: String,
        occurredAt: String,
        categoryId: String? = nil,
        note: String? = nil,
        description: String? = nil,
        paymentMethod: String? = nil
    ) async throws -> String {
        try await insertRow(
            db: db, table: "transactions", userId: userId,
            values: [
                "account_id": accountId,
                "type": type,
                "amount": amount,
                "currency": currency,
                "category_id": categoryId,
                "note": note,
                "description": description,
                "payment_method": paymentMethod,
                "occurred_at": occurredAt,
            ]
        )
    }

    /// Create a transfer (single row: source account_id/amount, destination
    /// to_account_id/to_amount -- matches Ledger.swift's signedEffectFor,
    /// which reads both sides off one row, not two linked rows). [toAmount]
    /// defaults to [amount] for a same-currency transfer.
    @discardableResult
    public func createTransfer(
        userId: String,
        fromAccountId: String,
        toAccountId: String,
        amount: Int64,
        currency: String,
        occurredAt: String,
        toAmount: Int64? = nil,
        fxRate: Double? = nil,
        note: String? = nil
    ) async throws -> String {
        try await insertRow(
            db: db, table: "transactions", userId: userId,
            values: [
                "account_id": fromAccountId,
                "type": "transfer",
                "amount": amount,
                "currency": currency,
                "to_account_id": toAccountId,
                "to_amount": toAmount ?? amount,
                "fx_rate": fxRate,
                "transfer_group_id": newId(),
                "occurred_at": occurredAt,
                "note": note,
            ]
        )
    }

    public func updateTransaction(id: String, values: [String: Sendable?]) async throws {
        try await updateRow(db: db, table: "transactions", id: id, values: values)
    }

    public func deleteTransaction(id: String) async throws {
        try await softDelete(db: db, table: "transactions", id: id)
    }
}
