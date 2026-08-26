package com.sanvya.app.data.repository

/**
 * Read/write facade over the local PowerSync SQLite DB for accounts and
 * transactions (P2.5). Mirrors apps/web/src/hooks.ts's useAccountBalances/
 * useNetWorth/useRates for the REACTIVE reads (query raw rows, then call the
 * already-ported pure domain functions -- deriveBalance, aggregateNetWorth --
 * money+ledger domain, P1.1/P1.2 -- for any derived value), and mirrors
 * packages/data/src/powersync-repositories.ts's PowerSyncAccountRepository /
 * PowerSyncTransactionRepository / PowerSyncBalanceRepository for the WRITE
 * business logic and one-shot spec reads.
 *
 * IMPORTANT CORRECTION (this revision): the first version of this file
 * (commit 72dcb2b) was built by reverse-engineering apps/web/src/hooks.ts and
 * write.ts, WITHOUT knowing that a real, authoritative repository layer
 * already exists at packages/data/src/powersync-repositories.ts and is what
 * apps/web/src/powersync.ts's getRepositories() actually wires up for all
 * domain writes (dashboard tiles, transaction forms, credit-card settle,
 * etc). Per CLAUDE.md golden rule 8 ("web is the spec"), THAT file -- not
 * hooks.ts/write.ts -- is the correct source of truth for write behavior.
 * This revision ports its business logic faithfully: overdraft protection
 * (OverdraftError/assertNoOverdraft), opening-balance semantics
 * (setOpeningBalance), transaction breakdown items (transaction_items,
 * itemsReconcile-checked), labels (labels/transaction_labels,
 * find-or-create), and a change-audit trail (transaction_audit). The
 * reactive watch()-based reads have NO equivalent in the real repository
 * layer at all (the web app gets reactivity from separate useQuery hooks in
 * hooks.ts, not from @sanvya/data) -- they're a genuine mobile-side
 * addition on top of the spec, not a divergence from it, and are kept.
 *
 * One deliberate, documented divergence: PowerSyncBalanceRepository.netWorth()
 * in the real spec is currently an explicit unfinished placeholder that
 * always returns money(0, base) (comment: "full multi-account + FX
 * aggregation lands in Phase 5"). This repository's watchNetWorth() computes
 * a real answer via aggregateNetWorth (already correct domain logic, ported
 * in P1.2). Regressing mobile to match a stated placeholder would be a
 * strictly worse user experience for no fidelity benefit -- when the web
 * spec's real Phase 5 aggregation ships, reconcile the two.
 *
 * Table columns confirmed against the generated schema descriptor
 * (PocketCareSchema.kt, P2.1) and against supabase/migrations/0001_init.sql
 * (transaction_items/labels/transaction_labels/transaction_audit column
 * lists), not assumed.
 *
 * PowerSync Kotlin SDK call shapes (get/getOptional/getAll/execute/
 * writeTransaction) confirmed against docs.powersync.com's Kotlin SDK
 * reference page (fetched live), not assumed -- see that page's "Using
 * PowerSync: CRUD functions" section. The label-writing logic that the real
 * TS spec factors into a shared `writeLabels(tx, ...)` helper is inlined at
 * both of its two call sites here (create/update) instead, deliberately: the
 * real transaction-context type's exact name (PowerSyncTransaction, per
 * secondary web-search corroboration but not a fetched source file) wasn't
 * independently confirmed, and Kotlin's lambda-parameter type inference lets
 * `db.writeTransaction { tx -> ... }` avoid ever having to spell that type
 * out -- safer than risking a wrong import in code with no compiler to catch it.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.getBooleanOptional
import com.powersync.db.getDoubleOptional
import com.powersync.db.getLong
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import com.sanvya.app.domain.ledger.AccountBalance
import com.sanvya.app.domain.ledger.LedgerEntry
import com.sanvya.app.domain.ledger.RateLookup
import com.sanvya.app.domain.ledger.aggregateNetWorth
import com.sanvya.app.domain.ledger.deriveBalance
import com.sanvya.app.domain.money.Money
import com.sanvya.app.domain.money.itemsReconcile
import com.sanvya.app.domain.money.money
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map

data class Account(
    val id: String,
    val userId: String?,
    val name: String,
    val type: String,
    val currency: String,
    val icon: String?,
    val color: String?,
    val isArchived: Boolean,
    val includeInNetWorth: Boolean,
    val allowNegative: Boolean,
    /** Virtual split accounts (receivable/payable) use "split"; "real" otherwise. */
    val kind: String,
    val createdAt: String,
    val updatedAt: String,
)

data class TransactionRow(
    val id: String,
    val accountId: String,
    val type: String,
    val amount: Long,
    val currency: String,
    val categoryId: String?,
    val note: String?,
    val description: String?,
    val paymentMethod: String?,
    val occurredAt: String,
    val transferGroupId: String?,
    val toAccountId: String?,
    val toAmount: Long?,
    val fxRate: Double?,
    /** Mindfulness tag, expense-only, edit-screen-only (never set at create
     * time -- matches transactions/new/page.tsx not having this field at
     * all, only transactions/[id]/edit/page.tsx does). "need" | "greed" | null. */
    val intent: String? = null,
)

data class CategoryRow(val id: String, val name: String, val kind: String, val parentId: String?)
data class LabelRow(val id: String, val name: String, val color: String?)
data class PaymentMethodRow(val id: String, val label: String, val accountTypeId: String)

data class TransactionItemInput(val description: String, val amount: Money)

data class TransactionItem(
    val id: String,
    val transactionId: String,
    val description: String,
    val amount: Long,
)

data class TransactionAudit(
    val id: String,
    val transactionId: String,
    val action: String,
    /** JSON string of { field: { from, to } } -- not parsed here, mirrors the real repo's shape. */
    val changes: String?,
    val createdAt: String,
)

data class AccountWithBalance(val account: Account, val balance: Money)

data class NetWorth(val total: Money, val available: Money, val base: String)

/** One (month, type) bucket from the income/expense grouping query -- [type] is
 * always "income" or "expense" (query filters to those two), [total] is minor
 * units. */
/** One grouped total with the name it was grouped by. Null name = uncategorised. */
data class NamedTotal(val name: String?, val total: Long)

data class MonthlyIncomeExpense(val yearMonth: String, val type: String, val total: Long)

/** Thrown when a write would take a no-overdraft account below zero.
 * Mirrors packages/data/src/powersync-repositories.ts's OverdraftError. */
class OverdraftError(val accountName: String, val shortfall: Money) : Exception(
    "Recording this would take \"$accountName\" below zero. " +
        "Turn on \"Allow negative balance\" for this account, or reduce the amount.",
) {
    val code: String = "OVERDRAFT"
}

private fun accountMapper(cursor: com.powersync.db.SqlCursor): Account = Account(
    id = cursor.getString("id"),
    userId = cursor.getStringOptional("user_id"),
    name = cursor.getString("name"),
    type = cursor.getString("type"),
    currency = cursor.getString("currency"),
    icon = cursor.getStringOptional("icon"),
    color = cursor.getStringOptional("color"),
    // IFNULL-style defaults matching apps/web/src/hooks.ts's exact semantics:
    // missing/older rows are treated as not-archived, included in net worth,
    // and a "real" (non-split) account.
    isArchived = cursor.getBooleanOptional("is_archived") ?: false,
    includeInNetWorth = cursor.getBooleanOptional("include_in_net_worth") ?: true,
    allowNegative = cursor.getBooleanOptional("allow_negative") ?: false,
    kind = cursor.getStringOptional("kind") ?: "real",
    createdAt = cursor.getString("created_at"),
    updatedAt = cursor.getString("updated_at"),
)

private fun transactionMapper(cursor: com.powersync.db.SqlCursor): TransactionRow = TransactionRow(
    id = cursor.getString("id"),
    accountId = cursor.getString("account_id"),
    type = cursor.getString("type"),
    amount = cursor.getLong("amount"),
    currency = cursor.getString("currency"),
    categoryId = cursor.getStringOptional("category_id"),
    note = cursor.getStringOptional("note"),
    description = cursor.getStringOptional("description"),
    paymentMethod = cursor.getStringOptional("payment_method"),
    occurredAt = cursor.getString("occurred_at"),
    transferGroupId = cursor.getStringOptional("transfer_group_id"),
    toAccountId = cursor.getStringOptional("to_account_id"),
    toAmount = cursor.getLongOptional("to_amount"),
    fxRate = cursor.getDoubleOptional("fx_rate"),
    intent = cursor.getStringOptional("intent"),
)

private fun ledgerEntryMapper(cursor: com.powersync.db.SqlCursor): LedgerEntry = LedgerEntry(
    type = cursor.getString("type"),
    accountId = cursor.getString("account_id"),
    amount = cursor.getLong("amount"),
    toAccountId = cursor.getStringOptional("to_account_id"),
    toAmount = cursor.getLongOptional("to_amount"),
)

private fun itemMapper(cursor: com.powersync.db.SqlCursor): TransactionItem = TransactionItem(
    id = cursor.getString("id"),
    transactionId = cursor.getString("transaction_id"),
    description = cursor.getString("description"),
    amount = cursor.getLong("amount"),
)

private fun auditMapper(cursor: com.powersync.db.SqlCursor): TransactionAudit = TransactionAudit(
    id = cursor.getString("id"),
    transactionId = cursor.getString("transaction_id"),
    action = cursor.getString("action"),
    changes = cursor.getStringOptional("changes"),
    createdAt = cursor.getString("created_at"),
)

class LedgerRepository(private val db: PowerSyncDatabase) {

    // ---- reads (reactive) ----

    /** All accounts (reactive). Archived accounts excluded unless [includeArchived]. */
    fun watchAccounts(includeArchived: Boolean = false): Flow<List<Account>> {
        val where = if (includeArchived) {
            "deleted_at IS NULL AND IFNULL(kind,'real') = 'real'"
        } else {
            "deleted_at IS NULL AND IFNULL(is_archived, 0) = 0 AND IFNULL(kind,'real') = 'real'"
        }
        return db.watch(
            "SELECT * FROM accounts WHERE $where ORDER BY created_at",
            mapper = ::accountMapper,
        )
    }

    /** Single account by id (reactive) -- matches accounts/[id]/edit/page.tsx's
     * useQuery(single row, WHERE id = ?). Added 2026-08-05 for the Accounts
     * edit screen (docs/mobile/screen-specs/accounts.md); nothing needed a
     * single-account read before this. */
    fun watchAccount(id: String): Flow<Account?> = db.watch(
        "SELECT * FROM accounts WHERE id = ? AND deleted_at IS NULL",
        parameters = listOf(id),
        mapper = ::accountMapper,
    ).map { it.firstOrNull() }

    /** Minimal ledger-entry projection for balance derivation -- matches
     * hooks.ts's useAccountBalances query exactly (5 columns, all non-deleted
     * transactions, no account filter -- deriveBalance itself filters by
     * accountId as it folds). */
    fun watchLedgerEntries(): Flow<List<LedgerEntry>> = db.watch(
        "SELECT type, account_id, amount, to_account_id, to_amount FROM transactions WHERE deleted_at IS NULL",
        mapper = ::ledgerEntryMapper,
    )

    /** Full transaction rows for one account, newest first (for a ledger/list UI). */
    fun watchTransactionsForAccount(accountId: String): Flow<List<TransactionRow>> = db.watch(
        "SELECT * FROM transactions WHERE deleted_at IS NULL AND account_id = ? ORDER BY occurred_at DESC",
        parameters = listOf(accountId),
        mapper = ::transactionMapper,
    )

    /** All transaction rows across all accounts, newest first (for Dashboard). */
    fun watchRecentTransactions(limit: Int = 10): Flow<List<TransactionRow>> = db.watch(
        "SELECT * FROM transactions WHERE deleted_at IS NULL ORDER BY occurred_at DESC LIMIT ?",
        parameters = listOf(limit),
        mapper = ::transactionMapper,
    )

    /** All transaction rows across all accounts (for Transactions list). */
    fun watchAllTransactions(): Flow<List<TransactionRow>> = db.watch(
        "SELECT * FROM transactions WHERE deleted_at IS NULL ORDER BY occurred_at DESC",
        mapper = ::transactionMapper,
    )

    /**
     * Transactions inside a date range, for the Statements screen.
     *
     * Matches statements/page.tsx's query exactly, including two details that
     * are easy to lose:
     *
     * - **`type != 'opening_balance'`.** An opening balance is a bookkeeping
     *   entry, not something the user did. Including it would put a phantom
     *   line on the statement and inflate the income total.
     * - **`>= start AND < end`**, with `end` already advanced one day by the
     *   caller. A `BETWEEN` on ISO timestamps would silently drop everything
     *   that happened after midnight on the last day.
     */
    fun watchTransactionsInRange(startIso: String, endIso: String): Flow<List<TransactionRow>> = db.watch(
        """
            SELECT * FROM transactions
             WHERE deleted_at IS NULL AND type != 'opening_balance'
               AND occurred_at >= ? AND occurred_at < ?
             ORDER BY occurred_at
        """.trimIndent(),
        parameters = listOf(startIso, endIso),
        mapper = ::transactionMapper,
    )

    /** Income/expense totals grouped by month (all accounts, minor units) --
     * matches apps/web/app/page.tsx's NetWorthHero query exactly (same SQL,
     * same GROUP BY/ORDER BY), which the dashboard hero's sparkline + this-
     * month delta are computed from. */
    fun watchMonthlyIncomeExpense(): Flow<List<MonthlyIncomeExpense>> = db.watch(
        """SELECT strftime('%Y-%m', occurred_at) as ym, type, SUM(amount) as total
            FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense')
            GROUP BY ym, type ORDER BY ym""",
        mapper = { cursor ->
            MonthlyIncomeExpense(
                yearMonth = cursor.getString("ym"),
                type = cursor.getString("type"),
                total = cursor.getLong("total"),
            )
        },
    )

    /**
     * Expense totals grouped by CATEGORY, biggest first — web's ByCategoryTile.
     *
     * The `lend` exclusion is web's, and it matters: money you fronted for
     * someone is not your spending, and without this an evening you paid for
     * shows up as your biggest category. Every spending query on the dashboard
     * carries it.
     */
    fun watchExpenseByCategory(limit: Int = 8): Flow<List<NamedTotal>> = db.watch(
        """SELECT c.name AS name, SUM(t.amount) AS total
             FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
            WHERE t.deleted_at IS NULL AND t.type = 'expense'
              AND t.id NOT IN (
                    SELECT transaction_id FROM expense_postings
                     WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)
            GROUP BY t.category_id ORDER BY total DESC LIMIT ?""",
        parameters = listOf(limit),
        mapper = { cursor ->
            NamedTotal(
                // NULL means uncategorised. The view names that bucket, not the
                // repository -- a repository has no Resources and i18n belongs
                // where the string is rendered.
                name = cursor.getStringOptional("name"),
                total = cursor.getLong("total"),
            )
        },
    )

    /** Expense totals grouped by LABEL, biggest first — web's ByLabelTile. */
    fun watchExpenseByLabel(limit: Int = 8): Flow<List<NamedTotal>> = db.watch(
        """SELECT l.name AS name, SUM(t.amount) AS total
             FROM transaction_labels tl
             JOIN labels l ON l.id = tl.label_id
             JOIN transactions t ON t.id = tl.transaction_id
            WHERE t.deleted_at IS NULL AND t.type = 'expense'
              AND t.id NOT IN (
                    SELECT transaction_id FROM expense_postings
                     WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)
            GROUP BY l.id ORDER BY total DESC LIMIT ?""",
        parameters = listOf(limit),
        mapper = { cursor ->
            NamedTotal(name = cursor.getStringOptional("name"), total = cursor.getLong("total"))
        },
    )

    /**
     * Expense totals grouped by CATEGORY, **since [sinceIso]** — web's
     * SpendingTile.
     *
     * The by-category tile above has no date bound; this one does. Two methods
     * rather than one with a nullable date: the `lend` exclusion and the
     * grouping are identical, and a nullable parameter that changes the WHERE
     * clause is how a query quietly starts answering two questions.
     */
    fun watchExpenseByCategorySince(sinceIso: String): Flow<List<NamedTotal>> = db.watch(
        """SELECT c.name AS name, SUM(t.amount) AS total
             FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
            WHERE t.deleted_at IS NULL AND t.type = 'expense' AND t.occurred_at >= ?
              AND t.id NOT IN (
                    SELECT transaction_id FROM expense_postings
                     WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)
            GROUP BY t.category_id ORDER BY total DESC""",
        parameters = listOf(sinceIso),
        mapper = { cursor ->
            NamedTotal(name = cursor.getStringOptional("name"), total = cursor.getLong("total"))
        },
    )

    /**
     * Monthly income/expense totals **with web's `lend` exclusion** — the
     * series behind Cashflow, Net cashflow trend and This-month-vs-last.
     *
     * Web has TWO monthly queries and they differ: `NetWorthHero`'s has no
     * exclusion (that is `watchMonthlyIncomeExpense` above), `useCashflow`'s
     * does. Money you fronted for someone is not your expense, so a month in
     * which you paid for a group dinner would otherwise read as a spending
     * spike on the very charts meant to show your trend.
     */
    fun watchMonthlyCashflow(): Flow<List<MonthlyIncomeExpense>> = db.watch(
        """SELECT strftime('%Y-%m', occurred_at) as ym, type, SUM(amount) as total
             FROM transactions
            WHERE deleted_at IS NULL AND type IN ('income','expense')
              AND id NOT IN (
                    SELECT transaction_id FROM expense_postings
                     WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)
            GROUP BY ym, type ORDER BY ym""",
        mapper = { cursor ->
            MonthlyIncomeExpense(
                yearMonth = cursor.getString("ym"),
                type = cursor.getString("type"),
                total = cursor.getLong("total"),
            )
        },
    )

    /**
     * Daily expense totals since [sinceIso] — the raw material for `buildTrend`.
     *
     * Grouped by `date(occurred_at)`, which SQLite evaluates in UTC. Same
     * caveat as the monthly buckets, and the same reason for keeping it: web's
     * query is identical, and a native-only correction would make the two
     * disagree about which day a late-evening coffee belongs to.
     */
    fun watchDailyExpenseSince(sinceIso: String): Flow<Map<String, Long>> = db.watch(
        """SELECT date(occurred_at) as d, SUM(amount) as total
             FROM transactions
            WHERE deleted_at IS NULL AND type = 'expense' AND occurred_at >= ?
              AND id NOT IN (
                    SELECT transaction_id FROM expense_postings
                     WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)
            GROUP BY d ORDER BY d""",
        parameters = listOf(sinceIso),
        mapper = { cursor -> cursor.getString("d") to cursor.getLong("total") },
    ).map { pairs -> pairs.toMap() }

    /** All accounts with their ledger-derived balances (reactive). */
    fun watchAccountBalances(includeArchived: Boolean = false): Flow<List<AccountWithBalance>> =
        combine(watchAccounts(includeArchived), watchLedgerEntries()) { accounts, entries ->
            accounts.map { account ->
                AccountWithBalance(account, deriveBalance(account.id, account.currency, entries))
            }
        }

    /** Amount blocked per account toward goals, excluding the emergency fund
     * (which stays liquid). Matches hooks.ts's useBlockedByAccount exactly. */
    fun watchBlockedByAccount(): Flow<Map<String, Long>> = db.watch(
        """
        SELECT source_account_id, amount_blocked FROM goal_allocations
        WHERE deleted_at IS NULL
          AND goal_id NOT IN (SELECT id FROM goals WHERE is_emergency_fund = 1 AND deleted_at IS NULL)
        """.trimIndent(),
        mapper = { cursor ->
            cursor.getString("source_account_id") to cursor.getLong("amount_blocked")
        },
    ).map { rows ->
        val m = LinkedHashMap<String, Long>()
        for ((accountId, amount) in rows) m[accountId] = (m[accountId] ?: 0L) + amount
        m
    }

    /** Latest FX rate per currency pair (reactive), as a RateLookup for aggregateNetWorth.
     * RateLookup is a typealias for a plain function type ((String, String) -> Double),
     * not a `fun interface` -- so it's built as a lambda literal assigned to an
     * explicitly-typed val, not via a SAM-style `RateLookup { ... }` constructor call
     * (that syntax only works for actual functional interfaces). */
    fun watchRates(): Flow<RateLookup> = db.watch(
        "SELECT base_currency, quote_currency, rate, as_of FROM exchange_rates ORDER BY as_of DESC",
        mapper = { cursor ->
            Triple(cursor.getString("base_currency"), cursor.getString("quote_currency"), cursor.getDoubleOptional("rate") ?: 1.0)
        },
    ).map { rows ->
        val rateMap = LinkedHashMap<String, Double>()
        for ((base, quote, rate) in rows) {
            val key = "$base->$quote"
            if (!rateMap.containsKey(key)) rateMap[key] = rate // first = latest (query is ORDER BY as_of DESC)
        }
        val lookup: RateLookup = { from, to ->
            when {
                from == to -> 1.0
                rateMap.containsKey("$from->$to") -> rateMap.getValue("$from->$to")
                rateMap.containsKey("$to->$from") -> 1.0 / rateMap.getValue("$to->$from")
                else -> 1.0 // fallback: treat as par if no rate known yet
            }
        }
        lookup
    }

    /** Net worth in [base] currency, with and without blocked amounts (feature #13).
     * See the file-header note: this is intentionally ahead of the real web
     * spec's current netWorth() placeholder, not a divergence from settled
     * behavior. */
    fun watchNetWorth(base: String): Flow<NetWorth> =
        combine(watchAccountBalances(), watchBlockedByAccount(), watchRates()) { balances, blocked, rates ->
            val accountBalances: List<AccountBalance> = balances
                .filter { it.account.includeInNetWorth }
                .map { (account, balance) ->
                    AccountBalance(balance = balance, blocked = money(blocked[account.id] ?: 0L, account.currency))
                }
            NetWorth(
                total = aggregateNetWorth(accountBalances, base, rates, true),
                available = aggregateNetWorth(accountBalances, base, rates, false),
                base = base,
            )
        }

    /** All categories (reactive) -- matches transactions/new/page.tsx's
     * categories query. Added 2026-08-05 for the Transactions screens
     * (docs/mobile/screen-specs/transactions.md); nothing needed this read
     * before Transactions. */
    fun watchCategories(): Flow<List<CategoryRow>> = db.watch(
        "SELECT id, name, kind, parent_id FROM categories WHERE deleted_at IS NULL ORDER BY name",
        mapper = { cursor ->
            CategoryRow(
                id = cursor.getString("id"),
                name = cursor.getString("name"),
                kind = cursor.getString("kind"),
                parentId = cursor.getStringOptional("parent_id"),
            )
        },
    )

    /** All labels (reactive) -- matches transactions/new/page.tsx's labels
     * query. Added 2026-08-05 for the Transactions screens. */
    fun watchLabels(): Flow<List<LabelRow>> = db.watch(
        "SELECT id, name, color FROM labels WHERE deleted_at IS NULL ORDER BY name",
        mapper = { cursor ->
            LabelRow(
                id = cursor.getString("id"),
                name = cursor.getString("name"),
                color = cursor.getStringOptional("color"),
            )
        },
    )

    /** Every (account_type, payment_method) pairing, unfiltered -- matches
     * transactions/new/page.tsx's payMethodMap query. Callers filter to the
     * selected account's type client-side (small, static-ish lookup table --
     * not worth a parameterized watch per account-type change). Added
     * 2026-08-05 for the Transactions screens. */
    fun watchPaymentMethods(): Flow<List<PaymentMethodRow>> = db.watch(
        """SELECT pm.id, pm.label, m.account_type_id
            FROM account_type_payment_methods m JOIN payment_methods pm ON pm.id = m.payment_method_id
            ORDER BY pm.sort""",
        mapper = { cursor ->
            PaymentMethodRow(
                id = cursor.getString("id"),
                label = cursor.getString("label"),
                accountTypeId = cursor.getString("account_type_id"),
            )
        },
    )

    /** transaction_id -> ordered label names (reactive) -- used by the
     * Transactions list (tag row) and Edit (seeding the label picker).
     * Matches the list query's `GROUP_CONCAT(l.name)` but grouped in Kotlin
     * instead of SQL, so the same flat join also works for the Edit screen's
     * single-transaction lookup without a second query shape. Added
     * 2026-08-05 for the Transactions screens. */
    fun watchTransactionLabelNames(): Flow<Map<String, List<String>>> = db.watch(
        """SELECT tl.transaction_id, l.name FROM transaction_labels tl
            JOIN labels l ON l.id = tl.label_id ORDER BY l.name""",
        mapper = { cursor ->
            cursor.getString("transaction_id") to cursor.getString("name")
        },
    ).map { rows ->
        val m = LinkedHashMap<String, MutableList<String>>()
        for ((txnId, name) in rows) m.getOrPut(txnId) { mutableListOf() }.add(name)
        m
    }

    // ---- reads (one-shot, spec-matching) ----

    /** Ledger-derived balance of a single account. Scoped by
     * (account_id = ? OR to_account_id = ?), matching
     * PowerSyncBalanceRepository.accountBalance() exactly (more efficient
     * than folding over the whole ledger for a single-account lookup). */
    suspend fun accountBalance(accountId: String): Money {
        val currency = db.getOptional(
            sql = "SELECT currency FROM accounts WHERE id = ?",
            parameters = listOf(accountId),
            mapper = { cursor -> cursor.getString("currency") },
        ) ?: error("Account $accountId not found")
        val entries = db.getAll(
            sql = """SELECT type, account_id, amount, to_account_id, to_amount FROM transactions
                WHERE deleted_at IS NULL AND (account_id = ? OR to_account_id = ?)""",
            parameters = listOf(accountId, accountId),
            mapper = ::ledgerEntryMapper,
        )
        return deriveBalance(accountId, currency, entries)
    }

    // ---- writes: accounts ----

    /** Create a real account. Matches PowerSyncAccountRepository.create()'s
     * exact INSERT column list (id,user_id,name,type,currency,icon,color,
     * is_archived,allow_negative,created_at,updated_at) -- notably it does
     * NOT write include_in_net_worth or kind at creation time; those stay
     * NULL and fall back to their IFNULL read-side defaults (true / "real")
     * until explicitly set via update(). [allowNegative] defaults to true
     * for credit_card accounts (liabilities that carry a negative/owed
     * balance) and false otherwise, unless the caller passes an explicit
     * value -- matches `row.allow_negative ?? row.type === "credit_card"`. */
    suspend fun createAccount(
        userId: String,
        name: String,
        type: String,
        currency: String,
        icon: String? = null,
        color: String? = null,
        allowNegative: Boolean? = null,
        isArchived: Boolean = false,
    ): String {
        val id = newId()
        val ts = nowIso()
        val allowNeg = allowNegative ?: (type == "credit_card")
        db.execute(
            sql = """INSERT INTO accounts (id,user_id,name,type,currency,icon,color,is_archived,allow_negative,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
            parameters = listOf(id, userId, name, type, currency, icon, color, if (isArchived) 1L else 0L, if (allowNeg) 1L else 0L, ts, ts),
        )
        return id
    }

    /** Set/adjust the opening balance by appending a ledger entry -- never
     * rewrites history. First call on an account writes an "opening_balance"
     * entry; subsequent calls write "adjustment" entries. Matches
     * PowerSyncAccountRepository.setOpeningBalance() exactly. */
    suspend fun setOpeningBalance(userId: String, accountId: String, balance: Money, occurredAt: String) {
        val currency = db.getOptional(
            sql = "SELECT currency FROM accounts WHERE id = ?",
            parameters = listOf(accountId),
            mapper = { cursor -> cursor.getString("currency") },
        ) ?: error("Account $accountId not found")
        require(currency == balance.currency) { "Opening balance currency must match account currency" }
        val existingCount = db.get(
            sql = "SELECT COUNT(*) as c FROM transactions WHERE account_id = ? AND type = 'opening_balance'",
            parameters = listOf(accountId),
            mapper = { cursor -> cursor.getLong("c") },
        )
        val type = if (existingCount > 0) "adjustment" else "opening_balance"
        val ts = nowIso()
        db.execute(
            sql = """INSERT INTO transactions (id,user_id,account_id,type,amount,currency,occurred_at,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?)""",
            parameters = listOf(newId(), userId, accountId, type, balance.amount, balance.currency, occurredAt, ts, ts),
        )
    }

    suspend fun updateAccount(id: String, values: Map<String, Any?>) = updateRow(db, "accounts", id, values)

    suspend fun setAccountArchived(id: String, archived: Boolean) =
        updateRow(db, "accounts", id, mapOf("is_archived" to if (archived) 1L else 0L))

    suspend fun deleteAccount(id: String) = softDelete(db, "accounts", id)

    /** Soft-delete every non-deleted transaction on [accountId] -- matches
     * accounts/[id]/edit/page.tsx's "Delete everything" cascade path exactly
     * (raw UPDATE, transactions first, then the account is soft-deleted
     * separately by the caller via deleteAccount()). Added 2026-08-05 for the
     * Accounts edit screen's delete-confirm modal (docs/mobile/screen-specs/
     * accounts.md) -- web's "keep transactions" path is just deleteAccount()
     * alone, no separate method needed for that one. */
    suspend fun cascadeDeleteAccountTransactions(accountId: String) {
        val ts = nowIso()
        db.execute(
            sql = "UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE account_id = ? AND deleted_at IS NULL",
            parameters = listOf(ts, ts, accountId),
        )
    }

    // ---- writes: transactions ----

    /** Throw [OverdraftError] if applying [deltaMinor] to [accountId] would
     * take a no-overdraft account below zero. [excludeTxnId] omits a
     * transaction from the current balance (used on edits, so the row's own
     * prior effect isn't counted). Matches assertNoOverdraft() exactly. */
    private suspend fun assertNoOverdraft(accountId: String, deltaMinor: Long, excludeTxnId: String?) {
        if (deltaMinor >= 0) return
        val acct = db.getOptional(
            sql = "SELECT name, currency, IFNULL(allow_negative, 0) AS allow_negative FROM accounts WHERE id = ?",
            parameters = listOf(accountId),
            mapper = { cursor ->
                Triple(cursor.getString("name"), cursor.getString("currency"), cursor.getBooleanOptional("allow_negative") ?: false)
            },
        ) ?: return // unknown account
        val (name, currency, allowNegative) = acct
        if (allowNegative) return
        val sql = if (excludeTxnId != null) {
            """SELECT type, account_id, amount, to_account_id, to_amount FROM transactions
                WHERE deleted_at IS NULL AND (account_id = ? OR to_account_id = ?) AND id != ?"""
        } else {
            """SELECT type, account_id, amount, to_account_id, to_amount FROM transactions
                WHERE deleted_at IS NULL AND (account_id = ? OR to_account_id = ?)"""
        }
        val params = if (excludeTxnId != null) listOf(accountId, accountId, excludeTxnId) else listOf(accountId, accountId)
        val entries = db.getAll(sql = sql, parameters = params, mapper = ::ledgerEntryMapper)
        val projected = deriveBalance(accountId, currency, entries).amount + deltaMinor
        if (projected < 0) throw OverdraftError(name, money(projected, currency))
    }

    /** Create a transaction (+ optional breakdown items, + optional labels)
     * atomically. Rejects if items don't reconcile to the total. Overdraft-
     * checked for expenses and the source side of transfers. Matches
     * PowerSyncTransactionRepository.create() exactly, including the
     * transfer_group_id/fx_rate derivation. [toAccountId]/[toAmount] are for
     * transfers only; [toAmount] defaults to null (same-currency 1:1 is the
     * caller's responsibility to pass explicitly, matching the real spec --
     * it does NOT default to-amount to amount the way this repo's old
     * createTransfer() used to). */
    suspend fun createTransaction(
        userId: String,
        accountId: String,
        type: String,
        amount: Money,
        occurredAt: String,
        categoryId: String? = null,
        labels: List<String>? = null,
        note: String? = null,
        description: String? = null,
        paymentMethod: String? = null,
        items: List<TransactionItemInput>? = null,
        toAccountId: String? = null,
        toAmount: Money? = null,
    ): TransactionRow {
        val itemList = items ?: emptyList()
        if (itemList.isNotEmpty() && !itemsReconcile(amount, itemList.map { it.amount })) {
            error("Breakdown items must sum exactly to the transaction amount")
        }
        if (type == "transfer" && toAccountId == null) {
            error("Transfer requires a destination account")
        }
        if (type == "expense" || type == "transfer") {
            assertNoOverdraft(accountId, -amount.amount, null)
        }

        val id = newId()
        val ts = nowIso()
        val transferGroup = if (type == "transfer") newId() else null
        val fxRate = if (toAmount != null && amount.amount != 0L) toAmount.amount.toDouble() / amount.amount else null

        db.writeTransaction { tx ->
            tx.execute(
                sql = """INSERT INTO transactions
                    (id,user_id,account_id,type,amount,currency,category_id,note,description,payment_method,occurred_at,
                     transfer_group_id,to_account_id,to_amount,fx_rate,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                parameters = listOf(
                    id, userId, accountId, type, amount.amount, amount.currency,
                    categoryId, note, description, paymentMethod, occurredAt, transferGroup,
                    toAccountId, toAmount?.amount, fxRate, ts, ts,
                ),
            )
            for (item in itemList) {
                tx.execute(
                    sql = """INSERT INTO transaction_items (id,user_id,transaction_id,description,amount,created_at,updated_at)
                        VALUES (?,?,?,?,?,?,?)""",
                    parameters = listOf(newId(), userId, id, item.description, item.amount.amount, ts, ts),
                )
            }
            // Label resolution inlined here (and in updateTransaction) rather
            // than shared -- see file header note on the tx-type risk.
            if (!labels.isNullOrEmpty()) {
                tx.execute("DELETE FROM transaction_labels WHERE transaction_id = ?", listOf(id))
                val seen = mutableSetOf<String>()
                for (raw in labels) {
                    val name = raw.trim()
                    val lower = name.lowercase()
                    if (name.isEmpty() || lower in seen) continue
                    seen += lower
                    var labelId = tx.getOptional(
                        sql = "SELECT id FROM labels WHERE user_id = ? AND name = ? AND deleted_at IS NULL",
                        parameters = listOf(userId, name),
                        mapper = { cursor -> cursor.getString("id") },
                    )
                    if (labelId == null) {
                        labelId = newId()
                        tx.execute(
                            "INSERT INTO labels (id,user_id,name,color,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                            listOf(labelId, userId, name, null, ts, ts),
                        )
                    }
                    tx.execute(
                        "INSERT INTO transaction_labels (id,user_id,transaction_id,label_id,created_at) VALUES (?,?,?,?,?)",
                        listOf(newId(), userId, id, labelId, ts),
                    )
                }
            }
        }

        return TransactionRow(
            id = id, accountId = accountId, type = type, amount = amount.amount, currency = amount.currency,
            categoryId = categoryId, note = note, description = description, paymentMethod = paymentMethod,
            occurredAt = occurredAt, transferGroupId = transferGroup, toAccountId = toAccountId,
            toAmount = toAmount?.amount, fxRate = fxRate,
        )
    }

    suspend fun listByAccount(accountId: String, limit: Int = 50): List<TransactionRow> = db.getAll(
        sql = "SELECT * FROM transactions WHERE account_id = ? AND deleted_at IS NULL ORDER BY occurred_at DESC LIMIT ?",
        parameters = listOf(accountId, limit),
        mapper = ::transactionMapper,
    )

    suspend fun items(transactionId: String): List<TransactionItem> = db.getAll(
        sql = "SELECT * FROM transaction_items WHERE transaction_id = ? AND deleted_at IS NULL",
        parameters = listOf(transactionId),
        mapper = ::itemMapper,
    )

    suspend fun search(query: String, limit: Int = 50): List<TransactionRow> {
        val like = "%$query%"
        return db.getAll(
            sql = """SELECT t.* FROM transactions t
                WHERE t.deleted_at IS NULL AND (
                  t.note LIKE ? OR t.description LIKE ?
                  OR EXISTS (
                    SELECT 1 FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id
                    WHERE tl.transaction_id = t.id AND l.name LIKE ?
                  )
                )
                ORDER BY t.occurred_at DESC LIMIT ?""",
            parameters = listOf(like, like, like, limit),
            mapper = ::transactionMapper,
        )
    }

    /** Edit a transaction and append an audit record of what changed.
     * [patch]'s KEY PRESENCE (not just non-null value) decides whether a
     * field is touched -- a missing key means "don't touch"; a present key
     * with a null value means "set this nullable column to null". This
     * mirrors the real EditTransactionInput's undefined-vs-null distinction,
     * which a plain nullable Kotlin parameter can't represent by itself, and
     * is consistent with this codebase's existing updateRow()/updateAccount()
     * Map<String,Any?> convention. Recognized keys: "type" (String),
     * "account_id" (String), "amount" (Long, minor units), "category_id"
     * (String?), "note" (String?), "description" (String?),
     * "payment_method" (String?), "occurred_at" (String), "to_account_id"
     * (String?), "to_amount" (Long?), "items" (List<TransactionItemInput>?
     * -- absent = don't touch; present null/empty = clear; present non-empty
     * = replace with fresh rows), "labels" (List<String>? -- null/absent =
     * don't touch; non-null (even empty) = replace). [userId] is required
     * for any new item/label/audit rows this call writes (TransactionRow
     * doesn't carry user_id, unlike the real repo's `before.user_id`, so
     * this facade takes it as an explicit parameter -- mirrors
     * LedgerRepository.swift's updateTransaction(userId:id:patch:) exactly). */
    suspend fun updateTransaction(userId: String, id: String, patch: Map<String, Any?>) {
        val before = db.getOptional(
            sql = "SELECT * FROM transactions WHERE id = ?",
            parameters = listOf(id),
            mapper = ::transactionMapper,
        ) ?: error("Transaction $id not found")

        val changes = LinkedHashMap<String, Pair<Any?, Any?>>()
        val sets = mutableListOf<String>()
        val params = mutableListOf<Any?>()
        fun track(col: String, from: Any?, key: String) {
            if (!patch.containsKey(key)) return
            val to = patch[key]
            if (to != from) {
                changes[col] = from to to
                sets += "$col = ?"
                params += to
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

        val touchItems = patch.containsKey("items")
        @Suppress("UNCHECKED_CAST")
        val itemsVal = patch["items"] as? List<TransactionItemInput>
        @Suppress("UNCHECKED_CAST")
        val labelsVal = patch["labels"] as? List<String>
        val relabel = labelsVal != null
        if (sets.isEmpty() && !touchItems && !relabel) return

        val newType = (patch["type"] as? String) ?: before.type
        val newAccount = (patch["account_id"] as? String) ?: before.accountId
        val newAmount = (patch["amount"] as? Long) ?: before.amount
        if (newType == "expense" || newType == "transfer") {
            assertNoOverdraft(newAccount, -newAmount, id)
        }

        val ts = nowIso()

        db.writeTransaction { tx ->
            if (changes.containsKey("amount") && !touchItems) {
                tx.execute(
                    "UPDATE transaction_items SET deleted_at = ?, updated_at = ? WHERE transaction_id = ? AND deleted_at IS NULL",
                    listOf(ts, ts, id),
                )
            }
            if (touchItems) {
                tx.execute(
                    "UPDATE transaction_items SET deleted_at = ?, updated_at = ? WHERE transaction_id = ? AND deleted_at IS NULL",
                    listOf(ts, ts, id),
                )
                if (!itemsVal.isNullOrEmpty()) {
                    for (item in itemsVal) {
                        tx.execute(
                            """INSERT INTO transaction_items (id,user_id,transaction_id,description,amount,created_at,updated_at)
                                VALUES (?,?,?,?,?,?,?)""",
                            // Always a fresh id: the previous items were just
                            // soft-deleted (rows still exist), so reusing an
                            // incoming id would collide on the PRIMARY KEY.
                            listOf(newId(), userId, id, item.description, item.amount.amount, ts, ts),
                        )
                    }
                }
                changes["items"] = "(prev)" to (if (itemsVal.isNullOrEmpty()) "none" else "${itemsVal.size} items")
            }

            if (relabel) {
                tx.execute("DELETE FROM transaction_labels WHERE transaction_id = ?", listOf(id))
                val seen = mutableSetOf<String>()
                for (raw in labelsVal!!) {
                    val name = raw.trim()
                    val lower = name.lowercase()
                    if (name.isEmpty() || lower in seen) continue
                    seen += lower
                    var labelId = tx.getOptional(
                        sql = "SELECT id FROM labels WHERE user_id = ? AND name = ? AND deleted_at IS NULL",
                        parameters = listOf(userId, name),
                        mapper = { cursor -> cursor.getString("id") },
                    )
                    if (labelId == null) {
                        labelId = newId()
                        tx.execute(
                            "INSERT INTO labels (id,user_id,name,color,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                            listOf(labelId, userId, name, null, ts, ts),
                        )
                    }
                    tx.execute(
                        "INSERT INTO transaction_labels (id,user_id,transaction_id,label_id,created_at) VALUES (?,?,?,?,?)",
                        listOf(newId(), userId, id, labelId, ts),
                    )
                }
                changes["labels"] = "(prev)" to labelsVal.joinToString(", ")
            }
            if (sets.isNotEmpty()) {
                sets += "updated_at = ?"
                params += ts
                params += id
                tx.execute("UPDATE transactions SET ${sets.joinToString(", ")} WHERE id = ?", params)
            }
            tx.execute(
                "INSERT INTO transaction_audit (id,user_id,transaction_id,action,changes,created_at) VALUES (?,?,?,?,?,?)",
                listOf(newId(), userId, id, "update", changesToJson(changes), ts),
            )
        }
    }

    /** Soft-delete a transaction (and its items/labels), appending a delete
     * audit record. [userId] is needed for the audit row (see
     * updateTransaction's doc comment on why this facade can't derive it). */
    suspend fun removeTransaction(userId: String, id: String) {
        val exists = db.getOptional(
            sql = "SELECT id FROM transactions WHERE id = ?",
            parameters = listOf(id),
            mapper = { cursor -> cursor.getString("id") },
        ) ?: return
        val ts = nowIso()
        db.writeTransaction { tx ->
            tx.execute(
                "UPDATE transaction_items SET deleted_at = ?, updated_at = ? WHERE transaction_id = ? AND deleted_at IS NULL",
                listOf(ts, ts, id),
            )
            tx.execute("DELETE FROM transaction_labels WHERE transaction_id = ?", listOf(id))
            tx.execute("UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE id = ?", listOf(ts, ts, id))
            tx.execute(
                "INSERT INTO transaction_audit (id,user_id,transaction_id,action,changes,created_at) VALUES (?,?,?,?,?,?)",
                listOf(newId(), userId, id, "delete", "{\"deleted\":{\"from\":\"active\",\"to\":\"removed\"}}", ts),
            )
        }
    }

    suspend fun history(transactionId: String): List<TransactionAudit> = db.getAll(
        sql = "SELECT id, transaction_id, action, changes, created_at FROM transaction_audit WHERE transaction_id = ? ORDER BY created_at DESC",
        parameters = listOf(transactionId),
        mapper = ::auditMapper,
    )
}

/** Minimal, dependency-free JSON-object serializer for the audit `changes`
 * column -- values are always strings or null here (from/to pairs plus the
 * items/labels string summaries above), so a hand-rolled encoder avoids
 * pulling in a JSON library just for this one column. */
private fun changesToJson(changes: Map<String, Pair<Any?, Any?>>): String {
    fun encode(v: Any?): String = when (v) {
        null -> "null"
        is Number, is Boolean -> v.toString()
        else -> "\"${v.toString().replace("\\", "\\\\").replace("\"", "\\\"")}\""
    }
    val entries = changes.entries.joinToString(",") { (k, fromTo) ->
        "\"$k\":{\"from\":${encode(fromTo.first)},\"to\":${encode(fromTo.second)}}"
    }
    return "{$entries}"
}
