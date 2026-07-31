import Foundation
import PowerSync
import Domain

// Read/write facade over the local PowerSync SQLite DB for accounts and
// transactions (P2.5). Mirrors apps/web/src/hooks.ts's useAccountBalances/
// useNetWorth/useRates for the REACTIVE reads, and mirrors
// packages/data/src/powersync-repositories.ts's PowerSyncAccountRepository /
// PowerSyncTransactionRepository / PowerSyncBalanceRepository for the WRITE
// business logic and one-shot spec reads. Mirrors
// apps/android/data/.../repository/LedgerRepository.kt.
//
// IMPORTANT CORRECTION (this revision): the first version of this file
// (commit 72dcb2b) was built by reverse-engineering apps/web/src/hooks.ts and
// write.ts, WITHOUT knowing that a real, authoritative repository layer
// already exists at packages/data/src/powersync-repositories.ts and is what
// apps/web/src/powersync.ts's getRepositories() actually wires up for all
// domain writes. Per CLAUDE.md golden rule 8 ("web is the spec"), THAT file
// -- not hooks.ts/write.ts -- is the correct source of truth for write
// behavior. This revision ports its business logic faithfully: overdraft
// protection (OverdraftError/assertNoOverdraft), opening-balance semantics
// (setOpeningBalance), transaction breakdown items (transaction_items,
// itemsReconcile-checked), labels (labels/transaction_labels,
// find-or-create), and a change-audit trail (transaction_audit). The
// reactive watch()-based reads have NO equivalent in the real repository
// layer at all (the web app gets reactivity from separate useQuery hooks in
// hooks.ts, not from @pocketcare/data) -- they're a genuine mobile-side
// addition on top of the spec, not a divergence from it, and are kept.
//
// One deliberate, documented divergence: PowerSyncBalanceRepository.netWorth()
// in the real spec is currently an explicit unfinished placeholder that
// always returns money(0, base) (comment: "full multi-account + FX
// aggregation lands in Phase 5"). This repository's netWorth() computes a
// real answer via aggregateNetWorth (already correct domain logic, ported in
// P1.2). Regressing mobile to match a stated placeholder would be a strictly
// worse user experience for no fidelity benefit -- when the web spec's real
// Phase 5 aggregation ships, reconcile the two.
//
// Table columns confirmed against the generated schema descriptor
// (PocketCareSchema.swift, P2.1) and against
// supabase/migrations/0001_init.sql, not assumed.
//
// PowerSync Swift SDK call shapes (get/getOptional/getAll/execute/
// writeTransaction) confirmed against docs.powersync.com's Swift SDK
// reference page (fetched live), not assumed. The label-writing logic that
// the real TS spec factors into a shared `writeLabels(tx, ...)` helper is
// inlined at both of its two call sites here (create/update) instead,
// deliberately: the real transaction-context protocol's exact name wasn't
// independently confirmed (secondary web-search corroboration only, not a
// fetched source file), and Swift's closure-parameter type inference lets
// `db.writeTransaction { tx in ... }` avoid ever having to spell that type
// out -- safer than risking a wrong type name in code with no compiler to
// catch it.
//
// REACTIVITY NOTE (a real, deliberate platform asymmetry vs Android): iOS's
// Queries.watch returns AsyncThrowingStream<[RowType], Error>, which -- unlike
// Kotlin's kotlinx.coroutines.flow.Flow -- has no built-in combine/combineLatest
// operator. Single-table reads are exposed as real watch() streams; the
// DERIVED/composed views (accountBalances, netWorth) are one-shot async
// snapshot functions instead of reactive streams (see P2.5's original
// commit message for the full rationale).

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

public struct TransactionItemInput: Sendable {
    public let description: String
    public let amount: Money
    public init(description: String, amount: Money) {
        self.description = description
        self.amount = amount
    }
}

public struct TransactionItem: Sendable {
    public let id: String
    public let transactionId: String
    public let description: String
    public let amount: Int64
}

public struct TransactionAudit: Sendable {
    public let id: String
    public let transactionId: String
    public let action: String
    /// JSON string of { field: { from, to } } -- not parsed here, mirrors the real repo's shape.
    public let changes: String?
    public let createdAt: String
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

/// Thrown when a write would take a no-overdraft account below zero.
/// Mirrors packages/data/src/powersync-repositories.ts's OverdraftError.
public struct OverdraftError: Error, Sendable {
    public let code = "OVERDRAFT"
    public let accountName: String
    public let shortfall: Money
    public init(accountName: String, shortfall: Money) {
        self.accountName = accountName
        self.shortfall = shortfall
    }
    public var message: String {
        "Recording this would take \"\(accountName)\" below zero. " +
            "Turn on \"Allow negative balance\" for this account, or reduce the amount."
    }
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

private func itemMapper(_ cursor: SqlCursor) throws -> TransactionItem {
    TransactionItem(
        id: try cursor.getString(name: "id"),
        transactionId: try cursor.getString(name: "transaction_id"),
        description: try cursor.getString(name: "description"),
        amount: try cursor.getInt64(name: "amount")
    )
}

private func auditMapper(_ cursor: SqlCursor) throws -> TransactionAudit {
    TransactionAudit(
        id: try cursor.getString(name: "id"),
        transactionId: try cursor.getString(name: "transaction_id"),
        action: try cursor.getString(name: "action"),
        changes: try cursor.getStringOptional(name: "changes"),
        createdAt: try cursor.getString(name: "created_at")
    )
}

/// Minimal, dependency-free JSON-object serializer for the audit `changes`
/// column -- values are always strings or nil here, so a hand-rolled encoder
/// avoids pulling in Codable machinery just for this one column.
private func changesToJson(_ changes: [(String, String?, String?)]) -> String {
    func encode(_ v: String?) -> String {
        guard let v else { return "null" }
        let escaped = v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
    let entries = changes.map { (k, from, to) in
        "\"\(k)\":{\"from\":\(encode(from)),\"to\":\(encode(to))}"
    }.joined(separator: ",")
    return "{\(entries)}"
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
    /// hooks.ts's useAccountBalances query exactly.
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

    /// Ledger-derived balance of a single account. Scoped by
    /// (account_id = ? OR to_account_id = ?), matching
    /// PowerSyncBalanceRepository.accountBalance() exactly.
    public func accountBalance(accountId: String) async throws -> Money {
        guard let currency = try await db.getOptional(
            sql: "SELECT currency FROM accounts WHERE id = ?",
            parameters: [accountId],
            mapper: { cursor in try cursor.getString(name: "currency") }
        ) else {
            throw NSError(domain: "LedgerRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Account \(accountId) not found"])
        }
        let entries = try await db.getAll(
            sql: """
                SELECT type, account_id, amount, to_account_id, to_amount FROM transactions
                WHERE deleted_at IS NULL AND (account_id = ? OR to_account_id = ?)
                """,
            parameters: [accountId, accountId],
            mapper: ledgerEntryMapper
        )
        return deriveBalance(accountId, currency, entries)
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
            if rateMap[key] == nil { rateMap[key] = rate }
        }
        return { from, to in
            if from == to { return 1.0 }
            if let direct = rateMap["\(from)->\(to)"] { return direct }
            if let inverse = rateMap["\(to)->\(from)"] { return 1.0 / inverse }
            return 1.0
        }
    }

    /// Net worth in [base] currency, with and without blocked amounts, as of
    /// now. See the file-header note: this is intentionally ahead of the
    /// real web spec's current netWorth() placeholder, not a divergence from
    /// settled behavior.
    public func netWorth(base: String) async throws -> NetWorth {
        let balances = try await accountBalances()
        let blocked = try await blockedByAccount()
        let rateLookup = try await rates()
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

    // ---- writes: accounts ----

    /// Create a real account. Matches PowerSyncAccountRepository.create()'s
    /// exact INSERT column list -- notably it does NOT write
    /// include_in_net_worth or kind at creation time; those stay NULL and
    /// fall back to their IFNULL read-side defaults until explicitly set via
    /// updateAccount(). [allowNegative] defaults to true for credit_card
    /// accounts and false otherwise, unless the caller passes an explicit
    /// value.
    @discardableResult
    public func createAccount(
        userId: String,
        name: String,
        type: String,
        currency: String,
        icon: String? = nil,
        color: String? = nil,
        allowNegative: Bool? = nil,
        isArchived: Bool = false
    ) async throws -> String {
        let id = newId()
        let ts = nowIso()
        let allowNeg = allowNegative ?? (type == "credit_card")
        try await db.execute(
            sql: """
                INSERT INTO accounts (id,user_id,name,type,currency,icon,color,is_archived,allow_negative,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """,
            parameters: [id, userId, name, type, currency, icon, color, isArchived, allowNeg, ts, ts]
        )
        return id
    }

    /// Set/adjust the opening balance by appending a ledger entry -- never
    /// rewrites history. Matches PowerSyncAccountRepository.setOpeningBalance().
    public func setOpeningBalance(userId: String, accountId: String, balance: Money, occurredAt: String) async throws {
        guard let currency = try await db.getOptional(
            sql: "SELECT currency FROM accounts WHERE id = ?",
            parameters: [accountId],
            mapper: { cursor in try cursor.getString(name: "currency") }
        ) else {
            throw NSError(domain: "LedgerRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Account \(accountId) not found"])
        }
        guard currency == balance.currency else {
            throw NSError(domain: "LedgerRepository", code: 2, userInfo: [NSLocalizedDescriptionKey: "Opening balance currency must match account currency"])
        }
        let existingCount: Int64 = try await db.getOptional(
            sql: "SELECT COUNT(*) as c FROM transactions WHERE account_id = ? AND type = 'opening_balance'",
            parameters: [accountId],
            mapper: { cursor in try cursor.getInt64(name: "c") }
        ) ?? 0
        let type = existingCount > 0 ? "adjustment" : "opening_balance"
        let ts = nowIso()
        try await db.execute(
            sql: """
                INSERT INTO transactions (id,user_id,account_id,type,amount,currency,occurred_at,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?)
                """,
            parameters: [newId(), userId, accountId, type, balance.amount, balance.currency, occurredAt, ts, ts]
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

    // ---- writes: transactions ----

    /// Throw OverdraftError if applying [deltaMinor] to [accountId] would
    /// take a no-overdraft account below zero. Matches assertNoOverdraft().
    private func assertNoOverdraft(accountId: String, deltaMinor: Int64, excludeTxnId: String?) async throws {
        if deltaMinor >= 0 { return }
        struct AcctInfo { let name: String; let currency: String; let allowNegative: Bool }
        let acct: AcctInfo? = try await db.getOptional(
            sql: "SELECT name, currency, IFNULL(allow_negative, 0) AS allow_negative FROM accounts WHERE id = ?",
            parameters: [accountId],
            mapper: { cursor in
                AcctInfo(
                    name: try cursor.getString(name: "name"),
                    currency: try cursor.getString(name: "currency"),
                    allowNegative: (try cursor.getBooleanOptional(name: "allow_negative")) ?? false
                )
            }
        )
        guard let acct, !acct.allowNegative else { return }
        let sql = excludeTxnId != nil
            ? "SELECT type, account_id, amount, to_account_id, to_amount FROM transactions WHERE deleted_at IS NULL AND (account_id = ? OR to_account_id = ?) AND id != ?"
            : "SELECT type, account_id, amount, to_account_id, to_amount FROM transactions WHERE deleted_at IS NULL AND (account_id = ? OR to_account_id = ?)"
        let params: [Sendable?] = excludeTxnId != nil ? [accountId, accountId, excludeTxnId] : [accountId, accountId]
        let entries = try await db.getAll(sql: sql, parameters: params, mapper: ledgerEntryMapper)
        let projected = deriveBalance(accountId, acct.currency, entries).amount + deltaMinor
        if projected < 0 { throw OverdraftError(accountName: acct.name, shortfall: money(projected, acct.currency)) }
    }

    /// Create a transaction (+ optional breakdown items, + optional labels)
    /// atomically. Rejects if items don't reconcile to the total.
    /// Overdraft-checked for expenses and the source side of transfers.
    /// Matches PowerSyncTransactionRepository.create() exactly.
    @discardableResult
    public func createTransaction(
        userId: String,
        accountId: String,
        type: String,
        amount: Money,
        occurredAt: String,
        categoryId: String? = nil,
        labels: [String]? = nil,
        note: String? = nil,
        description: String? = nil,
        paymentMethod: String? = nil,
        items: [TransactionItemInput]? = nil,
        toAccountId: String? = nil,
        toAmount: Money? = nil
    ) async throws -> TransactionRow {
        let itemList = items ?? []
        if !itemList.isEmpty, !itemsReconcile(amount, itemList.map(\.amount)) {
            throw NSError(domain: "LedgerRepository", code: 3, userInfo: [NSLocalizedDescriptionKey: "Breakdown items must sum exactly to the transaction amount"])
        }
        if type == "transfer", toAccountId == nil {
            throw NSError(domain: "LedgerRepository", code: 4, userInfo: [NSLocalizedDescriptionKey: "Transfer requires a destination account"])
        }
        if type == "expense" || type == "transfer" {
            try await assertNoOverdraft(accountId: accountId, deltaMinor: -amount.amount, excludeTxnId: nil)
        }

        let id = newId()
        let ts = nowIso()
        let transferGroup = type == "transfer" ? newId() : nil
        let fxRate: Double? = (toAmount != nil && amount.amount != 0) ? Double(toAmount!.amount) / Double(amount.amount) : nil

        try await db.writeTransaction { tx in
            try tx.execute(
                sql: """
                    INSERT INTO transactions
                     (id,user_id,account_id,type,amount,currency,category_id,note,description,payment_method,occurred_at,
                      transfer_group_id,to_account_id,to_amount,fx_rate,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    """,
                parameters: [
                    id, userId, accountId, type, amount.amount, amount.currency,
                    categoryId, note, description, paymentMethod, occurredAt, transferGroup,
                    toAccountId, toAmount?.amount, fxRate, ts, ts,
                ]
            )
            for item in itemList {
                try tx.execute(
                    sql: """
                        INSERT INTO transaction_items (id,user_id,transaction_id,description,amount,created_at,updated_at)
                        VALUES (?,?,?,?,?,?,?)
                        """,
                    parameters: [newId(), userId, id, item.description, item.amount.amount, ts, ts]
                )
            }
            // Label resolution inlined here (and in updateTransaction) rather
            // than shared -- see file header note on the tx-type risk.
            if let labels, !labels.isEmpty {
                try tx.execute(sql: "DELETE FROM transaction_labels WHERE transaction_id = ?", parameters: [id])
                var seen: Set<String> = []
                for raw in labels {
                    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lower = name.lowercased()
                    if name.isEmpty || seen.contains(lower) { continue }
                    seen.insert(lower)
                    var labelId = try tx.getOptional(
                        sql: "SELECT id FROM labels WHERE user_id = ? AND name = ? AND deleted_at IS NULL",
                        parameters: [userId, name],
                        mapper: { cursor in try cursor.getString(name: "id") }
                    )
                    if labelId == nil {
                        let newLabelId = newId()
                        try tx.execute(
                            sql: "INSERT INTO labels (id,user_id,name,color,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                            parameters: [newLabelId, userId, name, nil, ts, ts]
                        )
                        labelId = newLabelId
                    }
                    try tx.execute(
                        sql: "INSERT INTO transaction_labels (id,user_id,transaction_id,label_id,created_at) VALUES (?,?,?,?,?)",
                        parameters: [newId(), userId, id, labelId, ts]
                    )
                }
            }
        }

        return TransactionRow(
            id: id, accountId: accountId, type: type, amount: amount.amount, currency: amount.currency,
            categoryId: categoryId, note: note, description: description, paymentMethod: paymentMethod,
            occurredAt: occurredAt, transferGroupId: transferGroup, toAccountId: toAccountId,
            toAmount: toAmount?.amount, fxRate: fxRate
        )
    }

    public func listByAccount(accountId: String, limit: Int = 50) async throws -> [TransactionRow] {
        try await db.getAll(
            sql: "SELECT * FROM transactions WHERE account_id = ? AND deleted_at IS NULL ORDER BY occurred_at DESC LIMIT ?",
            parameters: [accountId, limit],
            mapper: transactionMapper
        )
    }

    public func items(transactionId: String) async throws -> [TransactionItem] {
        try await db.getAll(
            sql: "SELECT * FROM transaction_items WHERE transaction_id = ? AND deleted_at IS NULL",
            parameters: [transactionId],
            mapper: itemMapper
        )
    }

    public func search(query: String, limit: Int = 50) async throws -> [TransactionRow] {
        let like = "%\(query)%"
        return try await db.getAll(
            sql: """
                SELECT t.* FROM transactions t
                WHERE t.deleted_at IS NULL AND (
                  t.note LIKE ? OR t.description LIKE ?
                  OR EXISTS (
                    SELECT 1 FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id
                    WHERE tl.transaction_id = t.id AND l.name LIKE ?
                  )
                )
                ORDER BY t.occurred_at DESC LIMIT ?
                """,
            parameters: [like, like, like, limit],
            mapper: transactionMapper
        )
    }

    /// Edit a transaction and append an audit record of what changed.
    /// [patch]'s KEY PRESENCE (not just non-nil value) decides whether a
    /// field is touched -- a missing key means "don't touch"; a present key
    /// with a nil value means "set this nullable column to null". This
    /// mirrors the real EditTransactionInput's undefined-vs-null distinction,
    /// which a plain optional Swift parameter can't represent by itself.
    /// [userId] is required for item/label/audit rows (this facade doesn't
    /// carry user_id on TransactionRow). Recognized keys: same set as the
    /// Kotlin mirror's doc comment.
    public func updateTransaction(userId: String, id: String, patch: [String: Sendable?]) async throws {
        guard let before = try await db.getOptional(sql: "SELECT * FROM transactions WHERE id = ?", parameters: [id], mapper: transactionMapper) else {
            throw NSError(domain: "LedgerRepository", code: 5, userInfo: [NSLocalizedDescriptionKey: "Transaction \(id) not found"])
        }

        var changeLog: [(String, String?, String?)] = []
        var sets: [String] = []
        var params: [Sendable?] = []
        func track(_ col: String, _ from: Sendable?, _ key: String) {
            guard patch.keys.contains(key) else { return }
            let to = patch[key] ?? nil
            if !isEqualSendable(to, from) {
                changeLog.append((col, describeSendable(from), describeSendable(to)))
                sets.append("\(col) = ?")
                params.append(to)
            }
        }
        track("type", before.type, "type")
        track("account_id", before.accountId, "account_id")
        track("amount", before.amount, "amount")
        track("category_id", before.categoryId, "category_id")
        track("note", before.note, "note")
        track("description", before.description, "description")
        track("payment_method", before.paymentMethod, "payment_method")
        track("occurred_at", before.occurredAt, "occurred_at")
        track("to_account_id", before.toAccountId, "to_account_id")
        track("to_amount", before.toAmount, "to_amount")

        let touchItems = patch.keys.contains("items")
        let itemsVal = (patch["items"] ?? nil) as? [TransactionItemInput]
        let labelsVal = (patch["labels"] ?? nil) as? [String]
        let relabel = labelsVal != nil
        if sets.isEmpty, !touchItems, !relabel { return }

        let newType = (patch["type"] ?? nil) as? String ?? before.type
        let newAccount = (patch["account_id"] ?? nil) as? String ?? before.accountId
        let newAmount = (patch["amount"] ?? nil) as? Int64 ?? before.amount
        if newType == "expense" || newType == "transfer" {
            try await assertNoOverdraft(accountId: newAccount, deltaMinor: -newAmount, excludeTxnId: id)
        }

        let ts = nowIso()

        try await db.writeTransaction { tx in
            if changeLog.contains(where: { $0.0 == "amount" }), !touchItems {
                try tx.execute(
                    sql: "UPDATE transaction_items SET deleted_at = ?, updated_at = ? WHERE transaction_id = ? AND deleted_at IS NULL",
                    parameters: [ts, ts, id]
                )
            }
            if touchItems {
                try tx.execute(
                    sql: "UPDATE transaction_items SET deleted_at = ?, updated_at = ? WHERE transaction_id = ? AND deleted_at IS NULL",
                    parameters: [ts, ts, id]
                )
                if let itemsVal, !itemsVal.isEmpty {
                    for item in itemsVal {
                        try tx.execute(
                            sql: """
                                INSERT INTO transaction_items (id,user_id,transaction_id,description,amount,created_at,updated_at)
                                VALUES (?,?,?,?,?,?,?)
                                """,
                            // Always a fresh id -- see the Kotlin mirror's
                            // comment on why reusing an incoming id would
                            // collide on the PRIMARY KEY.
                            parameters: [newId(), userId, id, item.description, item.amount.amount, ts, ts]
                        )
                    }
                }
                changeLog.append(("items", "(prev)", (itemsVal?.isEmpty ?? true) ? "none" : "\(itemsVal!.count) items"))
            }

            if relabel, let labelsVal {
                try tx.execute(sql: "DELETE FROM transaction_labels WHERE transaction_id = ?", parameters: [id])
                var seen: Set<String> = []
                for raw in labelsVal {
                    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lower = name.lowercased()
                    if name.isEmpty || seen.contains(lower) { continue }
                    seen.insert(lower)
                    var labelId = try tx.getOptional(
                        sql: "SELECT id FROM labels WHERE user_id = ? AND name = ? AND deleted_at IS NULL",
                        parameters: [userId, name],
                        mapper: { cursor in try cursor.getString(name: "id") }
                    )
                    if labelId == nil {
                        let newLabelId = newId()
                        try tx.execute(
                            sql: "INSERT INTO labels (id,user_id,name,color,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                            parameters: [newLabelId, userId, name, nil, ts, ts]
                        )
                        labelId = newLabelId
                    }
                    try tx.execute(
                        sql: "INSERT INTO transaction_labels (id,user_id,transaction_id,label_id,created_at) VALUES (?,?,?,?,?)",
                        parameters: [newId(), userId, id, labelId, ts]
                    )
                }
                changeLog.append(("labels", "(prev)", labelsVal.joined(separator: ", ")))
            }
            if !sets.isEmpty {
                sets.append("updated_at = ?")
                params.append(ts)
                params.append(id)
                try tx.execute(sql: "UPDATE transactions SET \(sets.joined(separator: ", ")) WHERE id = ?", parameters: params)
            }
            try tx.execute(
                sql: "INSERT INTO transaction_audit (id,user_id,transaction_id,action,changes,created_at) VALUES (?,?,?,?,?,?)",
                parameters: [newId(), userId, id, "update", changesToJson(changeLog), ts]
            )
        }
    }

    /// Soft-delete a transaction (and its items/labels), appending a delete
    /// audit record.
    public func removeTransaction(userId: String, id: String) async throws {
        let exists = try await db.getOptional(sql: "SELECT id FROM transactions WHERE id = ?", parameters: [id]) { cursor in
            try cursor.getString(name: "id")
        }
        guard exists != nil else { return }
        let ts = nowIso()
        try await db.writeTransaction { tx in
            try tx.execute(
                sql: "UPDATE transaction_items SET deleted_at = ?, updated_at = ? WHERE transaction_id = ? AND deleted_at IS NULL",
                parameters: [ts, ts, id]
            )
            try tx.execute(sql: "DELETE FROM transaction_labels WHERE transaction_id = ?", parameters: [id])
            try tx.execute(sql: "UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE id = ?", parameters: [ts, ts, id])
            try tx.execute(
                sql: "INSERT INTO transaction_audit (id,user_id,transaction_id,action,changes,created_at) VALUES (?,?,?,?,?,?)",
                parameters: [newId(), userId, id, "delete", "{\"deleted\":{\"from\":\"active\",\"to\":\"removed\"}}", ts]
            )
        }
    }

    public func history(transactionId: String) async throws -> [TransactionAudit] {
        try await db.getAll(
            sql: "SELECT id, transaction_id, action, changes, created_at FROM transaction_audit WHERE transaction_id = ? ORDER BY created_at DESC",
            parameters: [transactionId],
            mapper: auditMapper
        )
    }
}

/// Sendable-boxed equality/description helpers for updateTransaction's patch
/// diffing -- Sendable? values here are only ever String/Int64/Double/Bool/
/// nil in practice (SQLite bind types), so a small closed comparison covers
/// every case this facade actually produces.
private func isEqualSendable(_ a: Sendable?, _ b: Sendable?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (x as String, y as String): return x == y
    case let (x as Int64, y as Int64): return x == y
    case let (x as Double, y as Double): return x == y
    case let (x as Bool, y as Bool): return x == y
    default: return false
    }
}

private func describeSendable(_ v: Sendable?) -> String? {
    switch v {
    case nil: return nil
    case let x as String: return x
    default: return "\(v!)"
    }
}
