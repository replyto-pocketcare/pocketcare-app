package care.pocket.data.repository

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
 * entry and supabase/migrations/0001_init.sql +
 * 0032_loans_investments_cards.sql (which added pending_due/due_on --
 * unused by this repository, matching the real spec's column subset).
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import care.pocket.domain.money.Money

data class CreditCardDetails(
    val accountId: String,
    val statementDay: Int,
    val dueDay: Int,
    val creditLimit: Long?,
    val cardLast4: String?,
)

class CreditCardRepository(
    private val db: PowerSyncDatabase,
    private val transactions: LedgerRepository,
) {
    suspend fun getDetails(accountId: String): CreditCardDetails? = db.getOptional(
        sql = "SELECT account_id, statement_day, due_day, credit_limit, card_last4 FROM credit_card_details WHERE account_id = ?",
        parameters = listOf(accountId),
        mapper = { cursor ->
            CreditCardDetails(
                accountId = cursor.getString("account_id"),
                statementDay = (cursor.getLongOptional("statement_day") ?: 0L).toInt(),
                dueDay = (cursor.getLongOptional("due_day") ?: 0L).toInt(),
                creditLimit = cursor.getLongOptional("credit_limit"),
                cardLast4 = cursor.getStringOptional("card_last4"),
            )
        },
    )

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
