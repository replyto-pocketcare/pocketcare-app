package com.sanvya.app.data.repository

import com.sanvya.app.domain.repository.PushRepository
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.Serializable

@Serializable
data class PushSub(
    val user_id: String,
    val platform: String,
    val token: String
)

class SupabasePushRepository(
    private val client: SupabaseClient
) : PushRepository {
    override suspend fun registerToken(token: String, platform: String, userId: String) {
        val sub = PushSub(user_id = userId, platform = platform, token = token)
        try {
            client.postgrest["pocketcare.push_subscriptions"].upsert(sub) {
                onConflict = "user_id, token"
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
