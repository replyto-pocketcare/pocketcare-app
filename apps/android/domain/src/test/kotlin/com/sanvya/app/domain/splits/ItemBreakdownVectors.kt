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
import kotlinx.serialization.json.long

// Wires ItemBreakdown.kt into FunctionRegistry.
//
// These vectors were TRANSCRIBED, not recorded: web's version of this
// arithmetic lives inside a React component (`ItemBreakdown.tsx`) and cannot be
// imported and run from node. The transcription was diffed against that
// component line by line -- in particular the two orderings it inherits from JS
// Map insertion order, which the last vector pins deliberately.

private const val DOMAIN = "splits-item-breakdown"

private fun nullableString(v: JsonElement?): String? =
    if (v == null || v is JsonNull) null else v.jsonPrimitive.content

private fun items(arr: JsonArray): List<ItemBreakdownItem> = arr.map { entry ->
    val o = entry.jsonObject
    ItemBreakdownItem(
        id = o.getValue("id").jsonPrimitive.content,
        amount = o.getValue("amount").jsonPrimitive.long,
    )
}

private fun shares(arr: JsonArray): List<ItemBreakdownShare> = arr.map { entry ->
    val o = entry.jsonObject
    ItemBreakdownShare(
        itemId = o.getValue("itemId").jsonPrimitive.content,
        userId = o.getValue("userId").jsonPrimitive.content,
        shareAmount = o.getValue("shareAmount").jsonPrimitive.long,
    )
}

private fun lineShareToJson(s: ItemBreakdownLineShare): JsonObject = JsonObject(
    mapOf(
        "userId" to JsonPrimitive(s.userId),
        "amount" to JsonPrimitive(s.amount),
    ),
)

private fun lineToJson(line: ItemBreakdownLine): JsonObject = JsonObject(
    mapOf(
        "itemId" to JsonPrimitive(line.itemId),
        "amount" to JsonPrimitive(line.amount),
        "shares" to JsonArray(line.shares.map(::lineShareToJson)),
    ),
)

fun registerSplitsItemBreakdownVectors() {
    FunctionRegistry.register(DOMAIN, "itemBreakdown") { input ->
        val o = input.jsonObject
        val view = itemBreakdown(
            items = items(o.getValue("items").jsonArray),
            shares = shares(o.getValue("shares").jsonArray),
            filterUserId = nullableString(o["filterUserId"]),
        )
        JsonObject(
            mapOf(
                "everyone" to JsonArray(view.everyone.map { JsonPrimitive(it) }),
                "lines" to JsonArray(view.lines.map(::lineToJson)),
                "total" to JsonPrimitive(view.total),
            ),
        )
    }
}
