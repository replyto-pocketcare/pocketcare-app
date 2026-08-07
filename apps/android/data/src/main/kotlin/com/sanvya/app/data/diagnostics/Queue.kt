package com.sanvya.app.data.diagnostics

/**
 * Inspecting and repairing the pending-upload queue, from inside the app.
 *
 * Ported from apps/web/src/diagnostics/queue.ts (Settings screen pass).
 *
 * THE FAILURE MODE THIS TARGETS: PowerSync uploads the queue in order and
 * retries forever on failure. If a queued row references a parent row that
 * never reached the server, its INSERT can never succeed -- foreign key or
 * RLS, either way it's permanent -- and everything queued behind it is
 * blocked. One orphaned row silently freezes all of a user's writes.
 *
 * Reads `ps_crud` directly (raw SQL, not a typed SDK accessor): PowerSync's
 * own getCrudBatch() caps at a batch size and gives no row ids to delete, so
 * it can't drive a repair UI. Mirrors the exact same choice in queue.ts.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.getString
import com.sanvya.app.domain.diagnostics.LogEntry
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull

/** Parent lookups for the tables that can strand a child row. */
private data class ForeignKey(val column: String, val parentTable: String)

private val FOREIGN_KEYS: Map<String, ForeignKey> = mapOf(
    "split_group_members" to ForeignKey("group_id", "split_groups"),
    "expenses" to ForeignKey("group_id", "split_groups"),
    "expense_participants" to ForeignKey("expense_id", "expenses"),
    "expense_items" to ForeignKey("expense_id", "expenses"),
    "expense_item_shares" to ForeignKey("item_id", "expense_items"),
    "settlements" to ForeignKey("group_id", "split_groups"),
    "transaction_items" to ForeignKey("transaction_id", "transactions"),
    "transaction_labels" to ForeignKey("transaction_id", "transactions"),
)

data class QueuedOp(
    /** ps_crud row id -- what we delete to discard the op. */
    val id: Long,
    val table: String,
    val op: String,
    val rowId: String,
    /** True when this op cannot upload: it's the one the server keeps rejecting. */
    val orphaned: Boolean,
    val reason: String? = null,
)

/** `sanvya.split_group_members` -> `split_group_members` (also handles "pocketcare."). */
fun stripSchema(table: String): String {
    val dot = table.lastIndexOf(".")
    return if (dot >= 0) table.substring(dot + 1) else table
}

/**
 * Read the pending queue and flag orphans.
 *
 * NOTE ON DETECTION (matches queue.ts's own note): the reliable signal is the
 * failure itself, not a local FK check -- the parent exists locally (that's
 * where the user created it); what's missing is the parent ON THE SERVER,
 * which a client can't see for a row that never uploaded. So every queued op
 * for the table the server is actively rejecting is a blocker by definition.
 * The local FK check is a secondary signal that catches rows orphaned by a
 * local delete.
 */
suspend fun inspectQueue(
    db: PowerSyncDatabase,
    failingTable: String? = null,
    limit: Int = 200,
): List<QueuedOp> {
    val rows = try {
        db.getAll(
            sql = "SELECT id, data FROM ps_crud ORDER BY id LIMIT ?",
            parameters = listOf(limit),
            mapper = { cursor -> cursor.getString("id").toLong() to cursor.getString("data") },
        )
    } catch (_: Exception) {
        return emptyList()
    }

    val out = mutableListOf<QueuedOp>()
    for ((rowId, data) in rows) {
        val parsed = try {
            Json.parseToJsonElement(data) as? JsonObject ?: continue
        } catch (_: Exception) {
            continue
        }
        val table = parsed["type"]?.jsonPrimitive?.contentOrNull ?: ""
        val op = parsed["op"]?.jsonPrimitive?.contentOrNull ?: ""
        val opRowId = parsed["id"]?.jsonPrimitive?.contentOrNull ?: ""

        var orphaned = false
        var reason: String? = null

        if (failingTable != null && table == stripSchema(failingTable)) {
            orphaned = true
            reason = "the server keeps rejecting this"
        }

        val fk = FOREIGN_KEYS[table]
        if (fk != null && op.uppercase() == "PUT") {
            val opData = parsed["data"] as? JsonObject
            val parentId = opData?.get(fk.column)?.jsonPrimitive?.contentOrNull
            if (!parentId.isNullOrEmpty()) {
                try {
                    val parent = db.getOptional(
                        sql = "SELECT id FROM ${fk.parentTable} WHERE id = ?",
                        parameters = listOf(parentId),
                        mapper = { c -> c.getString("id") },
                    )
                    if (parent == null) {
                        orphaned = true
                        reason = "${fk.parentTable} row is missing"
                    }
                } catch (_: Exception) {
                    // table not in schema -- can't judge, leave it alone
                }
            }
        }

        out.add(QueuedOp(id = rowId, table = table, op = op, rowId = opRowId, orphaned = orphaned, reason = reason))
    }
    return out
}

/**
 * Delete specific queued ops.
 *
 * Destructive and deliberately narrow: callers should only ever pass ids
 * that have been PROVEN orphaned. Discarding a good op silently loses a
 * user's data.
 */
suspend fun discardOps(db: PowerSyncDatabase, ids: List<Long>): Int {
    if (ids.isEmpty()) return 0
    val placeholders = ids.joinToString(",") { "?" }
    db.execute("DELETE FROM ps_crud WHERE id IN ($placeholders)", ids)
    logDiagnostic(level = "info", scope = "sync", message = "discarded ${ids.size} stuck change(s) from the upload queue")
    return ids.size
}

/** Compact summary for the shared log and for auto-reports. */
fun summarizeQueue(ops: List<QueuedOp>): String {
    if (ops.isEmpty()) return "empty"
    val byTable = LinkedHashMap<String, Int>()
    for (o in ops) byTable[o.table] = (byTable[o.table] ?: 0) + 1
    val orphans = ops.filter { it.orphaned }
    val parts = byTable.entries.joinToString(", ") { (t, n) -> "$t×$n" }
    return if (orphans.isNotEmpty()) {
        val distinct = orphans.map { "${it.table} (${it.reason})" }.distinct().joinToString("; ")
        "${ops.size} pending ($parts) — ${orphans.size} STUCK: $distinct"
    } else {
        "${ops.size} pending ($parts)"
    }
}

/**
 * Pull the failing table out of the most recent sync error. Prefers the
 * structured `detail.table` the connector emits; falls back to parsing the
 * message, which is all we have on an older build.
 */
fun failingTableFrom(entries: List<LogEntry>): String? {
    val uploadFailedRe = Regex("upload failed for ([\\w.]+)", RegexOption.IGNORE_CASE)
    for (i in entries.indices.reversed()) {
        val e = entries[i]
        if (e.scope != "sync" && e.scope != "console") continue
        val structured = (e.detail?.value?.get("table") as? com.sanvya.app.domain.diagnostics.DetailValue.Str)?.value
        if (!structured.isNullOrEmpty()) return stripSchema(structured)
        val m = uploadFailedRe.find(e.message)
        if (m != null) return stripSchema(m.groupValues[1])
    }
    return null
}
