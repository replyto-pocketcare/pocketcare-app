package com.sanvya.app.domain.notifications

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires TimeAgo.kt into FunctionRegistry.
//
// Web's version lives in a page module and reads `Date.now()`, so it cannot be
// imported and called with a fixed clock. These vectors were generated from a
// transcription of it with the clock passed in, and they pin the SHAPE the port
// returns rather than web's English strings -- see TimeAgo.kt for why the port
// returns a shape.

private const val DOMAIN = "time-ago"

fun registerTimeAgoVectors() {
    FunctionRegistry.register(DOMAIN, "timeAgo") { input ->
        val o = input.jsonObject
        val result = timeAgo(
            o.getValue("iso").jsonPrimitive.content,
            o.getValue("now").jsonPrimitive.content,
        )
        when (result) {
            is TimeAgo.JustNow -> JsonObject(mapOf("unit" to JsonPrimitive("justNow")))
            is TimeAgo.Minutes -> JsonObject(
                mapOf("unit" to JsonPrimitive("minutes"), "value" to JsonPrimitive(result.value))
            )
            is TimeAgo.Hours -> JsonObject(
                mapOf("unit" to JsonPrimitive("hours"), "value" to JsonPrimitive(result.value))
            )
            is TimeAgo.Days -> JsonObject(
                mapOf("unit" to JsonPrimitive("days"), "value" to JsonPrimitive(result.value))
            )
            is TimeAgo.On -> JsonObject(
                mapOf("unit" to JsonPrimitive("on"), "iso" to JsonPrimitive(result.iso))
            )
        }
    }
}
