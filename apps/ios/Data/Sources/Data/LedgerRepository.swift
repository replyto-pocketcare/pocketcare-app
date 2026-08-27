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
// hooks.ts, not from @sanvya/data) -- they're a genuine mobile-side
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
    /// Mindfulness tag, expense-only, edit-screen-only (never set at create
    /// time -- matches transactions/new/page.tsx not having this field at
    /// all, only transactions/[id]/edit/page.tsx does). "need" | "greed" | nil.
    public let intent: String?
}

public struct CategoryRow: Sendable { public let id: String; public let name: String; public let kind: String; public let parentId: String? }
public struct LabelRow: Sendable { public let id: String; public let name: String; public let color: String? }
public struct PaymentMethodRow: Sendable { public let id: String; public let label: String; public let accountTypeId: String }

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

/// One (month, type) bucket from the income/expense grouping query -- `type`
/// is always "income" or "expense", `total` is minor units. Mirrors Android's
/// LedgerRepository.kt MonthlyIncomeExpense exactly (added same session,
/// 2026-08-05, for the dashboard hero sparkline/delta -- see
/// docs/mobile/screen-specs/dashboard.md).
/// One grouped total with the name it was grouped by. Nil name = uncategorised.
/// One day's expense total, before it is folded into a dictionary.
private struct DailyTotal: Sendable {
    let day: String
    let total: Int64
}

private struct RateRow: Sendable {
    let base: String
    let quote: String
    let rate: Double
}

/// The fold `rates()` and `watchRates()` share, so a snapshot and a stream can
/// never disagree about which rate is "latest".
private func rateLookup(_ rows: [RateRow]) -> RateLookup {
    var built: [String: Double] = [:]
    for row in rows {
        let key = "\(row.base)->\(row.quote)"
        // First wins: the query is ORDER BY as_of DESC.
        if built[key] == nil { built[key] = row.rate }
    }
    // Rebound to a `let` before the closure captures it. `RateLookup` is
    // `@Sendable` (see Ledger.swift for why), and a @Sendable closure cannot
    // capture a `var` even one nothing writes to again -- Swift 6 rejects the
    // capture, not the mutation. CI run 32986742366 is where that landed.
    let rateMap = built
    return { from, to in
        if from == to { return 1.0 }
        if let direct = rateMap["\(from)->\(to)"] { return direct }
        if let inverse = rateMap["\(to)->\(from)"] { return 1.0 / inverse }
        return 1.0
    }
}

public struct NamedTotal: Sendable {
    public let name: String?
    public let total: Int64

    public init(name: String?, total: Int64) {
        self.name = name
        self.total = total
    }
}

public struct MonthlyIncomeExpense: Sendable {
    public let yearMonth: String
    public let type: String
    public let total: Int64
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

private func namedTotalMapper(_ cursor: SqlCursor) throws -> NamedTotal {
    NamedTotal(
        // NULL means uncategorised. The view names that bucket, not the
        // repository -- a repository has no localised strings and i18n belongs
        // where the string is rendered.
        name: try cursor.getStringOptional(name: "name"),
        total: try cursor.getInt64(name: "total")
    )
}

func monthlyIncomeExpenseMapper(_ cursor: SqlCursor) throws -> MonthlyIncomeExpense {
    MonthlyIncomeExpense(
        yearMonth: try cursor.getString(name: "ym"),
        type: try cursor.getString(name: "type"),
        total: try cursor.getInt64(name: "total")
    )
}

func accountMapper(_ cursor: SqlCursor) throws -> Account {
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
        fxRate: try cursor.getDoubleOptional(name: "fx_rate"),
        intent: try cursor.getStringOptional(name: "intent")
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

    /// Single account by id (reactive) -- matches accounts/[id]/edit/page.tsx's
    /// useQuery(single row, WHERE id = ?). Added 2026-08-05 for the Accounts
    /// edit screen, mirrors Android's LedgerRepository.kt addition the same
    /// session.
    public func watchAccount(id: String) throws -> AsyncThrowingStream<Account?, Error> {
        let upstream = try db.watch(
            sql: "SELECT * FROM accounts WHERE id = ? AND deleted_at IS NULL",
            parameters: [id],
            mapper: accountMapper
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

    /// Full transaction rows for one account, newest first (for a ledger/list UI).
    public func watchTransactions(accountId: String) throws -> AsyncThrowingStream<[TransactionRow], Error> {
        try db.watch(
            sql: "SELECT * FROM transactions WHERE deleted_at IS NULL AND account_id = ? ORDER BY occurred_at DESC",
            parameters: [accountId],
            mapper: transactionMapper
        )
    }

    /// All transaction rows across all accounts, newest first (for Dashboard).
    public func watchRecentTransactions(limit: Int = 10) throws -> AsyncThrowingStream<[TransactionRow], Error> {
        try db.watch(
            sql: "SELECT * FROM transactions WHERE deleted_at IS NULL ORDER BY occurred_at DESC LIMIT ?",
            parameters: [limit],
            mapper: transactionMapper
        )
    }

    /// All transaction rows across all accounts (for Transactions list).
    public func watchAllTransactions() throws -> AsyncThrowingStream<[TransactionRow], Error> {
        try db.watch(
            sql: "SELECT * FROM transactions WHERE deleted_at IS NULL ORDER BY occurred_at DESC",
            parameters: [],
            mapper: transactionMapper
        )
    }

    /// The Search screen's haystack — web's `app/search/page.tsx` query.
    ///
    /// Three details that are the query, not decoration:
    ///
    /// - **`type != 'opening_balance'`.** An opening balance is bookkeeping,
    ///   not something the user did, and it is not searchable on web either.
    /// - **`LIMIT 2000`.** Search filters in memory, so the cap is what stops
    ///   a decade of history from being held in RAM to answer one query. It is
    ///   web's number; the visible result cap (300) is separate and lives in
    ///   Domain's `searchResultLimit`.
    /// - **Newest first.** `searchTransactions` preserves input order, so the
    ///   ORDER BY here IS the result order.
    public func watchSearchTransactions() throws -> AsyncThrowingStream<[TransactionRow], Error> {
        try db.watch(
            sql: """
                SELECT * FROM transactions
                 WHERE deleted_at IS NULL AND type != 'opening_balance'
                 ORDER BY occurred_at DESC LIMIT 2000
                """,
            parameters: [],
            mapper: transactionMapper
        )
    }

    /// Every split posting joined to its transaction — web's `useSplitInfo`.
    ///
    /// Returns Domain's `SplitPosting` rather than a Data-local twin: the
    /// aggregation that consumes it is vector-tested in Domain, and a second
    /// row shape here would exist only to be copied into the first.
    public func watchSplitPostings() throws -> AsyncThrowingStream<[SplitPosting], Error> {
        try db.watch(
            sql: """
                SELECT ep.transaction_id AS txid, ep.expense_id AS eid, ep.role AS role,
                       t.amount AS amount, t.currency AS currency, e.group_id AS gid
                  FROM expense_postings ep
                  JOIN transactions t ON t.id = ep.transaction_id AND t.deleted_at IS NULL
                  LEFT JOIN expenses e ON e.id = ep.expense_id
                 WHERE ep.deleted_at IS NULL AND ep.expense_id IS NOT NULL
                """,
            parameters: []
        ) { cursor in
            SplitPosting(
                transactionId: try cursor.getString(name: "txid"),
                expenseId: try cursor.getString(name: "eid"),
                role: try cursor.getString(name: "role"),
                amountMinor: try cursor.getInt64(name: "amount"),
                currency: try cursor.getString(name: "currency"),
                groupId: try cursor.getStringOptional(name: "gid")
            )
        }
    }

    /// Transactions inside a date range, for the Statements screen.
    ///
    /// Matches statements/page.tsx's query exactly, including two details that
    /// are easy to lose:
    ///
    /// - **`type != 'opening_balance'`.** An opening balance is a bookkeeping
    ///   entry, not something the user did. Including it would put a phantom
    ///   line on the statement and inflate the income total.
    /// - **`>= start AND < end`**, with `end` already advanced one day by the
    ///   caller. A `BETWEEN` on ISO timestamps would silently drop everything
    ///   that happened after midnight on the last day.
    public func watchTransactionsInRange(
        startIso: String,
        endIso: String
    ) throws -> AsyncThrowingStream<[TransactionRow], Error> {
        try db.watch(
            sql: """
                SELECT * FROM transactions
                 WHERE deleted_at IS NULL AND type != 'opening_balance'
                   AND occurred_at >= ? AND occurred_at < ?
                 ORDER BY occurred_at
                """,
            parameters: [startIso, endIso],
            mapper: transactionMapper
        )
    }

    /// All categories (reactive) -- matches transactions/new/page.tsx's
    /// categories query. Added 2026-08-05 for the Transactions screens
    /// (docs/mobile/screen-specs/transactions.md); mirrors Android's
    /// LedgerRepository.kt addition the same session.
    public func watchCategories() throws -> AsyncThrowingStream<[CategoryRow], Error> {
        try db.watch(
            sql: "SELECT id, name, kind, parent_id FROM categories WHERE deleted_at IS NULL ORDER BY name",
            parameters: [],
            mapper: { cursor in
                CategoryRow(
                    id: try cursor.getString(name: "id"),
                    name: try cursor.getString(name: "name"),
                    kind: try cursor.getString(name: "kind"),
                    parentId: try cursor.getStringOptional(name: "parent_id")
                )
            }
        )
    }

    /// All labels (reactive). Added 2026-08-05 for the Transactions screens.
    public func watchLabels() throws -> AsyncThrowingStream<[LabelRow], Error> {
        try db.watch(
            sql: "SELECT id, name, color FROM labels WHERE deleted_at IS NULL ORDER BY name",
            parameters: [],
            mapper: { cursor in
                LabelRow(
                    id: try cursor.getString(name: "id"),
                    name: try cursor.getString(name: "name"),
                    color: try cursor.getStringOptional(name: "color")
                )
            }
        )
    }

    /// Every (account_type, payment_method) pairing, unfiltered -- callers
    /// filter to the selected account's type client-side. Added 2026-08-05
    /// for the Transactions screens.
    public func watchPaymentMethods() throws -> AsyncThrowingStream<[PaymentMethodRow], Error> {
        try db.watch(
            sql: """
                SELECT pm.id, pm.label, m.account_type_id
                FROM account_type_payment_methods m JOIN payment_methods pm ON pm.id = m.payment_method_id
                ORDER BY pm.sort
                """,
            parameters: [],
            mapper: { cursor in
                PaymentMethodRow(
                    id: try cursor.getString(name: "id"),
                    label: try cursor.getString(name: "label"),
                    accountTypeId: try cursor.getString(name: "account_type_id")
                )
            }
        )
    }

    /// transaction_id -> ordered label names (reactive) -- used by the
    /// Transactions list (tag row) and Edit (seeding the label picker).
    /// Added 2026-08-05 for the Transactions screens, mirrors Android's
    /// watchTransactionLabelNames() (flat join, grouped client-side rather
    /// than SQL GROUP_CONCAT, so the same query shape serves both the list
    /// and a single-transaction lookup).
    public func watchTransactionLabelNames() throws -> AsyncThrowingStream<[String: [String]], Error> {
        struct Row: Sendable { let transactionId: String; let name: String }
        let rows: AsyncThrowingStream<[Row], Error> = try db.watch(
            sql: """
                SELECT tl.transaction_id, l.name FROM transaction_labels tl
                JOIN labels l ON l.id = tl.label_id ORDER BY l.name
                """,
            parameters: [],
            mapper: { cursor in
                Row(transactionId: try cursor.getString(name: "transaction_id"), name: try cursor.getString(name: "name"))
            }
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await batch in rows {
                        var map: [String: [String]] = [:]
                        for row in batch { map[row.transactionId, default: []].append(row.name) }
                        continuation.yield(map)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
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

    /// Income/expense totals grouped by month (all accounts, minor units) --
    /// matches apps/web/app/page.tsx's NetWorthHero query exactly (same SQL,
    /// same GROUP BY/ORDER BY). One-shot (matches this file's existing
    /// snapshot pattern -- DashboardViewModel re-runs its snapshot refresh on
    /// every account/transaction stream tick already).
    static let monthlyIncomeExpenseSql = """
        SELECT strftime('%Y-%m', occurred_at) as ym, type, SUM(amount) as total
        FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense')
        GROUP BY ym, type ORDER BY ym
        """

    public func monthlyIncomeExpense() async throws -> [MonthlyIncomeExpense] {
        try await db.getAll(sql: Self.monthlyIncomeExpenseSql, parameters: [], mapper: monthlyIncomeExpenseMapper)
    }

    /**
     Monthly income/expense totals, REACTIVE.

     Android has had `watchMonthlyIncomeExpense` all along; this side was a
     one-shot because the screen that needed it re-ran its own refresh. The
     dashboard's month-comparison tile needs a stream, and it is one query, so
     no `combineLatest` is involved — just the watch that should always have
     been here beside the snapshot.
     */
    public func watchMonthlyIncomeExpense() throws -> AsyncThrowingStream<[MonthlyIncomeExpense], Error> {
        try db.watch(sql: Self.monthlyIncomeExpenseSql, parameters: [], mapper: monthlyIncomeExpenseMapper)
    }

    /**
     Expense totals grouped by CATEGORY, biggest first — web's ByCategoryTile.

     The `lend` exclusion is web's, and it matters: money you fronted for someone
     is not your spending, and without it an evening you paid for shows up as
     your biggest category. Every spending query on the dashboard carries it.
     */
    public func watchExpenseByCategory(limit: Int = 8) throws -> AsyncThrowingStream<[NamedTotal], Error> {
        try db.watch(
            sql: """
                SELECT c.name AS name, SUM(t.amount) AS total
                  FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
                 WHERE t.deleted_at IS NULL AND t.type = 'expense'
                   AND t.id NOT IN (
                         SELECT transaction_id FROM expense_postings
                          WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)
                 GROUP BY t.category_id ORDER BY total DESC LIMIT ?
                """,
            parameters: [limit],
            mapper: namedTotalMapper
        )
    }

    /// Expense totals grouped by LABEL, biggest first — web's ByLabelTile.
    public func watchExpenseByLabel(limit: Int = 8) throws -> AsyncThrowingStream<[NamedTotal], Error> {
        try db.watch(
            sql: """
                SELECT l.name AS name, SUM(t.amount) AS total
                  FROM transaction_labels tl
                  JOIN labels l ON l.id = tl.label_id
                  JOIN transactions t ON t.id = tl.transaction_id
                 WHERE t.deleted_at IS NULL AND t.type = 'expense'
                   AND t.id NOT IN (
                         SELECT transaction_id FROM expense_postings
                          WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)
                 GROUP BY l.id ORDER BY total DESC LIMIT ?
                """,
            parameters: [limit],
            mapper: namedTotalMapper
        )
    }

    /**
     Expense totals grouped by CATEGORY, **since `sinceIso`** — web's
     SpendingTile.

     The by-category tile above has no date bound; this one does. Two methods
     rather than one with an optional date: the `lend` exclusion and the
     grouping are identical, and an optional parameter that changes the WHERE
     clause is how a query quietly starts answering two questions.
     */
    public func watchExpenseByCategorySince(_ sinceIso: String) throws -> AsyncThrowingStream<[NamedTotal], Error> {
        try db.watch(
            sql: """
                SELECT c.name AS name, SUM(t.amount) AS total
                  FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
                 WHERE t.deleted_at IS NULL AND t.type = 'expense' AND t.occurred_at >= ?
                   AND t.id NOT IN (
                         SELECT transaction_id FROM expense_postings
                          WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)
                 GROUP BY t.category_id ORDER BY total DESC
                """,
            parameters: [sinceIso],
            mapper: namedTotalMapper
        )
    }

    /**
     Monthly income/expense totals **with web's `lend` exclusion** — the series
     behind Cashflow, Net cashflow trend and This-month-vs-last.

     Web has TWO monthly queries and they differ: `NetWorthHero`'s has no
     exclusion (that is `watchMonthlyIncomeExpense` above), `useCashflow`'s does.
     Money you fronted for someone is not your expense, so a month in which you
     paid for a group dinner would otherwise read as a spending spike on the very
     charts meant to show your trend.
     */
    public func watchMonthlyCashflow() throws -> AsyncThrowingStream<[MonthlyIncomeExpense], Error> {
        try db.watch(
            sql: """
                SELECT strftime('%Y-%m', occurred_at) as ym, type, SUM(amount) as total
                  FROM transactions
                 WHERE deleted_at IS NULL AND type IN ('income','expense')
                   AND id NOT IN (
                         SELECT transaction_id FROM expense_postings
                          WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)
                 GROUP BY ym, type ORDER BY ym
                """,
            parameters: [],
            mapper: monthlyIncomeExpenseMapper
        )
    }

    /**
     Daily expense totals since `sinceIso` — the raw material for `buildTrend`.

     Grouped by `date(occurred_at)`, which SQLite evaluates in UTC. Same caveat
     as the monthly buckets, and the same reason for keeping it: web's query is
     identical, and a native-only correction would make the two disagree about
     which day a late-evening coffee belongs to.
     */
    public func watchDailyExpenseSince(_ sinceIso: String) throws -> AsyncThrowingStream<[String: Int64], Error> {
        let upstream = try db.watch(
            sql: """
                SELECT date(occurred_at) as d, SUM(amount) as total
                  FROM transactions
                 WHERE deleted_at IS NULL AND type = 'expense' AND occurred_at >= ?
                   AND id NOT IN (
                         SELECT transaction_id FROM expense_postings
                          WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)
                 GROUP BY d ORDER BY d
                """,
            parameters: [sinceIso],
            mapper: { cursor in
                DailyTotal(day: try cursor.getString(name: "d"), total: try cursor.getInt64(name: "total"))
            }
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await rows in upstream {
                        continuation.yield(Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0.total) }))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Minimal ledger-entry projection for balance derivation, REACTIVE.
    public func watchLedgerEntries() throws -> AsyncThrowingStream<[LedgerEntry], Error> {
        try db.watch(
            sql: "SELECT type, account_id, amount, to_account_id, to_amount FROM transactions WHERE deleted_at IS NULL",
            parameters: [],
            mapper: ledgerEntryMapper
        )
    }

    /**
     All accounts with their ledger-derived balances, REACTIVE.

     Android has combined these two watches since the Accounts screen was built;
     this side was a snapshot for one reason — `AsyncThrowingStream` had no
     `combineLatest`. It does now (`Streams.swift`), so this is the same two
     queries Android combines, combined the same way. The one-shot
     `accountBalances` stays for callers that want a single read.
     */
    public func watchAccountBalances(includeArchived: Bool = false) throws -> AsyncThrowingStream<[AccountWithBalance], Error> {
        let combined = combineLatest(
            try watchAccounts(includeArchived: includeArchived),
            try watchLedgerEntries()
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await (accounts, entries) in combined {
                        continuation.yield(accounts.map {
                            AccountWithBalance(account: $0, balance: deriveBalance($0.id, $0.currency, entries))
                        })
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Latest FX rate per currency pair, as of now, as a RateLookup for aggregateNetWorth.
    public func rates() async throws -> RateLookup {
        let rows = try await db.getAll(
            sql: "SELECT base_currency, quote_currency, rate, as_of FROM exchange_rates ORDER BY as_of DESC",
            parameters: []
        ) { cursor in
            RateRow(
                base: try cursor.getString(name: "base_currency"),
                quote: try cursor.getString(name: "quote_currency"),
                rate: (try cursor.getDoubleOptional(name: "rate")) ?? 1.0
            )
        }
        return rateLookup(rows)
    }

    /// Latest FX rate per currency pair, REACTIVE — same fold as `rates()`.
    public func watchRates() throws -> AsyncThrowingStream<RateLookup, Error> {
        let upstream = try db.watch(
            sql: "SELECT base_currency, quote_currency, rate, as_of FROM exchange_rates ORDER BY as_of DESC",
            parameters: [],
            mapper: { cursor in
                RateRow(
                    base: try cursor.getString(name: "base_currency"),
                    quote: try cursor.getString(name: "quote_currency"),
                    rate: (try cursor.getDoubleOptional(name: "rate")) ?? 1.0
                )
            }
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await rows in upstream { continuation.yield(rateLookup(rows)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
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

    // MARK: - CSV import / export

    /// Every non-deleted transaction as a PocketCare-format CSV.
    ///
    /// Web writes `(amount / 100).toFixed(2)` here — the same hardcoded ×100
    /// the de-hardcoding programme is removing everywhere else, and worse than
    /// usual because the importer reads it straight back: a ¥500 charge exports
    /// as "5.00" and re-imports as ¥5. This uses the currency's own minor-unit
    /// count in both directions, so a round trip is lossless for every currency.
    public func exportTransactionsCsv() async throws -> (csv: String, count: Int) {
        struct ExportRow: Sendable {
            let occurredAt: String
            let type: String
            let amount: Int64
            let currency: String
            let account: String?
            let toAccount: String?
            let toAmount: Int64?
            let category: String?
            let labels: String?
            let method: String?
            let note: String?
            let description: String?
        }

        let rows: [ExportRow] = try await db.getAll(
            sql: """
                SELECT t.occurred_at, t.type, t.amount, t.currency,
                       a.name  AS account,
                       a2.name AS to_account, t.to_amount,
                       c.name  AS category,
                       (SELECT GROUP_CONCAT(l.name, '|') FROM transaction_labels tl
                          JOIN labels l ON l.id = tl.label_id
                         WHERE tl.transaction_id = t.id) AS labels,
                       (SELECT pm.label FROM payment_methods pm WHERE pm.id = t.payment_method) AS method,
                       t.note, t.description
                  FROM transactions t
                  LEFT JOIN accounts   a  ON a.id  = t.account_id
                  LEFT JOIN accounts   a2 ON a2.id = t.to_account_id
                  LEFT JOIN categories c  ON c.id  = t.category_id
                 WHERE t.deleted_at IS NULL
                 ORDER BY t.occurred_at
                """,
            parameters: [],
            mapper: { cursor in
                ExportRow(
                    occurredAt: try cursor.getString(name: "occurred_at"),
                    type: try cursor.getString(name: "type"),
                    amount: try cursor.getInt64(name: "amount"),
                    currency: try cursor.getString(name: "currency"),
                    account: try cursor.getStringOptional(name: "account"),
                    toAccount: try cursor.getStringOptional(name: "to_account"),
                    toAmount: try cursor.getInt64Optional(name: "to_amount"),
                    category: try cursor.getStringOptional(name: "category"),
                    labels: try cursor.getStringOptional(name: "labels"),
                    method: try cursor.getStringOptional(name: "method"),
                    note: try cursor.getStringOptional(name: "note"),
                    description: try cursor.getStringOptional(name: "description")
                )
            }
        )

        var table: [[String?]] = [exportHeaders]
        for r in rows {
            table.append([
                r.occurredAt,
                r.type,
                majorText(r.amount, r.currency),
                r.currency,
                r.account ?? "",
                r.toAccount ?? "",
                r.toAmount.map { majorText($0, r.currency) } ?? "",
                r.category ?? "",
                r.labels ?? "",
                r.method ?? "",
                r.note ?? "",
                r.description ?? "",
            ])
        }
        return (csv: toCsv(table), count: rows.count)
    }

    public struct ImportResult: Sendable {
        public var created = 0
        public var skipped = 0
        public var failed = 0
        public var errors: [String] = []
    }

    /**
     Imports canonical rows: find-or-create accounts and categories, then insert
     the transactions.

     ONE write transaction for the whole file, which is web's `…Bulk` variant
     rather than its per-row one. PowerSync records a CRUD entry per row and
     uploads a contiguous run as a single batched request; a transaction per row
     means one PostgREST request per row on the next sync, which for a
     ten-thousand-line statement is the difference between one upload and ten
     thousand.

     Labels, transfers' destination legs and the overdraft guard are NOT handled
     here, matching the bulk variant: imported rows are historical facts, not
     new spend to validate.
     */
    public func importTransactions(
        userId: String,
        rows: [CanonRow],
        baseCurrency: String,
        nowIso stampIso: String,
        skipDuplicates: Bool = true
    ) async throws -> ImportResult {
        var result = ImportResult()
        if rows.isEmpty { return result }

        var accountCache: [String: String] = [:]
        for row in try await db.getAll(
            sql: "SELECT id, name FROM accounts WHERE deleted_at IS NULL",
            parameters: [],
            mapper: { c in (try c.getString(name: "id"), try c.getString(name: "name")) }
        ) {
            accountCache[row.1.trimmingCharacters(in: .whitespaces).lowercased()] = row.0
        }

        var categoryCache: [String: String] = [:]
        for row in try await db.getAll(
            sql: "SELECT id, name, kind FROM categories WHERE deleted_at IS NULL",
            parameters: [],
            mapper: { c in
                (try c.getString(name: "id"), try c.getString(name: "name"), try c.getString(name: "kind"))
            }
        ) {
            categoryCache["\(row.2):\(row.1.trimmingCharacters(in: .whitespaces).lowercased())"] = row.0
        }

        var seen = Set<String>()
        if skipDuplicates {
            for key in try await db.getAll(
                sql: "SELECT account_id, amount, type, occurred_at FROM transactions WHERE deleted_at IS NULL",
                parameters: [],
                mapper: { c in
                    "\(try c.getString(name: "account_id"))|\(try c.getInt64(name: "amount"))|\(try c.getString(name: "type"))|\(try c.getString(name: "occurred_at"))"
                }
            ) { seen.insert(key) }
        }

        let ts = nowIso()
        // Captured out of the transaction body and copied back after: the
        // closure cannot mutate `result` in place under Swift 6.
        var created = 0, skipped = 0, failed = 0
        var errors: [String] = []

        try await db.writeTransaction { tx in
            for row in rows {
                do {
                    let currency = row.currency.isEmpty ? baseCurrency : row.currency
                    let occurredAt = importDate(row.date, nowIso: stampIso)
                    let amountMinor = fromMajor(row.amount, currency).amount

                    let accountKey = row.account.trimmingCharacters(in: .whitespaces).lowercased()
                    let accountId: String
                    if let hit = accountCache[accountKey] {
                        accountId = hit
                    } else {
                        accountId = newId()
                        try tx.execute(
                            sql: """
                                INSERT INTO accounts (id,user_id,name,type,currency,icon,color,is_archived,include_in_net_worth,created_at,updated_at)
                                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                                """,
                            parameters: [
                                accountId, userId, row.account.trimmingCharacters(in: .whitespaces),
                                guessAccountType(row.account), currency, nil, nil, 0, 1, ts, ts,
                            ]
                        )
                        accountCache[accountKey] = accountId
                    }

                    let dupKey = "\(accountId)|\(amountMinor)|\(row.type)|\(occurredAt)"
                    if skipDuplicates && seen.contains(dupKey) {
                        skipped += 1
                        continue
                    }
                    seen.insert(dupKey)

                    var categoryId: String?
                    if let name = row.category, row.type == "income" || row.type == "expense" {
                        let kind = row.type == "income" ? "income" : "expense"
                        let key = "\(kind):\(name.trimmingCharacters(in: .whitespaces).lowercased())"
                        if let hit = categoryCache[key] {
                            categoryId = hit
                        } else {
                            let id = newId()
                            try tx.execute(
                                sql: """
                                    INSERT INTO categories (id,user_id,name,kind,is_system,parent_id,icon,color,created_at,updated_at)
                                    VALUES (?,?,?,?,?,?,?,?,?,?)
                                    """,
                                parameters: [
                                    id, userId, name.trimmingCharacters(in: .whitespaces), kind,
                                    0, nil, nil, nil, ts, ts,
                                ]
                            )
                            categoryCache[key] = id
                            categoryId = id
                        }
                    }

                    try tx.execute(
                        sql: """
                            INSERT INTO transactions
                              (id,user_id,account_id,type,amount,currency,category_id,note,description,payment_method,
                               occurred_at,transfer_group_id,to_account_id,to_amount,fx_rate,created_at,updated_at)
                            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                            """,
                        parameters: [
                            newId(), userId, accountId, row.type, amountMinor, currency, categoryId,
                            row.note, row.description, nil, occurredAt, nil, nil, nil, nil, ts, ts,
                        ]
                    )
                    created += 1
                } catch {
                    failed += 1
                    if errors.count < 8 { errors.append(String(describing: error)) }
                }
            }
        }

        result.created = created
        result.skipped = skipped
        result.failed = failed
        result.errors = errors
        return result
    }

    /// The Reflect queue — web's `useIntentQueue`.
    ///
    /// Untagged expenses only, newest first, capped at 50. `intent` is the
    /// mindfulness tag; a row that already has one has been judged and must not
    /// come back.
    ///
    /// The category and account names are joined here rather than resolved in
    /// the view model: this is the only reader that wants them ALONGSIDE the
    /// row, and the alternative is holding two more maps for a screen that
    /// shows one card at a time.
    public struct IntentQueueRow: Identifiable, Sendable {
        public let id: String
        public let description: String?
        public let note: String?
        public let amountMinor: Int64
        public let currency: String
        public let occurredAt: String
        public let categoryName: String?
        public let accountName: String?
    }

    public func watchIntentQueue(limit: Int = 50) throws -> AsyncThrowingStream<[IntentQueueRow], Error> {
        try db.watch(
            sql: """
                SELECT t.id AS id, t.description AS description, t.note AS note,
                       t.amount AS amount, t.currency AS currency, t.occurred_at AS occurred_at,
                       c.name AS category_name, a.name AS account_name
                  FROM transactions t
                  LEFT JOIN categories c ON c.id = t.category_id
                  LEFT JOIN accounts a ON a.id = t.account_id
                 WHERE t.type = 'expense'
                   AND t.intent IS NULL
                   AND t.deleted_at IS NULL
                 ORDER BY t.occurred_at DESC
                 LIMIT ?
                """,
            parameters: [limit]
        ) { cursor in
            IntentQueueRow(
                id: try cursor.getString(name: "id"),
                description: try cursor.getStringOptional(name: "description"),
                note: try cursor.getStringOptional(name: "note"),
                amountMinor: try cursor.getInt64(name: "amount"),
                currency: try cursor.getString(name: "currency"),
                occurredAt: try cursor.getString(name: "occurred_at"),
                categoryName: try cursor.getStringOptional(name: "category_name"),
                accountName: try cursor.getStringOptional(name: "account_name")
            )
        }
    }

    /// Tags an expense "need" or "greed", or clears the tag when `intent` is
    /// nil — which is what Reflect's Undo does.
    public func setIntent(id: String, intent: String?) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE transactions SET intent = ?, updated_at = ? WHERE id = ?",
            parameters: [intent, ts, id]
        )
    }

    // MARK: - Categories and labels
    //
    // The taxonomy screens' writes. Web does them through generic
    // `insertRow`/`updateRow`/`softDelete` helpers that take a table name and a
    // dictionary; these are typed per table instead, because a string table
    // name and an untyped bag of columns is exactly the shape that let web's
    // own `insertRow` grow a hardcoded list of tables it must not stamp a
    // `user_id` onto.
    //
    // Deletes are SOFT on both tables. A category or label may be referenced by
    // transactions that have already synced to other devices; removing the row
    // would orphan them. `deleted_at` is what every read here already filters
    // on, and it is what syncs.

    public func createCategory(
        userId: String,
        name: String,
        kind: String,
        parentId: String? = nil
    ) async throws -> String {
        let id = newId()
        let ts = nowIso()
        try await db.execute(
            sql: """
                INSERT INTO categories (id,user_id,name,kind,is_system,parent_id,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?)
                """,
            // is_system = 0: a category the user typed is theirs to rename and
            // delete. Web passes the same literal.
            parameters: [id, userId, name, kind, 0, parentId, ts, ts]
        )
        return id
    }

    public func renameCategory(id: String, name: String) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE categories SET name = ?, updated_at = ? WHERE id = ?",
            parameters: [name, ts, id]
        )
    }

    public func deleteCategory(id: String) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE categories SET deleted_at = ?, updated_at = ? WHERE id = ?",
            parameters: [ts, ts, id]
        )
    }

    public func createLabel(userId: String, name: String, color: String?) async throws -> String {
        let id = newId()
        let ts = nowIso()
        try await db.execute(
            sql: "INSERT INTO labels (id,user_id,name,color,created_at,updated_at) VALUES (?,?,?,?,?,?)",
            parameters: [id, userId, name, color, ts, ts]
        )
        return id
    }

    public func updateLabel(id: String, name: String, color: String?) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE labels SET name = ?, color = ?, updated_at = ? WHERE id = ?",
            parameters: [name, color, ts, id]
        )
    }

    public func deleteLabel(id: String) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE labels SET deleted_at = ?, updated_at = ? WHERE id = ?",
            parameters: [ts, ts, id]
        )
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

    /// Soft-delete every non-deleted transaction on [accountId] -- matches
    /// accounts/[id]/edit/page.tsx's "Delete everything" cascade path exactly
    /// (raw UPDATE, transactions first; the account itself is soft-deleted
    /// separately by the caller via deleteAccount()). Added 2026-08-05,
    /// mirrors Android's LedgerRepository.kt addition the same session.
    public func cascadeDeleteAccountTransactions(accountId: String) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE account_id = ? AND deleted_at IS NULL",
            parameters: [ts, ts, accountId]
        )
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
            toAmount: toAmount?.amount, fxRate: fxRate, intent: nil
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
        track("intent", before.intent, "intent")

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

        // Precompute everything the transaction closure needs as `let`s
        // BEFORE opening it: Swift 6's strict concurrency checker forbids
        // referencing OR mutating a captured `var` inside a concurrently-
        // executing closure like writeTransaction's (confirmed by a real
        // xcodebuild failure on the first version of this function, which
        // mutated changeLog/sets/params from inside the closure) -- only
        // `let` captures of Sendable values are safe. All of this is pure
        // decision-making based on already-known patch/before state (not on
        // anything the transaction itself produces), so hoisting it out
        // changes nothing about correctness or atomicity, only where it's
        // computed.
        let touchesAmount = changeLog.contains { $0.0 == "amount" }
        var fullChangeLog = changeLog
        if touchItems {
            fullChangeLog.append(("items", "(prev)", (itemsVal?.isEmpty ?? true) ? "none" : "\(itemsVal!.count) items"))
        }
        if relabel, let labelsVal {
            fullChangeLog.append(("labels", "(prev)", labelsVal.joined(separator: ", ")))
        }
        var fullSets = sets
        var fullParams = params
        if !fullSets.isEmpty {
            fullSets.append("updated_at = ?")
            fullParams.append(ts)
            fullParams.append(id)
        }
        let finalChangeLog = fullChangeLog
        let finalSets = fullSets
        let finalParams = fullParams
        let changesJson = changesToJson(finalChangeLog)

        try await db.writeTransaction { tx in
            if touchesAmount, !touchItems {
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
            }
            if !finalSets.isEmpty {
                try tx.execute(sql: "UPDATE transactions SET \(finalSets.joined(separator: ", ")) WHERE id = ?", parameters: finalParams)
            }
            try tx.execute(
                sql: "INSERT INTO transaction_audit (id,user_id,transaction_id,action,changes,created_at) VALUES (?,?,?,?,?,?)",
                parameters: [newId(), userId, id, "update", changesJson, ts]
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
