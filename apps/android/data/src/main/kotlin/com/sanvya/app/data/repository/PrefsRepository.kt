package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.powersync.db.SqlCursor
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.Serializable

@Serializable
data class NotificationPrefs(
    val user_id: String,
    val push_enabled: Long = 0,
    val emi_due: Long = 1,
    val budget: Long = 1,
    val low_balance: Long = 1,
    val outlier: Long = 1,
    val group_invite: Long = 1,
    val group_expense: Long = 1,
    val low_balance_threshold: Long = 500,
    val emi_lead_days: Long = 3
)

/** Row mapper shared by the watch/get variants below -- matches
 * LedgerRepository's convention (docs.powersync.com Kotlin SDK requires an
 * explicit `mapper` on every db.watch/get/getOptional/getAll call; there is
 * no untyped Map<String,Any?> row overload to `.let{}` into). */
private fun notificationPrefsMapper(cursor: SqlCursor): NotificationPrefs = NotificationPrefs(
    user_id = cursor.getString("user_id"),
    push_enabled = cursor.getLongOptional("push_enabled") ?: 0L,
    emi_due = cursor.getLongOptional("emi_due") ?: 1L,
    budget = cursor.getLongOptional("budget") ?: 1L,
    low_balance = cursor.getLongOptional("low_balance") ?: 1L,
    outlier = cursor.getLongOptional("outlier") ?: 1L,
    group_invite = cursor.getLongOptional("group_invite") ?: 1L,
    group_expense = cursor.getLongOptional("group_expense") ?: 1L,
    low_balance_threshold = cursor.getLongOptional("low_balance_threshold") ?: 500L,
    emi_lead_days = cursor.getLongOptional("emi_lead_days") ?: 3L
)

/**
 * The entitlement columns the app reads.
 *
 * Was the 4 that Insights' gate (domain.entitlements.isPaid) needs, added
 * 2026-08-06. The five AI-quota columns joined them 2026-08-27 for the
 * assistant, which is the only screen that shows a remaining-queries count --
 * and `entitlementState` has taken them as optional arguments since it was
 * ported, so nothing downstream needed changing to start filling them in.
 */
data class EntitlementRow(
    val tier: String?,
    val premiumTrialStartDate: String?,
    val compTier: String?,
    val compUntil: String?,
    val monthlyQuotaTotal: Int? = null,
    val monthlyQuotaUsed: Int? = null,
    val purchasedQuotaRemaining: Int? = null,
    val additionalPurchasedQuota: Int? = null,
    /** ISO date the monthly allowance refills. */
    val quotaResetDate: String? = null,
)

private fun entitlementMapper(cursor: SqlCursor): EntitlementRow = EntitlementRow(
    tier = cursor.getStringOptional("tier"),
    premiumTrialStartDate = cursor.getStringOptional("premium_trial_start_date"),
    compTier = cursor.getStringOptional("comp_tier"),
    compUntil = cursor.getStringOptional("comp_until"),
    monthlyQuotaTotal = cursor.getLongOptional("monthly_quota_total")?.toInt(),
    monthlyQuotaUsed = cursor.getLongOptional("monthly_quota_used")?.toInt(),
    purchasedQuotaRemaining = cursor.getLongOptional("purchased_quota_remaining")?.toInt(),
    additionalPurchasedQuota = cursor.getLongOptional("additional_purchased_quota")?.toInt(),
    quotaResetDate = cursor.getStringOptional("quota_reset_date"),
)

class PrefsRepository(private val db: PowerSyncDatabase) {
    /** Single entitlements row for the current user (there is exactly one
     * per web's `SELECT ... FROM entitlements LIMIT 1` -- no user_id filter
     * needed, PowerSync's sync rules already scope it to the signed-in
     * user). Real db.watch() so Insights' premium gate reacts immediately
     * to a plan change synced down from Supabase. */
    fun watchEntitlement(): Flow<EntitlementRow?> = db.watch(
        """
        SELECT tier, premium_trial_start_date, comp_tier, comp_until,
               monthly_quota_total, monthly_quota_used, purchased_quota_remaining,
               additional_purchased_quota, quota_reset_date
        FROM entitlements LIMIT 1
        """.trimIndent(),
        mapper = ::entitlementMapper,
    ).map { it.firstOrNull() }

    fun watchNotificationPrefs(userId: String): Flow<NotificationPrefs?> {
        return db.watch(
            "SELECT * FROM notification_prefs WHERE user_id = ?",
            parameters = listOf(userId),
            mapper = ::notificationPrefsMapper,
        ).map { it.firstOrNull() }
    }

    suspend fun getNotificationPrefs(userId: String): NotificationPrefs? {
        return db.getOptional(
            "SELECT * FROM notification_prefs WHERE user_id = ?",
            parameters = listOf(userId),
            mapper = ::notificationPrefsMapper,
        )
    }

    suspend fun updateNotificationPrefs(userId: String, prefs: NotificationPrefs) {
        val sql = """
            INSERT INTO notification_prefs 
            (user_id, push_enabled, emi_due, budget, low_balance, outlier, group_invite, group_expense, low_balance_threshold, emi_lead_days)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (user_id) DO UPDATE SET
            push_enabled = excluded.push_enabled,
            emi_due = excluded.emi_due,
            budget = excluded.budget,
            low_balance = excluded.low_balance,
            outlier = excluded.outlier,
            group_invite = excluded.group_invite,
            group_expense = excluded.group_expense,
            low_balance_threshold = excluded.low_balance_threshold,
            emi_lead_days = excluded.emi_lead_days
        """.trimIndent()
        
        db.writeTransaction { tx ->
            tx.execute(
                sql = sql,
                parameters = listOf(
                    userId, prefs.push_enabled, prefs.emi_due, prefs.budget, prefs.low_balance,
                    prefs.outlier, prefs.group_invite, prefs.group_expense, prefs.low_balance_threshold, prefs.emi_lead_days
                )
            )
        }
    }
}
