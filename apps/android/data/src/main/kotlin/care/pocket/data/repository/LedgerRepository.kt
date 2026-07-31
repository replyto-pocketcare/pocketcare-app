package care.pocket.data.repository

/**
 * Read/write facade over the local PowerSync SQLite DB for accounts and
 * transactions (P2.5). Mirrors apps/web/src/hooks.ts's useAccountBalances/
 * useNetWorth/useRates exactly: query raw rows, then call the already-ported
 * pure domain functions (deriveBalance, aggregateNetWorth -- money+ledger
 * domain, P1.1/P1.2) for any derived value, rather than recomputing balance
 * logic here. Reactive via PowerSync's watch(), which mirrors useQuery's
 * "re-run on table change" semantics on the web.
 *
 * Table columns confirmed against the generated schema descriptor
 * (PocketCareSchema.kt, P2.1) rather than assumed.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.getBooleanOptional
import com.powersync.db.getDoubleOptional
import com.powersync.db.getLong
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import care.pocket.domain.ledger.AccountBalance
import care.pocket.domain.ledger.LedgerEntry
import care.pocket.domain.ledger.RateLookup
import care.pocket.domain.ledger.aggregateNetWorth
import care.pocket.domain.ledger.deriveBalance
import care.pocket.domain.money.Money
import care.pocket.domain.money.money
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
)

data class AccountWithBalance(val account: Account, val balance: Money)

data class NetWorth(val total: Money, val available: Money, val base: String)

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
)

private fun ledgerEntryMapper(cursor: com.powersync.db.SqlCursor): LedgerEntry = LedgerEntry(
    type = cursor.getString("type"),
    accountId = cursor.getString("account_id"),
    amount = cursor.getLong("amount"),
    toAccountId = cursor.getStringOptional("to_account_id"),
    toAmount = cursor.getLongOptional("to_amount"),
)

class LedgerRepository(private val db: PowerSyncDatabase) {

    // ---- reads ----

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

    /** Net worth in [base] currency, with and without blocked amounts (feature #13). */
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

    // ---- writes ----

    /** Create a real account. [kind] defaults to "real" (as opposed to a
     * virtual split account, which this repository does not create --
     * that's owned by the splits domain, P2.5's later slice). */
    suspend fun createAccount(
        userId: String,
        name: String,
        type: String,
        currency: String,
        icon: String? = null,
        color: String? = null,
        includeInNetWorth: Boolean = true,
        allowNegative: Boolean = false,
    ): String = insertRow(
        db, "accounts", userId,
        mapOf(
            "name" to name,
            "type" to type,
            "currency" to currency,
            "icon" to icon,
            "color" to color,
            // Bound as Long (0/1), not Boolean: these are INTEGER columns and
            // the SQLite bind layer's Boolean support isn't independently
            // confirmed from this sandbox (no real driver source checked for
            // this specific path) -- Long is unambiguously safe.
            "is_archived" to 0L,
            "include_in_net_worth" to if (includeInNetWorth) 1L else 0L,
            "allow_negative" to if (allowNegative) 1L else 0L,
            "kind" to "real",
        ),
    )

    suspend fun updateAccount(id: String, values: Map<String, Any?>) = updateRow(db, "accounts", id, values)

    suspend fun setAccountArchived(id: String, archived: Boolean) =
        updateRow(db, "accounts", id, mapOf("is_archived" to if (archived) 1L else 0L))

    suspend fun deleteAccount(id: String) = softDelete(db, "accounts", id)

    /** Create a non-transfer transaction (income/expense/opening_balance/adjustment). */
    suspend fun createTransaction(
        userId: String,
        accountId: String,
        type: String,
        amount: Long,
        currency: String,
        occurredAt: String,
        categoryId: String? = null,
        note: String? = null,
        description: String? = null,
        paymentMethod: String? = null,
    ): String = insertRow(
        db, "transactions", userId,
        mapOf(
            "account_id" to accountId,
            "type" to type,
            "amount" to amount,
            "currency" to currency,
            "category_id" to categoryId,
            "note" to note,
            "description" to description,
            "payment_method" to paymentMethod,
            "occurred_at" to occurredAt,
        ),
    )

    /** Create a transfer (single row: source account_id/amount, destination
     * to_account_id/to_amount -- matches Ledger.kt's signedEffectFor, which
     * reads both sides off one row, not two linked rows). [toAmount] defaults
     * to [amount] for a same-currency transfer. */
    suspend fun createTransfer(
        userId: String,
        fromAccountId: String,
        toAccountId: String,
        amount: Long,
        currency: String,
        occurredAt: String,
        toAmount: Long? = null,
        fxRate: Double? = null,
        note: String? = null,
    ): String = insertRow(
        db, "transactions", userId,
        mapOf(
            "account_id" to fromAccountId,
            "type" to "transfer",
            "amount" to amount,
            "currency" to currency,
            "to_account_id" to toAccountId,
            "to_amount" to (toAmount ?: amount),
            "fx_rate" to fxRate,
            "transfer_group_id" to newId(),
            "occurred_at" to occurredAt,
            "note" to note,
        ),
    )

    suspend fun updateTransaction(id: String, values: Map<String, Any?>) = updateRow(db, "transactions", id, values)

    suspend fun deleteTransaction(id: String) = softDelete(db, "transactions", id)
}
