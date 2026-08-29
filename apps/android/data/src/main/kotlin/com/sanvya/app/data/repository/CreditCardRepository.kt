package com.sanvya.app.data.repository

/**
 * Credit-card details + bill settlement (P2.5). Mirrors
 * packages/data/src/powersync-repositories.ts's PowerSyncCreditCardRepository
 * exactly: getDetails/upsertDetails against credit_card_details; settle()
 * simply records a transfer transaction via LedgerRepository.createTransaction
 * (composition, matching the real repo's own
 * `private readonly transactions: PowerSyncTransactionRepository`
 * constructor dependency) -- it does not touch a real bill.
 *
 * Table columns confirmed against PocketCareSchema.kt's credit_card_details
 * entry and supabase/migrations/0001_init.sql + 0032_loans_investments_cards.sql
 * (which added pending_due/due_on). Extended 2026-08-06 (task #29,
 * Credit Cards) with watchAllDetails/cycleSpend/setCycleDetails --
 * pending_due/due_on are written via the latter, matching web's
 * `saveCycle()`, which updates them with a raw SQL statement separate
 * from upsertDetails.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import com.sanvya.app.domain.money.Money
import kotlinx.coroutines.flow.Flow

data class CreditCardDetails(
    val accountId: String,
    val statementDay: Int,
    val dueDay: Int,
    val creditLimit: Long?,
    val cardLast4: String?,
    /** The user's own typed "amount due this statement" -- set by the edit
     * form, not derived from transactions. Null until first configured. */
    val pendingDue: Long?,
    /** Due date (YYYY-MM-DD) for [pendingDue], recomputed from the cycle
     * whenever the details are saved. */
    val dueOn: String?,
)

/**
 * One charge behind a card's outstanding balance, for the "View transactions"
 * list. Deliberately a narrow row rather than a full `TransactionRow`: the
 * list shows a description, a date and an amount, and web's query
 * (`SELECT id, description, amount, occurred_at`) selects exactly those four.
 */
data class CardCharge(
    val id: String,
    val description: String?,
    val amount: Long,
    val occurredAt: String,
)

/** Web caps the charges list at 200 rows (`LIMIT 200` in cards/page.tsx); the
 * running total is the total of what is listed, so the cap has to match or the
 * two clients would print different totals for the same card. */
const val CARD_CHARGES_LIMIT = 200

class CreditCardRepository(
    private val db: PowerSyncDatabase,
    private val transactions: LedgerRepository,
) {
    private fun detailsMapper(cursor: com.powersync.db.SqlCursor) = CreditCardDetails(
        accountId = cursor.getString("account_id"),
        statementDay = (cursor.getLongOptional("statement_day") ?: 0L).toInt(),
        dueDay = (cursor.getLongOptional("due_day") ?: 0L).toInt(),
        creditLimit = cursor.getLongOptional("credit_limit"),
        cardLast4 = cursor.getStringOptional("card_last4"),
        pendingDue = cursor.getLongOptional("pending_due"),
        dueOn = cursor.getStringOptional("due_on"),
    )

    suspend fun getDetails(accountId: String): CreditCardDetails? = db.getOptional(
        sql = "SELECT account_id, statement_day, due_day, credit_limit, card_last4, pending_due, due_on FROM credit_card_details WHERE account_id = ?",
        parameters = listOf(accountId),
        mapper = ::detailsMapper,
    )

    /** Live version of [getDetails] for every card at once -- reacts to
     * edits from any screen/device, matches web's `useQuery` over the
     * whole table (not per-card). */
    fun watchAllDetails(): Flow<List<CreditCardDetails>> = db.watch(
        sql = "SELECT account_id, statement_day, due_day, credit_limit, card_last4, pending_due, due_on FROM credit_card_details",
        parameters = emptyList(),
        mapper = ::detailsMapper,
    )

    /**
     * New spend posted to this card SINCE [cycleStartIso] -- an EMI charged
     * to the card, a purchase, anything. Deliberately separate from
     * `pending_due` (the statement amount the user typed): a charge made
     * today lands on the NEXT statement on a real card, so folding it into
     * "due this cycle" would overstate what's actually payable by the due
     * date.
     *
     * One-shot, not a live `db.watch()`: web's `useQuery` is reactive per
     * render, but a per-card dynamic Flow-of-Flows combine is a lot of
     * ceremony for this one number. Recomputed by the ViewModel every time
     * `watchAccountBalances()` re-emits, which itself fires on every new
     * transaction against the account -- the realistic "I just spent on
     * this card" case is already covered; same simplification already
     * documented for Budgets' per-item spend (see AUDIT_HISTORY.md's
     * 2026-08-06 Goals/Budgets list-staleness entry).
     */
    suspend fun cycleSpend(accountId: String, cycleStartIso: String): Long {
        val row = db.getOptional(
            sql = """SELECT COALESCE(SUM(amount), 0) AS total FROM transactions
                     WHERE account_id = ? AND deleted_at IS NULL AND type = 'expense' AND occurred_at >= ?""",
            parameters = listOf(accountId, cycleStartIso),
            mapper = { cursor -> cursor.getLongOptional("total") ?: 0L },
        )
        return row ?: 0L
    }

    /** Writes the user's typed statement amount + its due date directly --
     * `pending_due`/`due_on` aren't part of [upsertDetails]'s field set
     * (matches web's `saveCycle()`, which updates them via a separate raw
     * SQL statement after `upsertDetails`). */
    suspend fun setCycleDetails(accountId: String, pendingDue: Long?, dueOnIso: String?) {
        db.execute(
            sql = "UPDATE credit_card_details SET pending_due = ?, due_on = ?, updated_at = ? WHERE account_id = ?",
            parameters = listOf(pendingDue, dueOnIso, nowIso(), accountId),
        )
    }

    suspend fun upsertDetails(userId: String, details: CreditCardDetails) {
        val ts = nowIso()
        val existing = getDetails(details.accountId)
        if (existing != null) {
            db.execute(
                sql = "UPDATE credit_card_details SET statement_day = ?, due_day = ?, credit_limit = ?, card_last4 = ?, updated_at = ? WHERE account_id = ?",
                parameters = listOf(details.statementDay.toLong(), details.dueDay.toLong(), details.creditLimit, details.cardLast4, ts, details.accountId),
            )
        } else {
            db.execute(
                sql = """INSERT INTO credit_card_details (id,user_id,account_id,statement_day,due_day,credit_limit,card_last4,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?)""",
                parameters = listOf(newId(), userId, details.accountId, details.statementDay.toLong(), details.dueDay.toLong(), details.creditLimit, details.cardLast4, ts, ts),
            )
        }
    }

    /**
     * The charges that add up to this card's outstanding balance, newest
     * first -- web's second `useQuery` in `CardPanel`.
     *
     * `type = 'expense'` only, matching web: a settlement is a TRANSFER, and
     * listing it here would show a payment as though it were another charge.
     *
     * One-shot rather than a live `db.watch()` for the same reason
     * [cycleSpend] is: it is read when the user opens the list, and the list
     * is a modal over a screen that is itself rebuilt whenever a transaction
     * against the account changes.
     */
    suspend fun charges(accountId: String, limit: Int = CARD_CHARGES_LIMIT): List<CardCharge> = db.getAll(
        sql = """SELECT id, description, amount, occurred_at FROM transactions
                 WHERE account_id = ? AND deleted_at IS NULL AND type = 'expense'
                 ORDER BY occurred_at DESC LIMIT ?""",
        parameters = listOf(accountId, limit),
        mapper = { cursor ->
            CardCharge(
                id = cursor.getString("id"),
                description = cursor.getStringOptional("description"),
                amount = cursor.getLongOptional("amount") ?: 0L,
                occurredAt = cursor.getString("occurred_at"),
            )
        },
    )

    /**
     * How many charges [charges] would return, so the screen can hide the
     * "View transactions" control when there are none -- web's
     * `cardTxns.length > 0` guard. Counting is far cheaper than fetching 200
     * rows per card on every rebuild.
     */
    suspend fun chargeCount(accountId: String, limit: Int = CARD_CHARGES_LIMIT): Int {
        val row = db.getOptional(
            sql = """SELECT COUNT(*) AS n FROM (
                       SELECT id FROM transactions
                       WHERE account_id = ? AND deleted_at IS NULL AND type = 'expense'
                       LIMIT ?
                     )""",
            parameters = listOf(accountId, limit),
            mapper = { cursor -> cursor.getLongOptional("n") ?: 0L },
        )
        return (row ?: 0L).toInt()
    }

    /** Settle the bill = record a transfer from the chosen account to the card. */
    suspend fun settle(userId: String, fromAccountId: String, cardAccountId: String, amount: Money, toAmount: Money? = null, occurredAt: String) {
        transactions.createTransaction(
            userId = userId,
            accountId = fromAccountId,
            type = "transfer",
            amount = amount,
            occurredAt = occurredAt,
            note = "Credit card settlement",
            toAccountId = cardAccountId,
            toAmount = toAmount,
        )
    }
}
