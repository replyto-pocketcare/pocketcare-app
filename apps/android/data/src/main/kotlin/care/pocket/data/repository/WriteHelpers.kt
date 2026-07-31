package care.pocket.data.repository

/**
 * Generic synced-row write helpers (P2.5).
 *
 * Kotlin mirror of apps/web/src/write.ts's insertRow/updateRow/softDelete,
 * which auto-fill id/created_at/updated_at (and user_id, with the same
 * shared-ledger-table exception). Every domain repository builds its writes
 * on top of these three functions rather than hand-rolling INSERT/UPDATE SQL
 * per table, matching the web app's own stated convention (CLAUDE.md
 * "Conventions": "write with write.ts helpers (insertRow/updateRow/
 * softDelete) -- they auto-fill id/user_id/timestamps").
 *
 * [userId] is an explicit parameter here, not read from a magic global store
 * the way write.ts reads it via getUserId() from a reactive auth context --
 * Phase 2 (this file) is data-layer only, with no UI/auth-state layer built
 * yet (that's Phase 3+), so repositories take the caller's current user id
 * explicitly rather than assuming a not-yet-designed global source of truth.
 */

import com.powersync.PowerSyncDatabase
import java.time.Instant
import java.util.UUID

/**
 * Tables scoped by group_id, not user_id, and with no user_id column at all
 * -- adding one would make the INSERT fail. Identical list to write.ts's.
 */
private val SHARED_LEDGER_TABLES = setOf(
    "split_groups", "expenses", "expense_items", "settlements",
    "split_invitations", "connections", "profiles",
)

fun newId(): String = UUID.randomUUID().toString()

fun nowIso(): String = Instant.now().toString()

/**
 * Insert a row into a synced table, filling id/created_at/updated_at.
 * [userId] is added automatically unless [values] already has a "user_id"
 * key or [table] is a shared-ledger table.
 */
suspend fun insertRow(
    db: PowerSyncDatabase,
    table: String,
    userId: String,
    values: Map<String, Any?>,
): String {
    val id = newId()
    val ts = nowIso()
    val row = LinkedHashMap<String, Any?>()
    row["id"] = id
    row["created_at"] = ts
    row["updated_at"] = ts
    row.putAll(values)
    if (!values.containsKey("user_id") && table !in SHARED_LEDGER_TABLES) {
        row["user_id"] = userId
    }
    val keys = row.keys.toList()
    val placeholders = keys.joinToString(",") { "?" }
    db.execute(
        "INSERT INTO $table (${keys.joinToString(",")}) VALUES ($placeholders)",
        keys.map { row[it] },
    )
    return id
}

/** Update columns on a synced row by id (sets updated_at automatically). */
suspend fun updateRow(
    db: PowerSyncDatabase,
    table: String,
    id: String,
    values: Map<String, Any?>,
) {
    if (values.isEmpty()) return
    val sets = values.keys.map { "$it = ?" } + "updated_at = ?"
    val params = values.values.toMutableList()
    params.add(nowIso())
    params.add(id)
    db.execute("UPDATE $table SET ${sets.joinToString(", ")} WHERE id = ?", params)
}

/** Soft-delete a row (sets deleted_at) so the change syncs. */
suspend fun softDelete(db: PowerSyncDatabase, table: String, id: String) {
    val ts = nowIso()
    db.execute("UPDATE $table SET deleted_at = ?, updated_at = ? WHERE id = ?", listOf(ts, ts, id))
}
