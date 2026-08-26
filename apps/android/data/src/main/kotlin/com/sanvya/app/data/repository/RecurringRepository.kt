package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.powersync.db.SqlCursor
// The cursor accessors are EXTENSION functions on SqlCursor living in
// com.powersync.db -- each has to be imported by name or the call site does not
// resolve. Every other repository here imports exactly this set.
import com.powersync.db.getBooleanOptional
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.recurring.advance
import kotlinx.coroutines.flow.Flow

/**
 * Recurring commitments — the port of apps/web/src/recurring/engine.ts.
 *
 * A commitment is one row of `recurring_items`, the table migration 0060
 * consolidated `planned_cashflow` + `recurring_rules` + `transaction_templates`
 * into. Everything an occurrence needs to become a transaction lives on that
 * one row.
 *
 * Two things about this port are worth stating up front.
 *
 * **`next_due` is the cursor, and it is authoritative.** Posting an occurrence
 * and advancing `next_due` are a pair; if the post fails, `next_due` stays put
 * so the item still reads as due and will be retried on the next run. That is
 * why the catch-up loop below breaks rather than continuing on failure — an
 * overdraft-blocked auto-post must not silently skip a month.
 *
 * **Nothing here reads a clock or a preference.** `todayIso` and
 * `baseCurrency` are parameters. `:data` cannot see `ui/Prefs.kt`, and
 * duplicating the SharedPreferences read here would create a second source of
 * truth for a user-visible setting. Finance.kt already takes `asOfIso` for the
 * same reason.
 */
class RecurringRepository(
    private val db: PowerSyncDatabase,
    private val ledger: LedgerRepository,
    private val splits: SplitsRepository,
) {
    /** One row of `recurring_items`, as the engine reads it. */
    data class Item(
        val id: String,
        val direction: String,
        val name: String,
        val amount: Long?,
        val currency: String?,
        val frequency: String,
        val intervalCount: Long?,
        val nextDue: String,
        val accountId: String?,
        val toAccountId: String?,
        val categoryId: String?,
        val autoPost: Boolean,
        val active: Boolean,
        val alertTimeUtc: String?,
        val description: String?,
        val note: String?,
        val paymentMethod: String?,
        val labels: String?,
        val splitGroupId: String?,
    )

    /**
     * One row of the Subscriptions tile's query -- web's own six columns, not
     * [Item]. See [watchSubscriptions] for why the tile does not reuse [Item].
     */
    data class Subscription(
        val id: String,
        val name: String,
        val amount: Long,
        val currency: String,
        val frequency: String,
        val nextDue: String?,
        /**
         * When the commitment was created. The only reliable "since when have I
         * been paying this" signal there is -- nothing links a transaction to a
         * subscription -- which is what `estimatedSpentToDate` counts from.
         */
        val createdAt: String?,
    )

    private companion object {
        /** Mirrors web's RECURRING_COLUMNS, column for column. */
        const val COLUMNS =
            "id, direction, name, amount, currency, frequency, interval_count, next_due, " +
                "account_id, to_account_id, category_id, auto_post, active, alert_time_utc, " +
                "description, note, payment_method, labels, split_group_id"

        /**
         * Catching up more than two years of missed occurrences in one run is a
         * bug, not a feature. Same guard value web uses.
         */
        const val MAX_CATCH_UP_PER_ITEM = 24

        /**
         * Noon UTC, not midnight. An occurrence dated `T00:00:00Z` lands on the
         * previous day for anyone west of Greenwich, which silently shifts it
         * into the wrong month for month-boundary commitments. Web's `dueIso`
         * does the same thing for the same reason.
         */
        fun dueIso(day: String): String = "${day}T12:00:00.000Z"
    }

    private fun map(cursor: SqlCursor) = Item(
        id = cursor.getString("id"),
        direction = cursor.getStringOptional("direction") ?: "expense",
        name = cursor.getStringOptional("name") ?: "",
        amount = cursor.getLongOptional("amount"),
        currency = cursor.getStringOptional("currency"),
        frequency = cursor.getStringOptional("frequency") ?: "monthly",
        intervalCount = cursor.getLongOptional("interval_count"),
        nextDue = cursor.getStringOptional("next_due") ?: "",
        accountId = cursor.getStringOptional("account_id"),
        toAccountId = cursor.getStringOptional("to_account_id"),
        categoryId = cursor.getStringOptional("category_id"),
        autoPost = cursor.getBooleanOptional("auto_post") ?: false,
        active = cursor.getBooleanOptional("active") ?: false,
        alertTimeUtc = cursor.getStringOptional("alert_time_utc"),
        description = cursor.getStringOptional("description"),
        note = cursor.getStringOptional("note"),
        paymentMethod = cursor.getStringOptional("payment_method"),
        labels = cursor.getStringOptional("labels"),
        splitGroupId = cursor.getStringOptional("split_group_id"),
    )

    /**
     * The transaction type a direction posts.
     *
     * Savings are a transfer into the target account; payments are expenses;
     * income is income. Web routes this through two helpers (`directionOf` then
     * `typeForDirection`) because its UI says "payment" where the column says
     * "expense" — a translation that only exists to keep the UI's word out of
     * the check constraint 0060 defined. Native has no such vocabulary split,
     * so the round trip collapses to this.
     */
    private fun typeFor(direction: String): String = when (direction) {
        "income" -> "income"
        "saving" -> "transfer"
        else -> "expense"
    }

    /**
     * Every active commitment, for the Recurring screen's monthly summary.
     *
     * Mirrors web's `useRecurringItems()` — `active = 1`, ordered by `next_due`,
     * and NOT filtered by direction, because savings are excluded by the
     * summary rather than by the query (they still post, and still appear under
     * "Due now"; they simply have no browsable list on this screen).
     */
    fun watchActiveItems(): Flow<List<Item>> = db.watch(
        sql = """
            SELECT $COLUMNS FROM recurring_items
             WHERE deleted_at IS NULL AND active = 1
             ORDER BY next_due
        """.trimIndent(),
        parameters = emptyList(),
        mapper = ::map,
    )

    /** Items due today or earlier that do NOT auto-post — the ones asking to be confirmed. */
    /**
     * Active recurring PAYMENTS filed under the Subscriptions category.
     *
     * Both spellings are matched because the seed taxonomy says
     * "Subscriptions" while an older recurring group said "Subscription", and a
     * user who typed either meant the same thing. Web's comment says exactly
     * that, and the query is web's.
     *
     * Returns [Subscription], not [Item]: web's query selects six columns, one
     * of which (`created_at`) [Item] does not carry, and every column is
     * aliased so the join's ambiguous bare `id` never arises. Widening [Item]
     * to hold `created_at` would force every OTHER query in this file to select
     * it too -- the shared column list does not -- so the tile gets the row
     * shape it actually needs instead.
     */
    fun watchSubscriptions(): Flow<List<Subscription>> = db.watch(
        """SELECT i.id AS id, i.name AS name, COALESCE(i.amount, 0) AS amount,
                  COALESCE(i.currency, '') AS currency, i.frequency AS frequency,
                  i.next_due AS next_due, i.created_at AS created_at
             FROM recurring_items i
             JOIN categories c ON c.id = i.category_id
            WHERE i.deleted_at IS NULL AND c.deleted_at IS NULL
              AND i.active = 1 AND i.direction = 'expense'
              AND lower(c.name) IN ('subscription', 'subscriptions')
            ORDER BY i.next_due""",
        parameters = emptyList(),
        mapper = { cursor ->
            Subscription(
                id = cursor.getString("id"),
                name = cursor.getStringOptional("name") ?: "",
                amount = cursor.getLongOptional("amount") ?: 0L,
                currency = cursor.getStringOptional("currency") ?: "",
                frequency = cursor.getStringOptional("frequency") ?: "monthly",
                nextDue = cursor.getStringOptional("next_due"),
                createdAt = cursor.getStringOptional("created_at"),
            )
        },
    )

    fun watchDueItems(todayIso: String): Flow<List<Item>> = db.watch(
        sql = """
            SELECT $COLUMNS FROM recurring_items
             WHERE deleted_at IS NULL AND active = 1 AND auto_post = 0 AND next_due <= ?
             ORDER BY next_due
        """.trimIndent(),
        parameters = listOf(todayIso),
        mapper = ::map,
    )

    private suspend fun byId(id: String): Item? = db.getOptional(
        sql = "SELECT $COLUMNS FROM recurring_items WHERE id = ? AND deleted_at IS NULL",
        parameters = listOf(id),
        mapper = ::map,
    )

    /**
     * Turn one due occurrence into a real transaction.
     *
     * Carries description, note, payment method, labels, transfer destination
     * and the recurring split, so moving off templates does not quietly strip
     * detail from posted transactions.
     */
    suspend fun materialize(
        item: Item,
        occurredAtIso: String,
        userId: String,
        baseCurrency: String,
    ) {
        val currency = item.currency ?: baseCurrency
        val total = money(item.amount ?: 0L, currency)

        // Recurring split: equal split among the group's CURRENT members, you
        // pay. Fewer than two members is not a split -- it falls through to a
        // plain transaction rather than creating a one-person expense.
        val groupId = item.splitGroupId
        val accountId = item.accountId
        if (groupId != null && accountId != null) {
            val memberIds = db.getAll(
                sql = "SELECT user_id FROM split_group_members WHERE group_id = ? AND deleted_at IS NULL",
                parameters = listOf(groupId),
                mapper = { it.getString("user_id") },
            )
            if (memberIds.size >= 2) {
                splits.createSplitExpense(
                    userId = userId,
                    input = SplitExpenseInput(
                        groupId = groupId,
                        mode = "equal",
                        total = total,
                        participants = memberIds.map { ParticipantInput(userId = it) },
                        payers = listOf(PayerInput(userId = userId, paid = total.amount, accountId = accountId)),
                        categoryId = item.categoryId,
                        description = item.description,
                        note = item.note,
                        occurredAt = occurredAtIso,
                    ),
                )
                return
            }
        }

        val type = typeFor(item.direction)
        if (type == "transfer" && item.toAccountId != null && accountId != null) {
            // Deliberately no category/description/labels and no toAmount --
            // matching web exactly. A null to_amount leaves fx_rate null, which
            // is correct for a same-currency transfer and is what web produces.
            ledger.createTransaction(
                userId = userId,
                accountId = accountId,
                type = "transfer",
                amount = total,
                occurredAt = occurredAtIso,
                note = item.note,
                toAccountId = item.toAccountId,
            )
        } else if (accountId != null) {
            ledger.createTransaction(
                userId = userId,
                accountId = accountId,
                type = if (type == "income") "income" else "expense",
                amount = total,
                occurredAt = occurredAtIso,
                categoryId = item.categoryId,
                labels = item.labels
                    ?.split(",")
                    ?.map { it.trim() }
                    ?.filter { it.isNotEmpty() }
                    ?: emptyList(),
                note = item.note,
                description = item.description,
                paymentMethod = item.paymentMethod,
            )
        }
        // No account_id: nothing to post against. Web falls through silently
        // too -- the row is a plan, not yet a chargeable commitment.
    }

    /**
     * Post every auto-post item that has come due, catching up missed occurrences.
     *
     * @return how many transactions were posted.
     */
    suspend fun runRecurring(userId: String, todayIso: String, baseCurrency: String): Int {
        val items = db.getAll(
            sql = """
                SELECT $COLUMNS FROM recurring_items
                 WHERE deleted_at IS NULL AND active = 1 AND auto_post = 1 AND next_due <= ?
            """.trimIndent(),
            parameters = listOf(todayIso),
            mapper = ::map,
        )

        var posted = 0
        for (item in items) {
            var due = item.nextDue
            var guard = 0
            while (due <= todayIso && guard++ < MAX_CATCH_UP_PER_ITEM) {
                try {
                    materialize(item, dueIso(due), userId, baseCurrency)
                } catch (e: Exception) {
                    // e.g. an overdraft-blocked auto-post. Leave next_due where
                    // it is so the item still reads as due, and move on to the
                    // next item instead of stalling every one behind it.
                    break
                }
                val next = advance(due, item.frequency, (item.intervalCount ?: 1L).toInt())
                updateRow(
                    db, "recurring_items", item.id,
                    mapOf("next_due" to next, "last_generated" to due),
                )
                due = next
                posted++
            }
        }
        return posted
    }

    /** Post one occurrence now and advance ("Post now" / confirming a due item). */
    suspend fun postOnce(id: String, userId: String, baseCurrency: String) {
        val item = byId(id) ?: return
        materialize(item, dueIso(item.nextDue), userId, baseCurrency)
        updateRow(
            db, "recurring_items", id,
            mapOf(
                "next_due" to advance(item.nextDue, item.frequency, (item.intervalCount ?: 1L).toInt()),
                "last_generated" to item.nextDue,
            ),
        )
    }

    /**
     * What the create/edit form supplies. Mirrors web's `RecurringInput`, with
     * one deliberate difference: [amountMinor] is already in minor units.
     *
     * Web's `toRow` does `Math.round(inp.amount * 100)` — a hardcoded x100,
     * which is wrong for every currency that is not two-decimal (JPY has none,
     * BHD has three) and against this repo's own golden rule 1. The conversion
     * happens in the view model here, through `fromMajor`, which asks
     * `minorUnits(currency)`.
     */
    data class Input(
        val direction: String,
        val name: String,
        val amountMinor: Long,
        val currency: String,
        val accountId: String?,
        val toAccountId: String? = null,
        val categoryId: String? = null,
        val frequency: String,
        val firstDue: String,
        val autoPost: Boolean,
        val alertTimeUtc: String? = null,
    )

    private fun Input.toRow(): Map<String, Any?> = mapOf(
        "direction" to direction,
        "name" to name.trim(),
        "amount" to amountMinor,
        "currency" to currency,
        "frequency" to frequency,
        // Web hardcodes 1 here too. Every interval in the UI is "every 1
        // <frequency>"; the column exists for a multiplier no screen offers yet.
        "interval_count" to 1L,
        "next_due" to firstDue,
        "account_id" to accountId,
        "to_account_id" to toAccountId,
        "category_id" to categoryId,
        // Booleans are INTEGER 0/1 in this schema -- pass Long, not Boolean,
        // matching setAccountArchived's convention elsewhere in :data.
        "auto_post" to if (autoPost) 1L else 0L,
        "alert_time_utc" to alertTimeUtc,
    )

    /** New commitment. `active = 1`, nothing generated yet. */
    suspend fun create(userId: String, input: Input): String = insertRow(
        db, "recurring_items", userId,
        input.toRow() + mapOf("active" to 1L, "last_generated" to null),
    )

    /**
     * Edit an existing one.
     *
     * `last_generated` is deliberately untouched: editing the amount of a rent
     * commitment does not un-post the months already posted, and clearing it
     * would make the engine's history read as if nothing had ever run.
     */
    suspend fun update(id: String, input: Input) = updateRow(db, "recurring_items", id, input.toRow())

    /**
     * Stop a commitment.
     *
     * A soft delete (`deleted_at`), like every other removal in this app —
     * `active = 0` would also hide it from the lists, but the row would keep
     * syncing and keep answering queries that filter only on `deleted_at`.
     * Web's `removeRecurring` soft-deletes for the same reason.
     */
    suspend fun remove(id: String) = softDelete(db, "recurring_items", id)

    /**
     * Skip one occurrence without posting.
     *
     * `last_generated` is deliberately NOT touched, matching web: nothing was
     * generated, and writing it here would make a skipped month look posted.
     */
    suspend fun skipOnce(id: String) {
        val item = byId(id) ?: return
        updateRow(
            db, "recurring_items", id,
            mapOf("next_due" to advance(item.nextDue, item.frequency, (item.intervalCount ?: 1L).toInt())),
        )
    }
}
