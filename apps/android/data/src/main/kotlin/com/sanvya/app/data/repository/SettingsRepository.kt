package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.powersync.db.getLong
import com.powersync.db.getStringOptional
import com.sanvya.app.data.auth.isGuest as authIsGuest
import com.sanvya.app.data.diagnostics.QueuedOp
import com.sanvya.app.data.diagnostics.discardOps
import com.sanvya.app.data.diagnostics.inspectQueue
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * The Settings screen's data access.
 *
 * This exists because `SettingsViewModel` used to inject `SupabaseClient` and
 * `PowerSyncDatabase` directly from `:app` and call `client.auth`,
 * `client.postgrest` and `db.getOptional` itself. That never compiled — `:data`
 * declares those libraries as `implementation`, so they are not on `:app`'s
 * classpath — and it was a layering break regardless: every other screen
 * reaches its data through a repository. Fixing it by promoting those
 * dependencies to `api` would have made the build pass while making the
 * architecture worse, so the calls moved down here instead.
 *
 * Everything is a plain suspend function returning plain types; nothing about
 * PowerSync or Supabase escapes this file.
 */
class SettingsRepository(
    private val client: SupabaseClient,
    private val db: PowerSyncDatabase,
) {

    /** Signed-in user, as the Settings screen needs it. Null when signed out. */
    data class Session(
        val email: String?,
        val isGuest: Boolean,
        val username: String,
        /** Epoch millis; null when the SDK does not surface it. */
        val createdAtMs: Long?,
    )

    data class SyncSnapshot(val connected: Boolean, val lastSyncedAt: String?)

    suspend fun currentSession(): Session? {
        val user = client.auth.currentSessionOrNull()?.user ?: return null
        val createdAtMs = try {
            user.createdAt?.toEpochMilliseconds()
        } catch (_: Exception) {
            null
        }
        return Session(
            email = user.email,
            isGuest = authIsGuest(client),
            username = (user.userMetadata?.get("username") as? JsonPrimitive)?.content ?: "",
            createdAtMs = createdAtMs,
        )
    }

    suspend fun updateUsername(name: String) {
        client.auth.updateUser { data = buildJsonObject { put("username", name) } }
    }

    /** `profiles.gender` / `profiles.country`, or null when no row exists yet. */
    suspend fun loadProfile(userId: String): Pair<String, String>? = db.getOptional(
        sql = "SELECT gender, country FROM profiles WHERE id = ? LIMIT 1",
        parameters = listOf(userId),
        mapper = { c -> (c.getStringOptional("gender") ?: "") to (c.getStringOptional("country") ?: "") },
    )

    /**
     * Only `connected` and `lastSyncedAt` — the two `SyncStatus` fields
     * verified against the SDK's own docs. `dataFlowStatus.uploading/
     * downloading` exist but their exact Kotlin shape is unverified, so
     * "waiting to upload" comes from [crudQueueDepth] instead, which is what
     * web's DiagnosticsPanel also falls back to.
     */
    fun syncSnapshot(): SyncSnapshot {
        val status = db.currentStatus
        return SyncSnapshot(connected = status.connected, lastSyncedAt = status.lastSyncedAt?.toString())
    }

    /** Rows still waiting in PowerSync's upload queue. */
    suspend fun crudQueueDepth(): Int? = db.getOptional(
        sql = "SELECT COUNT(*) AS n FROM ps_crud",
        parameters = emptyList(),
        mapper = { c -> c.getLong("n").toInt() },
    )

    suspend fun queueOps(failingTable: String?): List<QueuedOp> = inspectQueue(db, failingTable)

    /** Drops orphaned rows from the upload queue. Returns how many went. */
    suspend fun discardQueueOps(ids: List<Long>): Int = discardOps(db, ids)

    /** `profiles` upsert, split so the caller keeps its own "does it exist yet" state. */
    suspend fun updateProfile(userId: String, gender: String?, country: String?) =
        updateRow(db, "profiles", userId, mapOf("gender" to gender, "country" to country))

    suspend fun insertProfile(userId: String, gender: String?, country: String?) =
        insertRow(db, "profiles", userId, mapOf("id" to userId, "gender" to gender, "country" to country))

    /**
     * Server-side account deletion, then a local wipe.
     *
     * `Postgrest.rpc()` takes no schema argument (only `from(schema, table)`
     * does) — verified against supabase-kt's own source: `RpcRequestBuilder`
     * extends `PostgrestRequestBuilder`, which exposes a mutable `schema`
     * defaulting to `config.defaultSchema` ("public", since DataModule's client
     * never sets one). So the override happens inside the `request` lambda.
     *
     * The schema is `pocketcare`, not `sanvya`: the product was renamed but
     * `0001_init.sql` created — and every migration since has used — the
     * `pocketcare` schema. Golden rule 3 in PROJECT_REFERENCE.md and CLAUDE.md
     * said `sanvya` until 2026-08-23; both were corrected.
     */
    suspend fun deleteAccountOnServer() {
        client.postgrest.rpc(
            function = "delete_user_account",
            parameters = buildJsonObject { put("orphan_records", false) },
            request = { schema = "pocketcare" },
        )
    }

    /** Best-effort local wipe. Sign-out proceeds even if this fails. */
    suspend fun clearLocalDatabase() {
        db.disconnectAndClear()
    }
}
