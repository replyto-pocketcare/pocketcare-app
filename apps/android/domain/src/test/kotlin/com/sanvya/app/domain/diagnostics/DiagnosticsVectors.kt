package com.sanvya.app.domain.diagnostics

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.longOrNull

// P1.6a: wires the real Diagnostics.kt port into FunctionRegistry so
// diagnostics.json's vectors un-skip. `detail`/redactDetail's input is a
// fully dynamic `Record<string, unknown>` in the TS source, so this
// adapter needs the same dynamic JSON<->DetailValue conversion Reconcile.kt
// needed for Row<->RowValue (P1.6a, same session).

private fun JsonElement.asDetailValue(): DetailValue = when (this) {
    is JsonNull -> DetailValue.Null
    is JsonObject -> DetailValue.Obj(LinkedHashMap(this.mapValues { (_, v) -> v.asDetailValue() }))
    is JsonArray -> DetailValue.Arr(this.map { it.asDetailValue() })
    is JsonPrimitive -> when {
        this.isString -> DetailValue.Str(this.content)
        this.booleanOrNull != null -> DetailValue.Bool(this.booleanOrNull!!)
        this.longOrNull != null -> DetailValue.IntNum(this.longOrNull!!)
        this.doubleOrNull != null -> DetailValue.DoubleNum(this.doubleOrNull!!)
        else -> DetailValue.Str(this.content)
    }
}

private fun DetailValue.toJson(): JsonElement = when (this) {
    is DetailValue.Null -> JsonNull
    is DetailValue.Str -> JsonPrimitive(value)
    is DetailValue.IntNum -> JsonPrimitive(value)
    is DetailValue.DoubleNum -> JsonPrimitive(value)
    is DetailValue.Bool -> JsonPrimitive(value)
    is DetailValue.Arr -> JsonArray(value.map { it.toJson() })
    is DetailValue.Obj -> JsonObject(value.mapValues { (_, v) -> v.toJson() })
}

private fun JsonElement.asLogEntry(): LogEntry {
    val o = jsonObject
    val detailEl = o["detail"]?.takeIf { it !is JsonNull }
    return LogEntry(
        at = o.getValue("at").jsonPrimitive.long,
        level = o.getValue("level").jsonPrimitive.content,
        scope = o.getValue("scope").jsonPrimitive.content,
        message = o.getValue("message").jsonPrimitive.content,
        route = o["route"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
        detail = detailEl?.asDetailValue() as? DetailValue.Obj,
    )
}

/** LogEntry.route/detail are OPTIONAL TS fields, omitted from the JSON
 * entirely when absent -- same convention as ReceiptDraft.rawText (P1.5)
 * and UpiTarget's optional fields (P1.6a, this session). */
private fun LogEntry.toJson(): JsonElement = JsonObject(
    buildMap {
        put("at", JsonPrimitive(at))
        put("level", JsonPrimitive(level))
        put("scope", JsonPrimitive(scope))
        put("message", JsonPrimitive(message))
        if (route != null) put("route", JsonPrimitive(route))
        if (detail != null) put("detail", detail!!.toJson())
    }
)

fun registerDiagnosticsVectors() {
    val domain = "diagnostics"

    FunctionRegistry.register(domain, "redactSecrets") { input ->
        JsonPrimitive(redactSecrets(input.jsonObject.getValue("input").jsonPrimitive.content))
    }
    FunctionRegistry.register(domain, "redactText") { input ->
        JsonPrimitive(redactText(input.jsonObject.getValue("input").jsonPrimitive.content))
    }
    FunctionRegistry.register(domain, "redactDetail") { input ->
        redactDetail(input.jsonObject.getValue("input").asDetailValue()).toJson()
    }
    FunctionRegistry.register(domain, "makeEntry") { input ->
        val o = input.jsonObject
        val optsObj = o["opts"]?.takeIf { it !is JsonNull }?.jsonObject
        val detailEl = optsObj?.get("detail")?.takeIf { it !is JsonNull }
        makeEntry(
            level = o.getValue("level").jsonPrimitive.content,
            scope = o.getValue("scope").jsonPrimitive.content,
            message = o.getValue("message").jsonPrimitive.content,
            route = optsObj?.get("route")?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
            detail = detailEl?.asDetailValue() as? DetailValue.Obj,
            at = optsObj?.get("at")?.takeIf { it !is JsonNull }?.jsonPrimitive?.long,
        ).toJson()
    }
    FunctionRegistry.register(domain, "formatLog") { input ->
        val o = input.jsonObject
        val entries = o.getValue("entries").jsonArray.map { it.asLogEntry() }
        val contextObj = o["context"]?.takeIf { it !is JsonNull }?.jsonObject ?: JsonObject(emptyMap())
        val context = contextObj.mapValues { (_, v) -> v.takeIf { it !is JsonNull }?.jsonPrimitive?.content }
        JsonPrimitive(formatLog(entries, context))
    }
}
