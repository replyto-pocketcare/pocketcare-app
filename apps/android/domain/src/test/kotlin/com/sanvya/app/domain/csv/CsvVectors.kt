package com.sanvya.app.domain.csv

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires Csv.kt and ImportAdapters.kt into FunctionRegistry.
//
// Unusually for a port of a page's logic, these vectors came from running web's
// REAL exports -- csv.ts and adapters.ts are plain modules. The only edit was
// adding a `.ts` extension to adapters.ts's relative import so node could
// resolve it; the copy was diffed against the original to prove that is all
// that changed.
//
// One vector records a WEB BUG on purpose: `"1.234,56"` parses as 1.23456, not
// 1234.56. See PARITY_AUDIT -- it is left in so a fix on web makes this vector
// fail rather than passing silently on two of three platforms.

private const val DOMAIN = "csv"

private fun str(v: JsonElement?): String? =
    if (v == null || v is JsonNull) null else v.jsonPrimitive.content

private fun canonToJson(r: CanonRow): JsonObject = JsonObject(
    mapOf(
        "date" to JsonPrimitive(r.date),
        "type" to JsonPrimitive(r.type),
        "amount" to JsonPrimitive(r.amount),
        "currency" to JsonPrimitive(r.currency),
        "account" to JsonPrimitive(r.account),
        "toAccount" to (r.toAccount?.let { JsonPrimitive(it) } ?: JsonNull),
        "toAmount" to (r.toAmount?.let { JsonPrimitive(it) } ?: JsonNull),
        "category" to (r.category?.let { JsonPrimitive(it) } ?: JsonNull),
        "labels" to JsonArray(r.labels.map { JsonPrimitive(it) }),
        "paymentMethod" to (r.paymentMethod?.let { JsonPrimitive(it) } ?: JsonNull),
        "note" to (r.note?.let { JsonPrimitive(it) } ?: JsonNull),
        "description" to (r.description?.let { JsonPrimitive(it) } ?: JsonNull),
    )
)

fun registerCsvVectors() {
    FunctionRegistry.register(DOMAIN, "parseCsv") { input ->
        val o = input.jsonObject
        JsonArray(
            parseCsv(o.getValue("text").jsonPrimitive.content, str(o["delimiter"]))
                .map { row -> JsonArray(row.map { JsonPrimitive(it) }) }
        )
    }

    FunctionRegistry.register(DOMAIN, "parseRecords") { input ->
        val o = input.jsonObject
        JsonArray(
            parseRecords(o.getValue("text").jsonPrimitive.content, str(o["delimiter"]))
                .map { rec -> JsonObject(rec.mapValues { (_, v) -> JsonPrimitive(v) }) }
        )
    }

    FunctionRegistry.register(DOMAIN, "toCsv") { input ->
        val rows = input.jsonObject.getValue("rows").jsonArray.map { row ->
            row.jsonArray.map { str(it) }
        }
        JsonPrimitive(toCsv(rows))
    }

    FunctionRegistry.register(DOMAIN, "parseWithAdapter") { input ->
        val o = input.jsonObject
        JsonArray(
            parseWithAdapter(
                o.getValue("adapterId").jsonPrimitive.content,
                o.getValue("text").jsonPrimitive.content,
                o.getValue("nowIso").jsonPrimitive.content,
            ).map(::canonToJson)
        )
    }
}
