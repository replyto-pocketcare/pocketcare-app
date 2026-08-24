package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
// Extension-function cursor accessors -- imported by name, as everywhere else.
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import com.sanvya.app.domain.finance.effectivePaidEmis
import com.sanvya.app.domain.finance.emiDueDate
import com.sanvya.app.domain.finance.emiDescription
import com.sanvya.app.domain.money.money
import kotlinx.coroutines.sync.Mutex
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.doubleOrNull

/**
 * Charge due EMIs to the account they are linked to — the port of
 * apps/web/src/loans/autoPost.ts.
 *
 * A loan can name the account its EMI is charged to, usually a credit card
 * (`loans.funding_account_id`). When an EMI's due date passes, this posts it as
 * an expense on that account, exactly as a bank adds the instalment to your
 * statement. That is what makes the EMI appear in the card's total due.
 *
 * ## CHARGED and PAID are different, and this only does the first
 *
 * - **charged** — the instalment is on the card. This file, on the due date.
 * - **paid** — you settled it. That happens when the card bill is settled, or
 *   by hand in the EMI dialog.
 *
 * `auto_mark_paid` therefore does **not** gate this. An EMI is owed whether or
 * not you have told the app you paid it. (Web's own comment is emphatic about
 * this; it used to be gated and was deliberately un-gated.)
 *
 * ## Never post an EMI twice
 *
 * - Dedupe is a lookup in the **synced ledger** for a transaction with exactly
 *   [emiDescription]'s output on that account — not a local flag — so a second
 *   device running the same catch-up finds the first device's row and skips.
 *   That is why `emiDescription` is a shared function and not a literal.
 * - A [Mutex] stops two concurrent runs inside one process.
 * - Only EMIs whose due date has actually passed are considered, and each is
 *   posted **at its own due date** so it lands in the right billing cycle.
 * - Manually-marked EMIs are skipped: that dialog already made the posting
 *   decision (the user picked an account there, or chose not to record).
 */
class LoanAutoPostRepository(
    private val db: PowerSyncDatabase,
    private val ledger: LedgerRepository,
) {
    private companion object {
        /** Catching up more than a year of missed EMIs at once is a bug, not a feature. */
        const val MAX_PER_LOAN = 12

        val json = Json { ignoreUnknownKeys = true }
    }

    /**
     * A coroutine Mutex, where web uses a module-level `let running = false`.
     *
     * Web's flag works because the browser is single-threaded and the check and
     * set cannot interleave. On Android two coroutines on different dispatchers
     * genuinely can, and the failure mode is the one thing this file exists to
     * prevent: two runs racing past the same dedupe lookup before either has
     * written its row.
     */
    private val running = Mutex()

    private data class LoanRow(
        val id: String,
        val lender: String?,
        val currency: String?,
        val emiAmount: Long?,
        val tenureMonths: Int?,
        val startDate: String?,
        val emiPayments: String?,
        val emiAmounts: String?,
        val emiDueDay: Int?,
        val fundingAccountId: String?,
    )

    private fun parseMap(raw: String?): JsonObject? {
        if (raw.isNullOrBlank()) return null
        return try {
            json.parseToJsonElement(raw) as? JsonObject
        } catch (_: Exception) {
            null
        }
    }

    /**
     * @param asOfIso today, as YYYY-MM-DD. A parameter rather than a clock read
     *   for the same reason Finance.kt takes one: a function that reads the
     *   clock cannot be tested against a fixed date.
     * @return how many EMIs were charged.
     */
    suspend fun run(userId: String, asOfIso: String): Int {
        // tryLock, not lock: a second caller arriving while a run is in flight
        // should return immediately, the way web's `if (running) return 0` does
        // -- NOT queue up and run the whole catch-up again straight after.
        if (!running.tryLock()) return 0
        try {
            val loans = db.getAll(
                // NOT gated on auto_mark_paid. A loan linked to an account posts
                // its EMI when the EMI falls due; that is what makes the charge
                // appear in the card's total due, which is the point of linking.
                sql = """
                    SELECT id, lender, currency, emi_amount, tenure_months, start_date,
                           emi_payments, emi_amounts, emi_due_day, funding_account_id
                      FROM loans
                     WHERE deleted_at IS NULL AND funding_account_id IS NOT NULL
                """.trimIndent(),
                parameters = emptyList(),
                mapper = { c ->
                    LoanRow(
                        id = c.getString("id"),
                        lender = c.getStringOptional("lender"),
                        currency = c.getStringOptional("currency"),
                        emiAmount = c.getLongOptional("emi_amount"),
                        tenureMonths = c.getLongOptional("tenure_months")?.toInt(),
                        startDate = c.getStringOptional("start_date"),
                        emiPayments = c.getStringOptional("emi_payments"),
                        emiAmounts = c.getStringOptional("emi_amounts"),
                        emiDueDay = c.getLongOptional("emi_due_day")?.toInt(),
                        fundingAccountId = c.getStringOptional("funding_account_id"),
                    )
                },
            )

            var posted = 0
            for (loan in loans) {
                // Web falls back to a localStorage map for loans created before
                // migration 0047 added the column. There is no native
                // equivalent and there should not be one -- the column is the
                // record, and a per-device memory of it would post different
                // EMIs on different phones.
                val accountId = loan.fundingAccountId ?: continue

                // The account may have been deleted or archived since.
                val account = db.getOptional(
                    sql = "SELECT id FROM accounts WHERE id = ? AND deleted_at IS NULL AND IFNULL(is_archived, 0) = 0",
                    parameters = listOf(accountId),
                    mapper = { it.getString("id") },
                ) ?: continue

                val total = loan.tenureMonths ?: 0
                if (total <= 0) continue

                val manualMap = parseMap(loan.emiPayments)
                val manual = manualMap?.keys?.mapNotNull { it.toIntOrNull() } ?: emptyList()

                // Every EMI whose due date has passed is CHARGED, regardless of
                // auto_mark_paid -- hence autoMark = true here unconditionally.
                val due = effectivePaidEmis(
                    // `manual` is passed in even though every manual EMI is
                    // skipped below. Web does the same, and the result is
                    // identical either way -- but diverging from the source on
                    // "it makes no difference" grounds is how a port acquires
                    // differences nobody can account for later.
                    manual = manual,
                    totalEmis = total,
                    autoMark = true,
                    startIso = loan.startDate,
                    dueDay = loan.emiDueDay,
                    asOfIso = asOfIso,
                )

                val manualSet = manual.toSet()
                val amounts = parseMap(loan.emiAmounts)
                val currency = loan.currency ?: "INR"

                var done = 0
                for (n in due.sorted()) {
                    if (done >= MAX_PER_LOAN) break
                    if (n in manualSet) continue

                    val perEmi = amounts?.get(n.toString())?.jsonPrimitive?.doubleOrNull
                    val amountMinor = (perEmi ?: loan.emiAmount?.toDouble() ?: 0.0)
                    if (!amountMinor.isFinite() || amountMinor <= 0.0) continue

                    val description = emiDescription(n, loan.lender)
                    val existing = db.getOptional(
                        sql = """
                            SELECT id FROM transactions
                             WHERE description = ? AND account_id = ? AND deleted_at IS NULL
                             LIMIT 1
                        """.trimIndent(),
                        parameters = listOf(description, account),
                        mapper = { it.getString("id") },
                    )
                    if (existing != null) continue

                    val dueDate = emiDueDate(loan.startDate, loan.emiDueDay, n) ?: continue
                    try {
                        ledger.createTransaction(
                            userId = userId,
                            accountId = account,
                            type = "expense",
                            amount = money(Math.round(amountMinor), currency),
                            // Dated at the EMI's own due date, so it lands in
                            // the right month and the right billing cycle.
                            // Noon UTC. Web builds this as `new Date(`${dueDate}T12:00:00`)`,
                            // i.e. noon LOCAL, which lands on a different UTC
                            // instant per device -- two phones in different
                            // zones would stamp the same EMI differently. Noon
                            // UTC is what web's own recurring engine uses
                            // (`dueIso`), and it is stable everywhere.
                            occurredAt = "${dueDate}T12:00:00.000Z",
                            description = description,
                        )
                        posted++
                        done++
                    } catch (e: Exception) {
                        // e.g. an overdraft guard refusing the write. Leave it
                        // unposted and move to the next loan rather than
                        // stalling every other one.
                        break
                    }
                }
            }
            return posted
        } finally {
            running.unlock()
        }
    }
}
