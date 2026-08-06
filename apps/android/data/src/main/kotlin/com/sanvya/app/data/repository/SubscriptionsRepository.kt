package com.sanvya.app.data.repository

/**
 * Read-only facade over `subscriptions` -- added 2026-08-06 for Insights'
 * genSubscriptions card (task #28), the first mobile reader of this table
 * (it has existed in AppSchema/migrations since the subscriptions feature
 * shipped on web, but no repository ever read it on mobile). Matches
 * useInsightStack.ts's subRows query exactly: only active, non-deleted rows.
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
}
