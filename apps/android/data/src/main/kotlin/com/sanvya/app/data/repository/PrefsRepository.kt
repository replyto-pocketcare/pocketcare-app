package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
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

class PrefsRepository(private val db: PowerSyncDatabase) {
    fun watchNotificationPrefs(userId: String): Flow<NotificationPrefs?> {
        return db.watch("SELECT * FROM notification_prefs WHERE user_id = ?", listOf(userId))
            .map { result ->
                result.firstOrNull()?.let { row ->
                    NotificationPrefs(
                        user_id = row["user_id"] as String,
                        push_enabled = (row["push_enabled"] as? Long) ?: 0L,
                        emi_due = (row["emi_due"] as? Long) ?: 1L,
                        budget = (row["budget"] as? Long) ?: 1L,
                        low_balance = (row["low_balance"] as? Long) ?: 1L,
                        outlier = (row["outlier"] as? Long) ?: 1L,
                        group_invite = (row["group_invite"] as? Long) ?: 1L,
                        group_expense = (row["group_expense"] as? Long) ?: 1L,
                        low_balance_threshold = (row["low_balance_threshold"] as? Long) ?: 500L,
                        emi_lead_days = (row["emi_lead_days"] as? Long) ?: 3L
                    )
                }
            }
    }

    suspend fun getNotificationPrefs(userId: String): NotificationPrefs? {
        val result = db.getOptional("SELECT * FROM notification_prefs WHERE user_id = ?", listOf(userId))
        return result?.let { row ->
            NotificationPrefs(
                user_id = row["user_id"] as String,
                push_enabled = (row["push_enabled"] as? Long) ?: 0L,
                emi_due = (row["emi_due"] as? Long) ?: 1L,
                budget = (row["budget"] as? Long) ?: 1L,
                low_balance = (row["low_balance"] as? Long) ?: 1L,
                outlier = (row["outlier"] as? Long) ?: 1L,
                group_invite = (row["group_invite"] as? Long) ?: 1L,
                group_expense = (row["group_expense"] as? Long) ?: 1L,
                low_balance_threshold = (row["low_balance_threshold"] as? Long) ?: 500L,
                emi_lead_days = (row["emi_lead_days"] as? Long) ?: 3L
            )
        }
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
        
        db.writeTransaction {
            execute(
                sql,
                listOf(
                    userId, prefs.push_enabled, prefs.emi_due, prefs.budget, prefs.low_balance,
                    prefs.outlier, prefs.group_invite, prefs.group_expense, prefs.low_balance_threshold, prefs.emi_lead_days
                )
            )
        }
    }
}
