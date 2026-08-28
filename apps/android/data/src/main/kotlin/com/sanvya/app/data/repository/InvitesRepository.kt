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
import kotlinx.serialization.json.booleanOrNull
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
 * Ported from `createInvite` + `acceptInvite` + `edgeFnMessage` in
 * `apps/web/src/splits/write.ts`. Mirrors iOS's InvitesRepository.swift.
 */
class InvitesRepository(private val client: SupabaseClient) {

    /**
     * Invite someone to a group.
     *
     * Web's own summary, which is the whole contract: "If `email` belongs to a
     * registered Sanvya user they're added to the group directly; otherwise a
     * shareable invite link is returned. With no email, always returns a link."
     *
     * The two outcomes are genuinely different things to tell the user, which
     * is why [InviteResult] keeps them apart rather than returning a string:
     * "added" means they are in the group now, "link" means somebody has to
     * send it on.
     */
    suspend fun createInvite(groupId: String, email: String? = null): InviteResult {
        val body = buildJsonObject {
            put("group_id", groupId)
            // Web sends `email: undefined` for a general share link, which
            // JSON.stringify DROPS. An explicit null is a different request, so
            // the key is omitted rather than nulled.
            if (!email.isNullOrBlank()) put("email", email.trim())
        }
        val json = invokeJson("split-invite", body, INVITE_CREATE_FAILURE)
        json["error"]?.jsonPrimitive?.contentOrNull?.let { throw InviteError(it) }

        val added = json["added"]?.jsonPrimitive?.booleanOrNull ?: false
        if (added) {
            return InviteResult(
                added = true,
                already = json["already"]?.jsonPrimitive?.booleanOrNull ?: false,
                name = json["name"]?.jsonPrimitive?.contentOrNull,
            )
        }
        // Web falls back to building the link from the token and its own
        // origin. A phone has no origin, so the SERVER's link is required --
        // and if it is missing that is a real failure, not something to paper
        // over with a URL this app invented.
        val link = json["link"]?.jsonPrimitive?.contentOrNull
            ?: throw InviteError(INVITE_CREATE_FAILURE)
        return InviteResult(added = false, link = link)
    }

    /**
     * Accept an invite by token.
     *
     * @return the joined group's id.
     * @throws InviteError with a message worth showing the user.
     */
    suspend fun acceptInvite(token: String): String {
        val body = buildJsonObject { put("token", token) }
        val json = invokeJson("split-invite-accept", body, INVITE_GENERIC_FAILURE)
        json["error"]?.jsonPrimitive?.contentOrNull?.let { throw InviteError(it) }
        return json["group_id"]?.jsonPrimitive?.contentOrNull
            ?: throw InviteError(INVITE_GENERIC_FAILURE)
    }

    /**
     * One Edge Function call, with web's error unwrapping.
     *
     * Extracted when `createInvite` arrived and needed the identical handling.
     * The unwrapping is the part worth keeping in one place: supabase-kt
     * collapses a non-2xx into an exception whose message is the raw response
     * body, and the function always answers with `{ error }`, so the real
     * reason is in there -- the same unwrapping web's `edgeFnMessage()` does,
     * for the same reason.
     */
    private suspend fun invokeJson(
        function: String,
        body: JsonObject,
        genericFailure: String,
    ): JsonObject = try {
        val response = client.functions.invoke(
            function = function,
            body = body,
            // supabase-kt's own doc comment on this overload says the JSON
            // content type has to be set explicitly, so it is passed rather
            // than assumed -- same as UpiRepository.
            headers = Headers.build { append(HttpHeaders.ContentType, "application/json") },
        )
        Json.parseToJsonElement(response.bodyAsText()).jsonObject
    } catch (e: RestException) {
        val parsed = runCatching { Json.parseToJsonElement(e.message.orEmpty()).jsonObject }.getOrNull()
        val msg = parsed?.get("error")?.jsonPrimitive?.contentOrNull
            ?: statusMessage(e.message.orEmpty())
            ?: genericFailure
        throw InviteError(msg)
    } catch (e: Exception) {
        throw InviteError(e.message ?: genericFailure)
    }
}

/**
 * What `split-invite` answered.
 *
 * Exactly one side is set: [added] with an optional [name], or a [link].
 * [already] means they were in the group before this call -- web reports that
 * separately because "added" and "was already there" are different news.
 */
data class InviteResult(
    val added: Boolean,
    val already: Boolean = false,
    val name: String? = null,
    val link: String? = null,
)

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
internal const val INVITE_CREATE_FAILURE = "Could not create the invite."

/** A failure worth putting on screen, with web's own wording. */
class InviteError(message: String) : Exception(message)
