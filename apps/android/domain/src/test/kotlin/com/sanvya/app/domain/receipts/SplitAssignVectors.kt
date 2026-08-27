package com.sanvya.app.domain.receipts

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// Wires SplitAssign.kt into FunctionRegistry.
//
// The interesting half is validateSplitLine: it decides whether a bill may be
// written at all, and "off by one minor unit" has to mean the same thing on all
// three clients. The discount cases matter most -- an exact split of a NEGATIVE
// line is the one place the sign rule is load-bearing.

private const val DOMAIN = "split-assign"

private fun JsonElement.toReceiptLine(): ReceiptLine {
    val o = jsonObject
    return ReceiptLine(
        id = o.getValue("id").jsonPrimitive.content,
        kind = o.getValue("kind").jsonPrimitive.content,
        description = o.getValue("description").jsonPrimitive.content,
        quantity = o["quantity"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.long,
        unit = o["unit"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
        unitPrice = o["unitPrice"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.long,
        amount = o.getValue("amount").jsonPrimitive.long,
        confidence = o.getValue("confidence").jsonPrimitive.int,
    )
}

private fun LineProblem?.toJson(): JsonElement = when (this) {
    null -> JsonNull
    is LineProblem.NeedsSomeone -> JsonObject(mapOf("kind" to JsonPrimitive("needsSomeone")))
    is LineProblem.ExactMismatch -> JsonObject(
        mapOf("kind" to JsonPrimitive("exactMismatch"), "diffMinor" to JsonPrimitive(diffMinor)),
    )
    is LineProblem.PercentMismatch -> JsonObject(
        mapOf("kind" to JsonPrimitive("percentMismatch"), "pct" to JsonPrimitive(pct)),
    )
    is LineProblem.QuantityMismatch -> JsonObject(
        mapOf(
            "kind" to JsonPrimitive("quantityMismatch"),
            "gotMilli" to JsonPrimitive(gotMilli),
            "wantMilli" to JsonPrimitive(wantMilli),
        ),
    )
}

fun registerSplitAssignVectors() {
    FunctionRegistry.register(DOMAIN, "receiptDigits") { input ->
        JsonPrimitive(receiptDigits(input.jsonObject.getValue("currency").jsonPrimitive.content))
    }

    FunctionRegistry.register(DOMAIN, "minorFromText") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            minorFromText(o.getValue("value").jsonPrimitive.content, o.getValue("digits").jsonPrimitive.int),
        )
    }

    FunctionRegistry.register(DOMAIN, "majorTextFromMinor") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            majorTextFromMinor(o.getValue("minor").jsonPrimitive.long, o.getValue("digits").jsonPrimitive.int),
        )
    }

    FunctionRegistry.register(DOMAIN, "qtyToMajor") { input ->
        JsonPrimitive(qtyToMajor(input.jsonObject.getValue("milli").jsonPrimitive.long))
    }

    FunctionRegistry.register(DOMAIN, "splitModesFor") { input ->
        val line = input.jsonObject.getValue("line").toReceiptLine()
        JsonArray(splitModesFor(line).map { JsonPrimitive(it) })
    }

    FunctionRegistry.register(DOMAIN, "lineWeight") { input ->
        val o = input.jsonObject
        val raw = o["raw"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content
        val w = lineWeight(
            mode = o.getValue("mode").jsonPrimitive.content,
            raw = raw,
            lineAmount = o.getValue("lineAmount").jsonPrimitive.long,
            digits = o.getValue("digits").jsonPrimitive.int,
        )
        if (w == null) JsonNull else JsonPrimitive(w)
    }

    FunctionRegistry.register(DOMAIN, "validateSplitLine") { input ->
        val o = input.jsonObject
        validateSplitLine(
            line = o.getValue("line").toReceiptLine(),
            mode = o.getValue("mode").jsonPrimitive.content,
            members = o.getValue("members").jsonArray.map { it.jsonPrimitive.content },
            weights = o.getValue("weights").jsonObject.mapValues { (_, v) -> v.jsonPrimitive.content },
            digits = o.getValue("digits").jsonPrimitive.int,
        ).toJson()
    }
}
