package com.sanvya.app.domain.syncstatus

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires SyncNotice.kt into FunctionRegistry.
//
// Hand-written rather than generated: web's `syncMessage()` returns English
// COPY, and the ports return a decision the screen then translates, so there is
// no single JS value to diff against. What the corpus pins instead is the
// classification -- which errors are swallowed as a network wobble and which
// reach the user -- because that is the part with a wrong answer in both
// directions (a swallowed schema error is silent data loss; a surfaced
// websocket blip is a strip nobody reads).

private const val DOMAIN = "sync-status"

/** Absent, JSON null and the JSON string "null" are all "no error". */
private fun optional(v: JsonElement?): String? =
    if (v == null || v is JsonNull) null else v.jsonPrimitive.content

fun registerSyncStatusVectors() {
    FunctionRegistry.register(DOMAIN, "syncNotice") { input ->
        val o: JsonObject = input.jsonObject
        val notice = syncNotice(
            online = o.getValue("online").jsonPrimitive.boolean,
            error = optional(o["error"]),
        )
        // Lowercase names, so the corpus reads as web's own tone strings rather
        // than as Kotlin enum constants.
        JsonPrimitive(notice.name.lowercase())
    }

    FunctionRegistry.register(DOMAIN, "isTransientSyncError") { input ->
        JsonPrimitive(isTransientSyncError(optional(input.jsonObject["error"])))
    }
}
