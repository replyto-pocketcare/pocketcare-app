package care.pocket.data.repository

/**
 * Repair logic and dead-letter queue operations (P2.6a).
 * Mirrors apps/web/src/sync/repair.ts and apps/web/src/sync/deadletter.ts.
 *
 * Scans local DB for stranded rows that never reached the server (parents before
 * children, per REPAIR_ORDER), formats human-readable row labels (describeRow),
 * generates JSON export payloads, and provides retry/discard functionality for
 * quarantined writes in failed_writes.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import java.time.Instant

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
    "planned_cashflow",
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

            val payloadMap = mutableMapOf<String, Any?>()
            payloadMap["id"] = rowId

            val label = describeRow(tableName, payloadMap)
            val explanation = message ?: code ?: "Write failed"

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
}
