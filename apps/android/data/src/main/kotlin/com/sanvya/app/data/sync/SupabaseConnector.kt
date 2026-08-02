package com.sanvya.app.data.sync

/**
 * SupabaseConnector — bridges PowerSync to Supabase on Android.
 *
 * Ported from packages/db/src/connector.ts (P2.2a).
 *
 * - fetchCredentials: gives PowerSync the current Supabase JWT.
 * - uploadData: flushes the local write queue to Postgres, preserving order.
 *
 * Financial-safety note: writes are applied in queue order and retried on
 * failure; because the ledger is append-only and server-authoritative, replays
 * are safe (no in-place money mutation).
 *
 * Coalescing: consecutive ops sharing the same table + op type are batched
 * into a single PostgREST request (array upsert / id IN (...) delete). This
 * turns a bulk import of N transactions into a handful of requests while
 * preserving queue ordering (we never reorder across tables, so FK ordering
 * like account-before-txn is untouched). PATCH stays per-row because two
 * updates to the same table can touch different columns.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.connectors.PowerSyncBackendConnector
import com.powersync.connectors.PowerSyncCredentials
import com.powersync.db.crud.CrudEntry
import com.powersync.db.crud.UpdateType
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
// P2.3 diagnostics wiring. Unlike Classification/FailureDetails (used only
// via inferred chained member access on same-package Quarantine.kt types,
// which needs no import), these are bare top-level identifiers / a type
// named directly, from OTHER packages -- Kotlin, like Swift, requires each
// file to import what it names explicitly, regardless of what a same-package
// sibling file already imports.
import com.sanvya.app.data.diagnostics.logDiagnostic
import com.sanvya.app.domain.diagnostics.DetailValue
import com.sanvya.app.domain.diagnostics.LOG_LEVEL_ERROR
import com.sanvya.app.domain.diagnostics.LOG_LEVEL_WARN
import com.sanvya.app.domain.syncpolicy.FAILURE_CLASS_PERMANENT

/** Postgres schema that holds all Sanvya tables. */
const val DB_SCHEMA = "pocketcare"

/**
 * Optional sink for structured sync failures.
 *
 * A module-level hook rather than a constructor option, so this package stays
 * free of any dependency on the app's diagnostics layer. The app opts in by
 * calling setSyncDiagnosticSink at startup.
 */
data class SyncDiagnostic(
    val table: String,
    val op: String,
    val rows: Int,
    val code: String? = null,
    val message: String? = null,
    val hint: String? = null,
    val cls: String? = null,
    val attempts: Int? = null,
    val quarantined: Boolean? = null,
)

private var diagnosticSink: ((SyncDiagnostic) -> Unit)? = null

fun setSyncDiagnosticSink(fn: ((SyncDiagnostic) -> Unit)?) {
    diagnosticSink = fn
}

/**
 * FAULT INJECTION — dev only.
 *
 * Makes unreachable paths reachable: force uploads to a chosen table to fail
 * with a chosen SQLSTATE, and exercise the full classify → retry → quarantine
 * → recover path deliberately. Identical to connector.ts's fault injection.
 */
data class FaultInjection(
    /** Unqualified table name, or "*" for everything. */
    val table: String,
    /** SQLSTATE to report, e.g. "42501" (RLS) or "23503" (foreign key). */
    val code: String,
    val message: String? = null,
    val status: Int? = null,
)

private var fault: FaultInjection? = null

/** Install (or clear) a fault. No-op in production builds — see the app's gate. */
fun setFaultInjection(f: FaultInjection?) {
    fault = f
}

fun getFaultInjection(): FaultInjection? = fault

private fun injectedErrorFor(table: String): FailureDetails? {
    val f = fault ?: return null
    val bare = if (table.contains(".")) table.substringAfterLast(".") else table
    if (f.table != "*" && f.table != bare) return null
    return FailureDetails(
        code = f.code,
        message = f.message ?: "injected fault (${f.code}) for $bare",
        status = f.status,
    )
}

/**
 * Keys we've recorded a failure for this session (in-memory; cleared on
 * success). Only ops we know have failed can have a counter.
 */
private val bumped = mutableSetOf<String>()

private fun reportSyncDiagnostic(d: SyncDiagnostic) {
    try {
        diagnosticSink?.invoke(d)
    } catch (_: Exception) {
        // Diagnostics must never make a sync failure worse than it already is.
    }
}

/**
 * Convert a PowerSync CrudEntry to our CrudOpSummary for quarantine tracking.
 * Reads the op's data map and serialises it to JSON for dead-letter storage.
 *
 * opData.typed, NOT opData.toMap(): CrudEntry.opData's real type is
 * `SqliteRow?` (confirmed via powersync-kotlin 1.13.0's real source,
 * CrudEntry.kt/SqliteRow.kt at the pinned tag), and SqliteRow itself
 * implements `Map<String, String?>` — every value stringified, kept only
 * for backwards compatibility. `opData?.toMap()` copies that same
 * stringified view; because Kotlin's Map is declared `out V` (covariant),
 * assigning a `Map<String, String?>` into a `Map<String, Any?>`-typed val
 * compiles with ZERO warning or error, so this shipped silently wrong.
 * `.typed: Map<String, Any?>` is SqliteRow's real typed accessor (Int/
 * Double/Boolean/String) — mirrors the exact fix applied to iOS's
 * SupabaseConnector.swift (opData vs opDataTyped) after finding the same
 * class of bug there. See CAUTION below `toJsonPrimitive` for a real
 * constraint of `.typed` itself (Int, never Long, for numeric columns).
 */
private fun CrudEntry.toOpSummary(): CrudOpSummary {
    val rawData: Map<String, Any?> = opData?.typed ?: emptyMap()
    return CrudOpSummary(
        // clientId is a non-nullable Int in the real SDK (confirmed via
        // CrudEntry.kt source) — the `?.` here is a harmless-but-misleading
        // unnecessary safe call, not a bug; kept as `.toLong()` since
        // CrudOpSummary.clientId is Long?.
        clientId = clientId.toLong(),
        table = table,
        op = op.name,
        id = id,
        payloadJson = encodePayload(rawData),
    )
}

/**
 * Convert an opData value (Any?) to a kotlinx.serialization JsonElement.
 * Used to build JsonObject payloads for supabase-kt's Serializable PostgREST API.
 *
 * CAUTION (real constraint, confirmed via SqliteRow.kt source): `.typed`'s
 * numeric parser (`jsonNumberOrBoolean()`) always produces Kotlin `Int`
 * (32-bit) for non-decimal numeric strings, never `Long` — there is no
 * bigint-range path. A synced integer column whose value exceeds
 * Int32.MAX_VALUE (~2.15 billion) would silently overflow when read via
 * `.typed`. Money is stored as integer minor units (golden rule #1) and
 * unlikely to hit that range in practice, but this is an SDK-level
 * limitation, not something fixable from our side — flag for review if a
 * future schema ever needs a genuinely bigint-range synced column.
 */
private fun toJsonPrimitive(v: Any?): kotlinx.serialization.json.JsonElement = when (v) {
    null -> JsonNull
    is String -> JsonPrimitive(v)
    is Number -> JsonPrimitive(v)
    is Boolean -> JsonPrimitive(v)
    else -> JsonPrimitive(v.toString())
}

/** Extract FailureDetails from a PostgREST or network exception. */
private fun extractFailure(e: Throwable): FailureDetails = FailureDetails(
    code = (e as? io.github.jan.supabase.exceptions.RestException)?.error,
    message = e.message,
    status = (e as? io.github.jan.supabase.exceptions.HttpRequestException)?.let {
        // supabase-kt wraps HTTP errors; extract status if available
        null // status is in the cause chain — best effort
    },
)

class SupabaseConnector(
    private val client: SupabaseClient,
    private val powerSyncUrl: String,
    /** Schema the tables live in; must be an Exposed schema in Supabase settings. */
    private val schema: String = DB_SCHEMA,
) : PowerSyncBackendConnector() {

    override suspend fun fetchCredentials(): PowerSyncCredentials? {
        val session = client.auth.currentSessionOrNull() ?: return null
        return PowerSyncCredentials(
            endpoint = powerSyncUrl,
            token = session.accessToken,
        )
    }

    override suspend fun uploadData(database: PowerSyncDatabase) {
        val batch = database.getCrudBatch() ?: return

        val ops: List<CrudEntry> = batch.crud

        // Track which keys gained a bump counter so we can clear them on success.
        val bumpedThisRun = mutableSetOf<String>()

        var i = 0
        while (i < ops.size) {
            val op = ops[i]
            // 2-arg operator get(schema, table) — NOT the 1-arg get(table), which uses
            // Postgrest.Config.defaultSchema ("public" unless configured at client
            // construction, which nothing here does). Golden rule #3 (CLAUDE.md):
            // every call must be schema-qualified or PostgREST 404s. Verified against
            // supabase-kt's real Postgrest.kt source (github.com/supabase-community/
            // supabase-kt) before using this form — `operator fun get(schema: String,
            // table: String): PostgrestQueryBuilder` is a real overload, not a guess.
            val rel = client.postgrest[schema, op.table]

            // Extend the run while the next op targets the same table + op type.
            // PATCH always stays per-row (different columns may be touched).
            var j = i + 1
            while (
                j < ops.size &&
                ops[j].table == op.table &&
                ops[j].op == op.op &&
                op.op != UpdateType.PATCH
            ) {
                j++
            }
            val run = ops.subList(i, j)

            // Fault injection short-circuits before any real network call.
            val injected = injectedErrorFor("$schema.${op.table}")

            var failure: FailureDetails? = injected

            if (failure == null) {
                try {
                    when (op.op) {
                        UpdateType.PUT -> {
                            // .typed, not the bare Map<String, String?> — see
                            // the comment on toOpSummary above.
                            val rows: List<JsonObject> = run.map { entry ->
                                buildJsonObject {
                                    entry.opData?.typed?.forEach { (k, v) -> put(k, toJsonPrimitive(v)) }
                                    put("id", entry.id)
                                }
                            }
                            rel.upsert(rows)
                        }
                        UpdateType.DELETE -> {
                            val ids = run.map { it.id }
                            rel.delete { filter { isIn("id", ids) } }
                        }
                        UpdateType.PATCH -> {
                            val data: JsonObject = buildJsonObject {
                                op.opData?.typed?.forEach { (k, v) -> put(k, toJsonPrimitive(v)) }
                            }
                            rel.update(data) { filter { eq("id", op.id) } }
                        }
                    }
                } catch (e: Exception) {
                    failure = extractFailure(e)
                }
            }

            if (failure != null) {
                val summaries = run.map { it.toOpSummary() }
                val verdict = handleUploadFailure(
                    db = database,
                    run = summaries,
                    failure = failure,
                    onBump = { k ->
                        bumped.add(k)
                        bumpedThisRun.add(k)
                    },
                )

                android.util.Log.e(
                    "SanvyaSync",
                    "[Sanvya sync] upload failed for $schema.${op.table} " +
                        "(${op.op}, ${run.size} row(s), attempt ${verdict.attempts}, " +
                        "${verdict.classification.cls})" +
                        if (verdict.quarantined) " — moved to Problems syncing" else "",
                )

                // P2.3: feed the already-ported diagnostics domain (P1.6a) so a
                // future "share diagnostics" flow has a redacted, human-readable
                // record. Permanent (about to be/already quarantined) is ERROR;
                // transient (still retrying) is WARN. makeEntry redacts the raw
                // failure.message itself -- safe to pass straight through.
                logDiagnostic(
                    level = if (verdict.classification.cls == FAILURE_CLASS_PERMANENT) LOG_LEVEL_ERROR else LOG_LEVEL_WARN,
                    scope = "sync",
                    message = failure.message ?: "Upload failed for ${op.table}",
                    detail = DetailValue.Obj(
                        linkedMapOf(
                            "table" to DetailValue.Str("$schema.${op.table}"),
                            "op" to DetailValue.Str(op.op.name),
                            "rows" to DetailValue.IntNum(run.size.toLong()),
                            "attempts" to DetailValue.IntNum(verdict.attempts.toLong()),
                            "cls" to DetailValue.Str(verdict.classification.cls),
                            "quarantined" to DetailValue.Bool(verdict.quarantined),
                            "code" to (failure.code?.let { DetailValue.Str(it) } ?: DetailValue.Null),
                        ),
                    ),
                )

                reportSyncDiagnostic(
                    SyncDiagnostic(
                        table = "$schema.${op.table}",
                        op = op.op.name,
                        rows = run.size,
                        code = failure.code,
                        message = failure.message,
                        cls = verdict.classification.cls,
                        attempts = verdict.attempts,
                        quarantined = verdict.quarantined,
                    ),
                )

                if (verdict.quarantined) {
                    i = j
                    continue
                }
                throw Exception(failure.message ?: "Upload failed for ${op.table}")
            }

            // Succeeded — clear retry counters for this run so a later, unrelated
            // failure on the same row starts from zero.
            for (entry in run) {
                val key = opKey(entry.table, entry.op.name, entry.id)
                if (bumped.remove(key)) {
                    clearAttempts(database, key)
                }
            }
            i = j
        }

        // null, not "" — matches PowerSync's own official Kotlin Supabase connector
        // (github.com/powersync-ja/powersync-kotlin, integrations/supabase), which calls
        // transaction.complete(null); an empty string is a real (if likely harmless)
        // writeCheckpoint value, not "no checkpoint".
        batch.complete(null)
    }
}
