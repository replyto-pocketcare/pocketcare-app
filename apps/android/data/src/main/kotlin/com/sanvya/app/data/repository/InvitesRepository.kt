package com.sanvya.app.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.functions.functions
import io.ktor.client.statement.bodyAsText
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * Split-group invites.
 *
 * Its own class rather than a method on [SplitsRepository], because
 * SplitsRepository's own header says invites are out of its scope and it is
 * right: everything there reads and writes the local PowerSync database, while
 * this is one HTTPS call to an Edge Function. Sharing a class would have meant
 * a repository that needs both a database and a Supabase client for one method.
 *
 * Ported from `acceptInvite` + `edgeFnMessage` in `apps/web/src/splits/write.ts`.
 * Mirrors iOS's InvitesRepository.swift.
 */
class InvitesRepository(private val client: SupabaseClient) {

    /**
     * Accept an invite by token.
     *
     * @return the joined group's id.
     * @throws InviteError with a message worth showing the user.
     */
    suspend fun acceptInvite(token: String): String {
        val body = buildJsonObject { put("token", token) }
        val json: JsonObject = try {
            val response = client.functions.invoke(
                function = "split-invite-accept",
                body = body,
                // supabase-kt's own doc comment on this overload says the JSON
                // content type has to be set explicitly, so it is passed rather
                // than assumed -- same as UpiRepository.
                headers = Headers.build { append(HttpHeaders.ContentType, "application/json") },
            )
            Json.parseToJsonElement(response.bodyAsText()).jsonObject
        } catch (e: RestException) {
            // supabase-kt collapses a non-2xx into an exception whose message is
            // the raw response body. The Edge Function always answers with
            // `{ error }`, so the real reason is in there -- this is the same
            // unwrapping web's edgeFnMessage() does for the same reason.
            val parsed = runCatching { Json.parseToJsonElement(e.message.orEmpty()).jsonObject }.getOrNull()
            val msg = parsed?.get("error")?.jsonPrimitive?.contentOrNull
                ?: statusMessage(e.message.orEmpty())
                ?: INVITE_GENERIC_FAILURE
            throw InviteError(msg)
        } catch (e: Exception) {
            throw InviteError(e.message ?: INVITE_GENERIC_FAILURE)
        }

        json["error"]?.jsonPrimitive?.contentOrNull?.let { throw InviteError(it) }
        return json["group_id"]?.jsonPrimitive?.contentOrNull
            ?: throw InviteError(INVITE_GENERIC_FAILURE)
    }
}

/**
 * Web's status-code fallbacks, kept for the case its own comment describes: a
 * non-2xx whose body is not the JSON we expect. The Edge Function always sends
 * `{ error }`, so in practice these never fire -- they exist because the day
 * one of them does, "Edge Function returned a non-2xx status code" is a dead
 * end for the user AND for whoever reads the bug report.
 */
private fun statusMessage(raw: String): String? = when {
    raw.contains("401") -> "Please sign in to accept this invite."
    raw.contains("404") -> "This invite link is invalid or has been removed."
    raw.contains("410") -> "This invite has expired or was already used."
    else -> null
}

internal const val INVITE_GENERIC_FAILURE = "Could not accept the invite."

/** A failure worth putting on screen, with web's own wording. */
class InviteError(message: String) : Exception(message)
