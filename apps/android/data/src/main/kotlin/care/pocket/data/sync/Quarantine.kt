package care.pocket.data.sync

/**
 * Dead-letter queue for uploads the server will never accept.
 *
 * Ported from packages/db/src/quarantine.ts (P2.2a).
 *
 * THE PROBLEM THIS SOLVES: PowerSync uploads ps_crud strictly in order and
 * retries forever. That is correct for a network blip and catastrophic for a
 * rejected write — an op that can never succeed blocks every write queued
 * behind it, indefinitely.
 *
 * After MAX_PERMANENT_ATTEMPTS, a failure classified permanent is **moved**,
 * not deleted. The full payload goes to the local-only `failed_writes` table,
 * the op leaves `ps_crud`, and the queue drains.
 *
 * Local-only on purpose: a synced quarantine table would put its own rows into
 * the queue it exists to unblock.
 *
 * Database schema for the local-only tables (must be present in the app's
 * PowerSync schema as local-only tables):
 *   sync_attempts(id TEXT PRIMARY KEY, attempts INTEGER, last_code TEXT, updated_at TEXT)
 *   failed_writes(id TEXT PRIMARY KEY, table_name TEXT, op TEXT, row_id TEXT,
 *                 payload TEXT, code TEXT, message TEXT, cls TEXT, reason TEXT,
 *                 attempts INTEGER, failed_at TEXT, resolved_at TEXT, resolution TEXT)
 */

import com.powersync.PowerSyncDatabase
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import care.pocket.domain.syncpolicy.Classification
import care.pocket.domain.syncpolicy.FailureInput
import care.pocket.domain.syncpolicy.classifyFailure
import care.pocket.domain.syncpolicy.shouldQuarantine

/**
 * Stable identity for one logical write, used as the retry-counter key.
 *
 * Keyed on table + op + row id (not ps_crud row id), so the count survives
 * PowerSync re-deriving the queue and an app restart.
 *
 * Identical to quarantine.ts: opKey(table, op, rowId) = "${table}|${op}|${rowId}"
 */
fun opKey(table: String, op: String, rowId: String): String =
    "$table|$op|$rowId"

/**
 * Read and increment the attempt count for an op. Missing row means attempt 1.
 *
 * NOT INSERT OR REPLACE: PowerSync exposes every table as a VIEW backed by
 * INSTEAD OF triggers, and SQLite cannot UPSERT into a view. The read above
 * already tells us which branch we need — identical workaround to the TS source.
 */
suspend fun bumpAttempts(
    db: PowerSyncDatabase,
    key: String,
    code: String?,
): Int {
    return try {
        val existing = db.getOptional(
            sql = "SELECT attempts FROM sync_attempts WHERE id = ?",
            parameters = listOf(key),
        ) { cursor ->
            cursor.getLong(0)
        }
        val attempts = ((existing ?: 0L) + 1L).toInt()
        val now = java.time.Instant.now().toString()
        if (existing != null) {
            db.execute(
                sql = "UPDATE sync_attempts SET attempts = ?, last_code = ?, updated_at = ? WHERE id = ?",
                parameters = listOf(attempts, code, now, key),
            )
        } else {
            db.execute(
                sql = "INSERT INTO sync_attempts (id, attempts, last_code, updated_at) VALUES (?, ?, ?, ?)",
                parameters = listOf(key, attempts, code, now),
            )
        }
        attempts
    } catch (_: Exception) {
        // If the counter table is unavailable (older local schema), report
        // attempt 1 so nothing is quarantined on the strength of a broken
        // counter. Identical safety valve as the TS source.
        1
    }
}

suspend fun clearAttempts(db: PowerSyncDatabase, key: String) {
    try {
        db.execute(
            sql = "DELETE FROM sync_attempts WHERE id = ?",
            parameters = listOf(key),
        )
    } catch (_: Exception) {
        /* best effort */
    }
}

/**
 * Summary of a single CRUD entry, extracted from PowerSync's CrudEntry before
 * any async I/O. Holding our own struct prevents SDK type leakage into the
 * quarantine layer and makes the quarantine logic testable without PowerSync.
 */
data class CrudOpSummary(
    /** ps_crud row id (clientId) — stable across retries; null if unavailable. */
    val clientId: Long?,
    val table: String,
    val op: String,
    val id: String,
    /** JSON-serialised payload for the dead-letter entry. */
    val payloadJson: String,
)

/** Failure info extracted from an upload exception. */
data class FailureDetails(
    val code: String? = null,
    val message: String? = null,
    val status: Int? = null,
)

/** Return value from handleUploadFailure. */
data class UploadFailureResult(
    val quarantined: Boolean,
    val classification: Classification,
    val attempts: Int,
)

/**
 * Move a run of failed ops out of the upload queue and into `failed_writes`.
 *
 * ORDER MATTERS: payload written first, queue entry deleted second. If the
 * process dies between the two, the op is still queued and will be quarantined
 * again on the next attempt — the delete-then-insert keyed on clientId makes a
 * repeat harmless. The reverse order would lose the write.
 *
 * Identical crash-safety semantics as quarantine.ts.
 */
suspend fun quarantineOps(
    db: PowerSyncDatabase,
    ops: List<CrudOpSummary>,
    failure: FailureDetails,
    classification: Classification,
    attempts: Int,
): Int {
    val now = java.time.Instant.now().toString()
    val ids = mutableListOf<Long>()

    for (op in ops) {
        val rowKey = op.clientId?.toString() ?: "${op.table}:${op.id}"
        // Delete-then-insert: PowerSync tables are VIEWs backed by INSTEAD OF
        // triggers — SQLite cannot UPSERT a view, so we read then branch.
        db.execute(sql = "DELETE FROM failed_writes WHERE id = ?", parameters = listOf(rowKey))
        db.execute(
            sql = """INSERT INTO failed_writes
                     (id, table_name, op, row_id, payload, code, message, cls, reason,
                      attempts, failed_at, resolved_at, resolution)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL)""",
            parameters = listOf(
                rowKey,
                op.table,
                op.op,
                op.id,
                op.payloadJson,
                failure.code,
                failure.message,
                classification.cls,
                classification.reason,
                attempts,
                now,
            ),
        )
        op.clientId?.let { ids.add(it) }
    }

    if (ids.isNotEmpty()) {
        db.execute(
            sql = "DELETE FROM ps_crud WHERE id IN (${ids.joinToString(",") { "?" }})",
            parameters = ids.map { it },
        )
    }
    return ops.size
}

/**
 * Decide what to do about a failed run, and do it.
 *
 * Returns quarantined=true when the run was moved to the dead-letter queue and
 * the caller should carry on with the rest of the batch; false when it should
 * rethrow so PowerSync retries.
 *
 * Mirrors handleUploadFailure in quarantine.ts exactly.
 */
suspend fun handleUploadFailure(
    db: PowerSyncDatabase,
    run: List<CrudOpSummary>,
    failure: FailureDetails,
    onBump: ((String) -> Unit)? = null,
): UploadFailureResult {
    val classification = classifyFailure(
        FailureInput(
            status = failure.status,
            code = failure.code,
            message = failure.message,
        ),
    )
    val head = run.first()
    val key = opKey(head.table, head.op, head.id)
    onBump?.invoke(key)
    val attempts = bumpAttempts(db, key, failure.code)

    if (!shouldQuarantine(classification, attempts)) {
        return UploadFailureResult(quarantined = false, classification = classification, attempts = attempts)
    }

    return try {
        quarantineOps(db, run, failure, classification, attempts)
        clearAttempts(db, key)
        UploadFailureResult(quarantined = true, classification = classification, attempts = attempts)
    } catch (_: Exception) {
        // If quarantining itself fails, retrying is strictly safer than
        // pretending we handled it — the alternative is dropping the write.
        UploadFailureResult(quarantined = false, classification = classification, attempts = attempts)
    }
}

/** Encode a Map<String, Any?> as a compact JSON string for storage. */
fun encodePayload(data: Map<String, Any?>?): String {
    if (data == null) return "{}"
    val jsonObject = buildJsonObject {
        for ((k, v) in data) {
            val elem: JsonElement = when (v) {
                null -> JsonNull
                is String -> JsonPrimitive(v)
                is Number -> JsonPrimitive(v)
                is Boolean -> JsonPrimitive(v)
                else -> JsonPrimitive(v.toString())
            }
            put(k, elem)
        }
    }
    return Json.encodeToString(jsonObject)
}
