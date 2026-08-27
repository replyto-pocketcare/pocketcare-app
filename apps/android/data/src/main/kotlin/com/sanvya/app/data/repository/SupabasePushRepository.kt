package com.sanvya.app.data.repository

import com.sanvya.app.domain.repository.PushRepository
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.Serializable

@Serializable
data class PushSub(
    val user_id: String,
    val platform: String,
    val token: String,
    val last_seen: String,
)

/**
 * `push_subscriptions`, written straight to Postgres rather than through
 * PowerSync — the dispatcher reads it server-side and nothing on the phone ever
 * queries it back, so syncing a copy down would be pure cost.
 */
class SupabasePushRepository(
    private val client: SupabaseClient,
) : PushRepository {
    override suspend fun registerToken(token: String, platform: String, userId: String, lastSeenIso: String) {
        // `onConflict = "token"`, NOT "user_id, token".
        //
        // Migration 0048 adds exactly one unique constraint for native devices
        // -- `push_subscriptions_native_token_unique unique (token)`. Postgres
        // requires the ON CONFLICT target to MATCH a unique index, so the
        // composite target this used to send failed every single time with
        // "there is no unique or exclusion constraint matching the ON CONFLICT
        // specification". No device token has ever been stored by either native
        // app.
        //
        // A token identifying one device also has no business being
        // per-user-unique: if the same phone signs in as somebody else, the row
        // must MOVE, not duplicate, or the previous account keeps receiving
        // that device's alerts.
        //
        // The try/catch that used to wrap this and call printStackTrace() is
        // GONE, deliberately. It is what hid the bug above for the whole life
        // of the feature: the caller asked "did that work?" and was always told
        // yes. Callers handle the failure now.
        client.postgrest[SCHEMA, TABLE].upsert(
            PushSub(user_id = userId, platform = platform, token = token, last_seen = lastSeenIso),
        ) {
            onConflict = "token"
        }
    }

    override suspend fun unregisterToken(token: String) {
        client.postgrest[SCHEMA, TABLE].delete { filter { eq("token", token) } }
    }

    private companion object {
        const val SCHEMA = "pocketcare"
        const val TABLE = "push_subscriptions"
    }
}
