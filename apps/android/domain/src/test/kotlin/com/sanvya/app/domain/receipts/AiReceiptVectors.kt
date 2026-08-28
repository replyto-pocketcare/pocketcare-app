package com.sanvya.app.domain.receipts

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires AiReceipt.kt into FunctionRegistry.
//
// A SPEC, not a capture: `mapLine` and the draft assembly live in a client
// module that imports supabase-js, so the fixtures were produced by
// transcribing the rules and running the transcription.
//
// ONE fixture deliberately does NOT match what a browser would produce, and it
// is the JPY one: web's `toMinor` is `Math.round(value * 10 ** minorDigits)`
// with `minorDigits` defaulting to 2 and no caller ever passing anything else,
// so a 3000-yen bill comes back as 300000 minor units. This uses
// `fromMajor(major, currency)`. INR, USD and EUR agree byte for byte; JPY and
// KWD are where they part.
//
// Money travels as STRINGS, per the corpus rule -- including `quantity`, which
// is milli-units and therefore also a scaled integer. `confidence` does not: it
// is a 0-100 score, not an amount.
//
// The two whitespace fixtures look pedantic and are not. Web's `x ? f(x) : null`
// treats "" as absent but "  " as present-then-trimmed-to-"", so those two
// inputs produce DIFFERENT outputs. A port that "cleaned that up" would diverge
// silently on a field the review screen displays.

private const val DOMAIN = "receipts-ai"

private fun JsonElement.doubleOrNullSafe(): Double? =
    if (this is JsonPrimitive && this !is JsonNull) doubleOrNull else null

private fun JsonObject.str(key: String): String? =
    this[key]?.let { if (it is JsonPrimitive && it !is JsonNull) it.content else null }

private fun JsonObject.num(key: String): Double? = this[key]?.doubleOrNullSafe()

private fun aiLine(o: JsonObject) = AiLine(
    kind = o.str("kind"),
    description = o.str("description"),
    quantity = o.num("quantity"),
    unit = o.str("unit"),
    unitPrice = o.num("unit_price"),
    amount = o.num("amount"),
)

private fun minorOrNull(v: Long?): JsonElement =
    if (v == null) JsonNull else JsonPrimitive(v.toString())

fun registerAiReceiptVectors() {
    FunctionRegistry.register(DOMAIN, "aiReceiptDraft") { input ->
        val o = input.jsonObject
        val r = o.getValue("receipt").jsonObject
        val receipt = AiReceipt(
            merchant = r.str("merchant"),
            date = r.str("date"),
            currency = r.str("currency"),
            total = r.num("total"),
            confidence = r.num("confidence"),
            lines = r["lines"]?.jsonArray?.map { aiLine(it.jsonObject) } ?: emptyList(),
        )
        val draft = aiReceiptDraft(
            receipt = receipt,
            currencyHint = o.getValue("currencyHint").jsonPrimitive.content,
            rawText = o.str("rawText"),
        )
        JsonObject(
            mapOf(
                "merchant" to (draft.merchant?.let { JsonPrimitive(it) } ?: JsonNull),
                "occurredAt" to (draft.occurredAt?.let { JsonPrimitive(it) } ?: JsonNull),
                "currency" to JsonPrimitive(draft.currency),
                "lines" to JsonArray(
                    draft.lines.map { l ->
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(l.id),
                                "kind" to JsonPrimitive(l.kind),
                                "description" to JsonPrimitive(l.description),
                                "quantity" to minorOrNull(l.quantity),
                                "unit" to (l.unit?.let { JsonPrimitive(it) } ?: JsonNull),
                                "unitPrice" to minorOrNull(l.unitPrice),
                                "amount" to JsonPrimitive(l.amount.toString()),
                                "confidence" to JsonPrimitive(l.confidence),
                            ),
                        )
                    },
                ),
                "total" to minorOrNull(draft.total),
                "confidence" to JsonPrimitive(draft.confidence),
                "engine" to JsonPrimitive(draft.engine),
                "rawText" to (draft.rawText?.let { JsonPrimitive(it) } ?: JsonNull),
            ),
        )
    }
}
