package com.sanvya.app.domain.splits

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires Invite.kt into FunctionRegistry.
//
// A SPEC, not a capture: the rules live inside a React component in
// `groups/[id]/page.tsx` and cannot be imported, so these expectations were
// written by transcribing that block line by line and running the
// transcription. What they prove is that Android and iOS agree with each other
// and with what was read off web.
//
// The cases that earn their keep are the ones nobody would think to check:
//
//   * a connection with NO email is not offered, because it cannot be invited
//     by this route and offering it produces a row nobody can act on;
//   * a typed address that already belongs to a connection is NOT offered as a
//     new invitee -- web tests the whole connection list, not the filtered
//     matches, so their row appears instead of a duplicate;
//   * `Ravi@X.com` typed twice is one invitee, because the identity key
//     lowercases. Two would mean two links and two rows.
//
// Suggestions travel as KEYS rather than whole rows: the fixture pins WHICH
// connections survive and in what order, and echoing the inputs back would
// double the file and test nothing extra.

private const val DOMAIN = "splits-invite"

private fun JsonElement.toInvitee(): Invitee {
    val o = jsonObject
    return Invitee(
        id = o["id"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
        name = o.getValue("name").jsonPrimitive.content,
        email = o.getValue("email").jsonPrimitive.content,
    )
}

private fun JsonElement.toInvitees(): List<Invitee> = jsonArray.map { it.toInvitee() }

fun registerInviteVectors() {
    FunctionRegistry.register(DOMAIN, "inviteSuggestions") { input ->
        val o = input.jsonObject
        val result = inviteSuggestions(
            connections = o.getValue("connections").toInvitees(),
            memberIds = o.getValue("memberIds").jsonArray.map { it.jsonPrimitive.content },
            selected = o.getValue("selected").toInvitees(),
            query = o.getValue("query").jsonPrimitive.content,
        )
        JsonObject(
            mapOf(
                "suggestions" to JsonArray(result.suggestions.map { JsonPrimitive(inviteeKey(it)) }),
                "moreMatches" to JsonPrimitive(result.moreMatches),
                "canAddTypedEmail" to JsonPrimitive(result.canAddTypedEmail),
            ),
        )
    }

    FunctionRegistry.register(DOMAIN, "looksLikeEmail") { input ->
        JsonPrimitive(looksLikeEmail(input.jsonObject.getValue("text").jsonPrimitive.content))
    }

    FunctionRegistry.register(DOMAIN, "inviteeKey") { input ->
        JsonPrimitive(inviteeKey(input.jsonObject.getValue("invitee").toInvitee()))
    }

    FunctionRegistry.register(DOMAIN, "inviteeLabel") { input ->
        JsonPrimitive(inviteeLabel(input.jsonObject.getValue("invitee").toInvitee()))
    }
}
