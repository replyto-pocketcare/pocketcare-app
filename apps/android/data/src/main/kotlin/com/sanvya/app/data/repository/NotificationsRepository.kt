package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.powersync.db.getLong
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * The notifications inbox.
 *
 * Web reads this through `useUnreadCount()` (`apps/web/src/notifications/hooks.ts`),
 * which the app shell's bell badge depends on. Neither native platform had any
 * equivalent — the badge would have had to render a hardcoded zero, which is
 * worse than no badge at all.
 */
data class NotificationRow(
    val id: String,
    val kind: String,
    val title: String,
    val body: String?,
    val severity: String?,
    val href: String?,
    val readAt: String?,
    val createdAt: String?,
)

class NotificationsRepository(private val db: PowerSyncDatabase) {

    /**
     * Live count of unread, undeleted notifications.
     *
     * A `watch`, not a one-shot read: the badge has to fall to zero the moment
     * the inbox is opened, and a list driven by a one-shot `list()` looking
     * stale after a write is a bug this codebase has already shipped once
     * (Goals and Budgets, 2026-08-06).
     */
    fun watchUnreadCount(userId: String): Flow<Int> = db.watch(
        sql = """
            SELECT COUNT(*) AS n FROM notifications
            WHERE user_id = ? AND read_at IS NULL AND deleted_at IS NULL
        """.trimIndent(),
        parameters = listOf(userId),
        mapper = { cursor -> cursor.getLong("n").toInt() },
    ).map { rows -> rows.firstOrNull() ?: 0 }

    fun watchInbox(userId: String, limit: Int = 100): Flow<List<NotificationRow>> = db.watch(
        sql = """
            SELECT id, kind, title, body, severity, href, read_at, created_at
            FROM notifications
            WHERE user_id = ? AND deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT ?
        """.trimIndent(),
        parameters = listOf(userId, limit),
        mapper = { cursor ->
            NotificationRow(
                id = cursor.getString("id"),
                kind = cursor.getString("kind"),
                title = cursor.getString("title"),
                body = cursor.getStringOptional("body"),
                severity = cursor.getStringOptional("severity"),
                href = cursor.getStringOptional("href"),
                readAt = cursor.getStringOptional("read_at"),
                createdAt = cursor.getStringOptional("created_at"),
            )
        },
    )

    suspend fun markRead(userId: String, id: String, at: String) {
        updateRow(db, "notifications", id, mapOf("read_at" to at))
    }

    /** Marks everything currently unread as read, in one local transaction. */
    suspend fun markAllRead(userId: String, at: String) {
        val unread = db.getAll(
            sql = "SELECT id FROM notifications WHERE user_id = ? AND read_at IS NULL AND deleted_at IS NULL",
            parameters = listOf(userId),
            mapper = { cursor -> cursor.getString("id") },
        )
        for (id in unread) updateRow(db, "notifications", id, mapOf("read_at" to at))
    }

    /**
     * Dismiss is a SOFT delete, as it is on web: the row has already synced to
     * this user's other devices, and dismissing on one should dismiss on all.
     */
    suspend fun dismiss(id: String) {
        softDelete(db, "notifications", id)
    }
}
