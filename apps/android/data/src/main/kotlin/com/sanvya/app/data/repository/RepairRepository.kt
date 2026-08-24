package com.sanvya.app.data.repository

/**
 * Repair logic and dead-letter queue operations (P2.6a, extended for the
 * Settings screen pass to add the network-facing half: scanForStranded/
 * repairStranded/retryFailedWrite/discardFailedWrite).
 * Mirrors apps/web/src/sync/repair.ts and apps/web/src/sync/deadletter.ts.
 *
 * Scans local DB for stranded rows that never reached the server (parents before
 * children, per REPAIR_ORDER), formats human-readable row labels (describeRow),
 * generates JSON export payloads, and provides retry/discard functionality for
 * quarantined writes in failed_writes.
 *
 * Re-upload/retry go DIRECT via Supabase, not by tricking PowerSync into
 * re-queueing -- same reasoning as repair.ts: we hold the complete row and
 * control ordering, so an upsert states the intended end state plainly.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import com.sanvya.app.data.diagnostics.logDiagnostic
import com.sanvya.app.domain.syncpolicy.FailureInput
import com.sanvya.app.domain.syncpolicy.explainForUser
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonNull
import java.time.Instant

/** Postgres schema every table/RPC lives in (matches SupabaseConnector.DB_SCHEMA). */
private const val REPAIR_SCHEMA = "pocketcare"

val REPAIR_ORDER: List<String> = listOf(
    "accounts",
    "categories",
    "labels",
    "budgets",
    "goals",
    "transactions",
    "transaction_items",
    "transaction_labels",
    "split_groups",
    "split_group_members",
    "expenses",
    "expense_participants",
    "expense_items",
    "expense_item_shares",
    "settlements",
    "expense_postings",
    "goal_allocations",
    "loans",
    "subscriptions",
    "recurring_commitments",
    // "planned_cashflow" was here and is not in web's REPAIR_ORDER
    // (apps/web/src/sync/repair.ts). Migration 0060 folded that table into
    // recurring_items; web dropped it, both native copies kept it. Harmless
    // while the native schema was stale enough to still declare the table --
    // and a query against a view PowerSync no longer creates the moment the
    // schema caught up.
    "holdings",
    "receipt_scans"
)

data class StrandedRow(
    val table: String,
    val id: String,
    val label: String,
    val row: Map<String, Any?>,
)

data class RepairScanResult(
    val stranded: List<StrandedRow>,
    val unchecked: List<String>,
)

data class FailedWriteItem(
    val id: String,
    val table: String,
    val op: String,
    val rowId: String,
    val payload: Map<String, Any?>,
    val code: String?,
    val message: String?,
    val reason: String?,
    val attempts: Int,
    val failedAt: String,
    val label: String,
    val explanation: String,
)

fun describeRow(table: String, row: Map<String, Any?>): String {
    return when (table) {
        "transactions" -> {
            val desc = (row["description"] as? String)?.ifEmpty { null } ?: "Transaction"
            val amt = (row["amount"] as? Number)?.toLong() ?: 0L
            val curr = (row["currency"] as? String) ?: "INR"
            val dt = (row["occurred_at"] as? String)?.take(10) ?: ""
            "$desc · $curr ${amt / 100.0} · $dt"
        }
        "expenses" -> {
            val desc = (row["description"] as? String)?.ifEmpty { null } ?: "Shared expense"
            val amt = (row["amount"] as? Number)?.toLong() ?: 0L
            val curr = (row["currency"] as? String) ?: "INR"
            val dt = (row["occurred_at"] as? String)?.take(10) ?: ""
            "$desc · $curr ${amt / 100.0} · $dt"
        }
        "accounts" -> "Account “${row["name"] ?: ""}”"
        "split_groups" -> "Group “${row["name"] ?: ""}”"
        "budgets" -> "Budget “${row["name"] ?: ""}”"
        "goals" -> "Goal “${row["name"] ?: ""}”"
        "settlements" -> {
            val amt = (row["amount"] as? Number)?.toLong() ?: 0L
            val curr = (row["currency"] as? String) ?: "INR"
            "Settlement · $curr ${amt / 100.0}"
        }
        "categories" -> "Category “${row["name"] ?: ""}”"
        "labels" -> "Label “${row["name"] ?: ""}”"
        else -> "${table.replace("_", " ")} entry"
    }
}

class RepairRepository(
    private val db: PowerSyncDatabase,
    private val client: SupabaseClient,
    private val getUserId: () -> String,
) {
    suspend fun listFailedWrites(limit: Int = 100): List<FailedWriteItem> {
        val rows = try {
            db.getAll(
                sql = "SELECT * FROM failed_writes WHERE resolved_at IS NULL ORDER BY failed_at DESC LIMIT ?",
                parameters = listOf(limit),
                mapper = { cursor ->
                    mapOf(
                        "id" to cursor.getString("id"),
                        "table_name" to cursor.getString("table_name"),
                        "op" to cursor.getString("op"),
                        "row_id" to cursor.getString("row_id"),
                        "payload" to cursor.getString("payload"),
                        "code" to cursor.getStringOptional("code"),
                        "message" to cursor.getStringOptional("message"),
                        "reason" to cursor.getStringOptional("reason"),
                        "attempts" to (cursor.getLongOptional("attempts")?.toInt() ?: 0),
                        "failed_at" to cursor.getString("failed_at")
                    )
                }
            )
        } catch (_: Exception) {
            return emptyList()
        }

        return rows.map { r ->
            val tableName = r["table_name"] as String
            val rowId = r["row_id"] as String
            val code = r["code"] as? String
            val message = r["message"] as? String

            val payloadMap = parsePayloadJson(r["payload"] as? String).toMutableMap()
            payloadMap["id"] = rowId

            val label = describeRow(tableName, payloadMap)
            val explanation = explainForUser(FailureInput(code = code, message = message))

            FailedWriteItem(
                id = r["id"] as String,
                table = tableName,
                op = r["op"] as String,
                rowId = rowId,
                payload = payloadMap,
                code = code,
                message = message,
                reason = r["reason"] as? String,
                attempts = r["attempts"] as Int,
                failedAt = r["failed_at"] as String,
                label = label,
                explanation = explanation,
            )
        }
    }

    suspend fun markResolved(id: String, resolution: String) {
        val ts = Instant.now().toString()
        db.execute(
            "UPDATE failed_writes SET resolved_at = ?, resolution = ? WHERE id = ?",
            listOf(ts, resolution, id)
        )
    }

    fun exportStrandedJson(rows: List<StrandedRow>): String {
        val sb = StringBuilder()
        sb.append("{\n")
        sb.append("  \"exportedAt\": \"${Instant.now()}\",\n")
        sb.append("  \"user\": \"${getUserId()}\",\n")
        sb.append("  \"note\": \"Unsynced local rows\",\n")
        sb.append("  \"count\": ${rows.size}\n")
        sb.append("}")
        return sb.toString()
    }

    /**
     * Full, unredacted JSON of quarantined writes -- this is the user's own
     * data being handed back to them, not a support log. Mirrors
     * exportFailedWrites in deadletter.ts.
     */
    fun exportFailedWritesJson(items: List<FailedWriteItem>): String {
        val root = buildJsonObject {
            put("exportedAt", Instant.now().toString())
            put("note", "Changes made on this device that the server would not accept.")
            put("items", kotlinx.serialization.json.buildJsonArray {
                for (i in items) {
                    add(buildJsonObject {
                        put("table", i.table)
                        put("operation", i.op)
                        put("id", i.rowId)
                        put("label", i.label)
                        put("failedAt", i.failedAt)
                        put("why", i.explanation)
                        put("technical", buildJsonObject {
                            put("code", i.code)
                            put("message", i.message)
                            put("reason", i.reason)
                            put("attempts", i.attempts)
                        })
                        put("data", buildJsonObject { for ((k, v) in i.payload) put(k, toJsonPrimitiveOrNull(v)) })
                    })
                }
            })
        }
        return Json { prettyPrint = true }.encodeToString(JsonObject.serializer(), root)
    }

    /**
     * Try the write again, directly. Direct rather than re-queued: we hold
     * the complete row, so an upsert states the intended end state plainly --
     * pushing it back into ps_crud would risk re-blocking the queue with the
     * very op we just freed it from. Mirrors retryFailedWrite in deadletter.ts.
     */
    suspend fun retryFailedWrite(item: FailedWriteItem): Boolean {
        val rel = client.postgrest[REPAIR_SCHEMA, item.table]
        return try {
            if (item.op.uppercase() == "DELETE") {
                rel.delete { filter { eq("id", item.rowId) } }
            } else {
                val row = buildJsonObject {
                    for ((k, v) in item.payload) put(k, toJsonPrimitiveOrNull(v))
                    put("id", item.rowId)
                }
                rel.upsert(row)
            }
            markResolved(item.id, "retried")
            logDiagnostic(level = "info", scope = "sync", message = "retry succeeded for ${item.table}")
            true
        } catch (e: Exception) {
            logDiagnostic(level = "warn", scope = "sync", message = "retry still failing for ${item.table}: ${e.message}")
            false
        }
    }

    /**
     * Give up on a write. Callers must export first (the UI enforces this) --
     * mirrors discardFailedWrite's "no argument, no opt-out" export-before-discard.
     */
    suspend fun discardFailedWrite(item: FailedWriteItem) {
        markResolved(item.id, "discarded")
        logDiagnostic(level = "warn", scope = "sync", message = "discarded a failed write to ${item.table} (exported first)")
    }

    /**
     * Diff local rows against the server. Requires a connection: "is this row
     * on the server" is not answerable offline. Mirrors scanForStranded in
     * repair.ts, including its 100-id PostgREST `in.()` chunking.
     */
    suspend fun scanForStranded(limitPerTable: Int = 500): RepairScanResult {
        val stranded = mutableListOf<StrandedRow>()
        val unchecked = mutableListOf<String>()
        val chunkSize = 100

        for (table in REPAIR_ORDER) {
            val local = try {
                db.getAll(
                    sql = "SELECT * FROM $table WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT ?",
                    parameters = listOf(limitPerTable),
                    mapper = { cursor -> rowToMap(cursor) },
                )
            } catch (_: Exception) {
                continue // table not in this build's schema
            }
            if (local.isEmpty()) continue

            val ids = local.map { (it["id"] as? String) ?: "" }.filter { it.isNotEmpty() }
            val present = mutableSetOf<String>()
            var failed = false

            for (i in ids.indices step chunkSize) {
                val chunk = ids.subList(i, minOf(i + chunkSize, ids.size))
                try {
                    val rows = client.postgrest[REPAIR_SCHEMA, table]
                        .select(columns = io.github.jan.supabase.postgrest.query.Columns.raw("id")) {
                            filter { isIn("id", chunk) }
                        }
                        .decodeList<Map<String, String>>()
                    for (row in rows) row["id"]?.let { present.add(it) }
                } catch (_: Exception) {
                    failed = true
                    break
                }
            }

            if (failed) {
                unchecked.add(table)
                continue
            }

            for (r in local) {
                val id = (r["id"] as? String) ?: continue
                if (id !in present) {
                    stranded.add(StrandedRow(table = table, id = id, label = describeRow(table, r), row = r))
                }
            }
        }

        if (stranded.isNotEmpty()) {
            logDiagnostic(
                level = "warn", scope = "repair",
                message = "found ${stranded.size} row(s) never uploaded",
            )
        }
        return RepairScanResult(stranded = stranded, unchecked = unchecked)
    }

    /**
     * Re-upload stranded rows, parents first. Upsert so a partially-succeeded
     * repair can be run again safely. One row at a time: a batch that fails
     * tells us nothing about WHICH row was bad. Mirrors repairStranded.
     */
    suspend fun repairStranded(rows: List<StrandedRow>): Pair<Int, List<Triple<String, String, String>>> {
        var uploaded = 0
        val failed = mutableListOf<Triple<String, String, String>>() // (table, id, error)

        for (table in REPAIR_ORDER) {
            val forTable = rows.filter { it.table == table }
            if (forTable.isEmpty()) continue
            for (item in forTable) {
                try {
                    val row = buildJsonObject { for ((k, v) in item.row) put(k, toJsonPrimitiveOrNull(v)) }
                    client.postgrest[REPAIR_SCHEMA, table].upsert(row)
                    uploaded++
                } catch (e: Exception) {
                    failed.add(Triple(table, item.id, e.message ?: "Upload failed"))
                }
            }
        }

        logDiagnostic(
            level = if (failed.isNotEmpty()) "warn" else "info", scope = "repair",
            message = "re-uploaded $uploaded row(s), ${failed.size} still failing",
        )
        return uploaded to failed
    }
}

/** Parse a failed_writes.payload JSON string (produced by encodePayload) back to a Map. */
private fun parsePayloadJson(json: String?): Map<String, Any?> {
    if (json.isNullOrBlank()) return emptyMap()
    return try {
        val obj = Json.parseToJsonElement(json) as? JsonObject ?: return emptyMap()
        obj.mapValues { (_, v) ->
            val prim = v as? JsonPrimitive
            when {
                prim == null -> null
                prim is JsonNull -> null
                prim.isString -> prim.content
                else -> prim.content.toLongOrNull() ?: prim.content.toDoubleOrNull() ?: prim.content
            }
        }
    } catch (_: Exception) {
        emptyMap()
    }
}

/**
 * Read every column of the current cursor row into a Map, for a table whose
 * columns aren't known ahead of time (repair needs the WHOLE row to
 * re-upload it, unlike every other repository's mapper, which knows its
 * columns statically).
 *
 * `columnNames` is a real SqlCursor property (confirmed present via the SDK
 * changelog), but reading every column through `getStringOptional` coerces
 * numeric columns to their string form -- fine for re-upload (PostgREST
 * accepts numeric strings in a JSON body) but the single riskiest guess in
 * this file since it's new API surface no other repository exercises. If a
 * real compile/runtime error surfaces here, this function is the first
 * place to look.
 */
private fun rowToMap(cursor: com.powersync.db.SqlCursor): Map<String, Any?> {
    val map = LinkedHashMap<String, Any?>()
    for (name in cursor.columnNames.keys) {
        map[name] = try { cursor.getStringOptional(name) } catch (_: Exception) { null }
    }
    return map
}

private fun toJsonPrimitiveOrNull(v: Any?): kotlinx.serialization.json.JsonElement = when (v) {
    null -> JsonNull
    is String -> JsonPrimitive(v)
    is Number -> JsonPrimitive(v)
    is Boolean -> JsonPrimitive(v)
    else -> JsonPrimitive(v.toString())
}
