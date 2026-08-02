package com.sanvya.app.domain.splitsmath

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// P1.4a: wires the real SplitsMath.kt port into FunctionRegistry so
// splits-math.json's vectors un-skip. Registered under
// (domain="splits-math", fn="pairwiseEdges") to match
// tools/golden-vectors/vectors/splits-math.json exactly.

private const val DOMAIN = "splits-math"

private fun JsonElement.asParty(): Party {
    val o = jsonObject
    return Party(o.getValue("userId").jsonPrimitive.content, o.getValue("share").jsonPrimitive.long, o.getValue("paid").jsonPrimitive.long)
}

private fun Edge.toJson(): JsonElement = JsonObject(
    mapOf("userId" to JsonPrimitive(userId), "amount" to JsonPrimitive(amount))
)

fun registerSplitsMathVectors() {
    FunctionRegistry.register(DOMAIN, "pairwiseEdges") { input ->
        val o = input.jsonObject
        val parties = o.getValue("parties").jsonArray.map { it.asParty() }
        val selfId = o.getValue("selfId").jsonPrimitive.content
        JsonArray(pairwiseEdges(parties, selfId).map { it.toJson() })
    }
}
