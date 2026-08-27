package com.sanvya.app.data.repository

/**
 * Facade over `subscriptions` -- added 2026-08-06 for Insights'
 * genSubscriptions card (task #28), the first mobile reader of this table
 * (it has existed in AppSchema/migrations since the subscriptions feature
 * shipped on web, but no repository ever read it on mobile). Matches
 * useInsightStack.ts's subRows query exactly: only active, non-deleted rows.
 *
 * Read-ONLY until 2026-08-27, when the assistant's `create_subscription` tool
 * needed a writer. It lives here rather than in AssistantRepository because
 * every other table in this app is written through the repository that owns it,
 * and a tool reaching past that would be the first exception.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.getLong
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import kotlinx.coroutines.flow.Flow

data class SubscriptionRow(val id: String, val name: String?, val amount: Long, val currency: String, val billingCycle: String?)

class SubscriptionsRepository(private val db: PowerSyncDatabase) {
    fun watchActive(): Flow<List<SubscriptionRow>> = db.watch(
        sql = "SELECT id, name, amount, currency, billing_cycle FROM subscriptions WHERE deleted_at IS NULL AND is_active = 1",
        mapper = { cursor ->
            SubscriptionRow(
                id = cursor.getString("id"),
                name = cursor.getStringOptional("name"),
                amount = cursor.getLong("amount"),
                currency = cursor.getStringOptional("currency") ?: "INR",
                billingCycle = cursor.getStringOptional("billing_cycle"),
            )
        },
    )

    /**
     * Insert a subscription. Matches web's `insertRow("subscriptions", …)` from
     * the assistant's tool, including its defaults: active, with no purchase
     * date and no next renewal.
     *
     * `next_renewal` being null is not an oversight -- web leaves it null too,
     * and the consequence is real: `buildFinancialSummary`'s "upcoming" list
     * only shows renewals that HAVE a date, so an assistant-created
     * subscription counts toward the monthly obligations total and never
     * appears as an upcoming charge until the user fills the date in. Recorded
     * in ABSENT-BY-DECISION rather than silently improved on.
     */
    suspend fun create(
        userId: String,
        name: String,
        amount: Long,
        currency: String,
        billingCycle: String,
        purchasedOn: String? = null,
        nextRenewal: String? = null,
        categoryId: String? = null,
    ): String {
        val id = newId()
        val ts = nowIso()
        db.execute(
            sql = """
                INSERT INTO subscriptions
                (id,user_id,name,amount,currency,billing_cycle,purchased_on,next_renewal,category_id,is_active,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                """.trimIndent(),
            parameters = listOf(
                id, userId, name, amount, currency, billingCycle,
                purchasedOn, nextRenewal, categoryId, 1L, ts, ts,
            ),
        )
        return id
    }
}
