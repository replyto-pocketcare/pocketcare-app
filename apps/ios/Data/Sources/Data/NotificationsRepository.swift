import Foundation
import PowerSync

/**
 The notifications inbox.

 Web reads this through `useUnreadCount()` (`apps/web/src/notifications/hooks.ts`),
 which the app shell's bell badge depends on. Neither native platform had any
 equivalent — the badge would have had to render a hardcoded zero, which is
 worse than no badge at all. Mirrors Android's `NotificationsRepository.kt`
 field for field.
 */
public struct NotificationRow: Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let body: String?
    public let severity: String?
    public let href: String?
    public let readAt: String?
    public let createdAt: String?
}

public actor NotificationsRepository {
    private let db: PowerSyncDatabaseProtocol

    public init(db: PowerSyncDatabaseProtocol) {
        self.db = db
    }

    /**
     Live count of unread, undeleted notifications.

     A `watch`, not a one-shot read: the badge has to fall to zero the moment
     the inbox is opened, and a list driven by a one-shot read looking stale
     after a write is a bug this codebase has already shipped once (Goals and
     Budgets, 2026-08-06).
     */
    public func watchUnreadCount(userId: String) throws -> AsyncThrowingStream<[Int64], Error> {
        try db.watch(
            sql: """
            SELECT COUNT(*) AS n FROM notifications
            WHERE user_id = ? AND read_at IS NULL AND deleted_at IS NULL
            """,
            parameters: [userId],
            mapper: { cursor in try cursor.getInt64(name: "n") }
        )
    }

    public func watchInbox(userId: String, limit: Int = 100) throws -> AsyncThrowingStream<[NotificationRow], Error> {
        try db.watch(
            sql: """
            SELECT id, kind, title, body, severity, href, read_at, created_at
            FROM notifications
            WHERE user_id = ? AND deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT ?
            """,
            parameters: [userId, limit],
            mapper: { cursor in
                NotificationRow(
                    id: try cursor.getString(name: "id"),
                    kind: try cursor.getString(name: "kind"),
                    title: try cursor.getString(name: "title"),
                    body: try cursor.getStringOptional(name: "body"),
                    severity: try cursor.getStringOptional(name: "severity"),
                    href: try cursor.getStringOptional(name: "href"),
                    readAt: try cursor.getStringOptional(name: "read_at"),
                    createdAt: try cursor.getStringOptional(name: "created_at")
                )
            }
        )
    }

    public func markRead(id: String, at: String) async throws {
        try await updateRow(db: db, table: "notifications", id: id, values: ["read_at": at])
    }

    /// Marks everything currently unread as read.
    ///
    /// Row by row rather than one bulk `UPDATE ... WHERE read_at IS NULL`,
    /// which is what Android already does and what PowerSync needs: its upload
    /// queue records a CRUD entry per row, and a bulk statement over rows it
    /// never saw named would sync as nothing at all.
    public func markAllRead(userId: String, at: String) async throws {
        let ids: [String] = try await db.getAll(
            sql: "SELECT id FROM notifications WHERE user_id = ? AND read_at IS NULL AND deleted_at IS NULL",
            parameters: [userId],
            mapper: { cursor in try cursor.getString(name: "id") }
        )
        for id in ids {
            try await updateRow(db: db, table: "notifications", id: id, values: ["read_at": at])
        }
    }

    /// Dismiss is a SOFT delete, as it is on web: the row has already synced to
    /// this user's other devices, and dismissing on one should dismiss on all.
    public func dismiss(id: String) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE notifications SET deleted_at = ?, updated_at = ? WHERE id = ?",
            parameters: [ts, ts, id]
        )
    }
}
