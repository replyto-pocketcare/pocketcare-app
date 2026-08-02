package com.sanvya.app.domain.upi

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// P1.6a: wires the real Upi.kt port into FunctionRegistry so upi.json's
// vectors un-skip.

private fun BuiltIntent.toJson(): JsonElement =
    JsonObject(mapOf("url" to JsonPrimitive(url), "ref" to JsonPrimitive(ref)))

/** UpiTarget's optional fields (name/amountMinor/note) are OPTIONAL TS
 * fields, omitted from the JSON entirely when absent (not emitted as
 * null) -- same convention as ReceiptDraft.rawText (P1.5). Vectors that
 * only carry a bare vpa expect a target object with JUST a "vpa" key, so
 * emitting the others as explicit nulls here would fail exact key-set
 * comparison. */
private fun UpiTarget.toJson(): JsonElement = JsonObject(
    buildMap {
        put("vpa", JsonPrimitive(vpa))
        if (name != null) put("name", JsonPrimitive(name))
        if (amountMinor != null) put("amountMinor", JsonPrimitive(amountMinor))
        if (note != null) put("note", JsonPrimitive(note))
    }
)

/** UpiParseResult is a discriminated union in the TS source
 * (`{ok:true;target}|{ok:false;reason}`) -- the two branches have
 * DIFFERENT key sets, so (again mirroring the optional-field-omission
 * convention above) only one of "target"/"reason" is ever emitted,
 * matching whichever branch `ok` selects. */
private fun UpiParseResult.toJson(): JsonElement = JsonObject(
    buildMap {
        put("ok", JsonPrimitive(ok))
        if (ok) put("target", target!!.toJson()) else put("reason", JsonPrimitive(reason!!))
    }
)

fun registerUpiVectors() {
    val domain = "upi"

    FunctionRegistry.register(domain, "isValidVpa") { input ->
        JsonPrimitive(isValidVpa(input.jsonObject.getValue("value").jsonPrimitive.content))
    }
    FunctionRegistry.register(domain, "normalizeVpa") { input ->
        JsonPrimitive(normalizeVpa(input.jsonObject.getValue("value").jsonPrimitive.content))
    }
    FunctionRegistry.register(domain, "maskVpa") { input ->
        JsonPrimitive(maskVpa(input.jsonObject.getValue("value").jsonPrimitive.content))
    }
    FunctionRegistry.register(domain, "formatAmount") { input ->
        JsonPrimitive(formatAmount(input.jsonObject.getValue("minor").jsonPrimitive.double))
    }
    FunctionRegistry.register(domain, "newPaymentRef") { input ->
        val seed = input.jsonObject.getValue("seed").jsonPrimitive.int
        JsonPrimitive(newPaymentRef(seededRandom(seed)))
    }
    FunctionRegistry.register(domain, "isValidRef") { input ->
        JsonPrimitive(isValidRef(input.jsonObject.getValue("ref").jsonPrimitive.content))
    }
    FunctionRegistry.register(domain, "buildIntentUrl") { input ->
        val o = input.jsonObject
        val params = IntentParams(
            vpa = o.getValue("vpa").jsonPrimitive.content,
            name = o.getValue("name").jsonPrimitive.content,
            amountMinor = o.getValue("amountMinor").jsonPrimitive.double,
            note = o["note"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
            ref = o["ref"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
            currency = o["currency"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
        )
        buildIntentUrl(params).toJson()
    }
    FunctionRegistry.register(domain, "buildQrPayload") { input ->
        val o = input.jsonObject
        val params = IntentParams(
            vpa = o.getValue("vpa").jsonPrimitive.content,
            name = o.getValue("name").jsonPrimitive.content,
            amountMinor = o.getValue("amountMinor").jsonPrimitive.double,
            note = o["note"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
            ref = o["ref"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
            currency = o["currency"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
        )
        buildQrPayload(params).toJson()
    }
    FunctionRegistry.register(domain, "canPayViaUpi") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            canPayViaUpi(
                currency = o.getValue("currency").jsonPrimitive.content,
                amountMinor = o.getValue("amountMinor").jsonPrimitive.double,
                hasHandle = o.getValue("hasHandle").jsonPrimitive.boolean,
            )
        )
    }
    FunctionRegistry.register(domain, "parseUpiTarget") { input ->
        val text = input.jsonObject.getValue("input").jsonPrimitive.content
        parseUpiTarget(text).toJson()
    }
}
