package com.sanvya.app.domain.transactions

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires AuditSummary.kt into FunctionRegistry.
//
// Web's version is a React component (`AuditChanges`) reading a module-level
// object literal, so it cannot be imported and called from node -- these
// vectors were transcribed from it and diffed against the component line by
// line. The one deliberate divergence they pin is the ORDER: web iterates the
// parsed object, this iterates the whitelist. See AUDIT_FIELDS.

private const val DOMAIN = "transaction-audit"

private fun nullableString(v: JsonElement?): String? =
    if (v == null || v is JsonNull) null else v.jsonPrimitive.content

/**
 * The JSON name for a kind. Spelled out rather than derived from the enum so
 * the corpus keeps one spelling across both platforms -- Kotlin's `name` is
 * SCREAMING_SNAKE and Swift's `rawValue` is camelCase, and neither is the other.
 */
private fun kindName(kind: AuditValueKind): String = when (kind) {
    AuditValueKind.MONEY -> "money"
    AuditValueKind.DATE -> "date"
    AuditValueKind.CATEGORY -> "category"
    AuditValueKind.ACCOUNT -> "account"
    AuditValueKind.PAYMENT_METHOD -> "paymentMethod"
    AuditValueKind.TYPE -> "type"
    AuditValueKind.TEXT -> "text"
}

private fun changeToJson(c: AuditChange): JsonObject = JsonObject(
    mapOf(
        "field" to JsonPrimitive(c.field),
        "kind" to JsonPrimitive(kindName(c.kind)),
        "from" to (c.from?.let { JsonPrimitive(it) } ?: JsonNull),
        "to" to (c.to?.let { JsonPrimitive(it) } ?: JsonNull),
    )
)

fun registerTransactionAuditVectors() {
    FunctionRegistry.register(DOMAIN, "summarizeAuditChanges") { input ->
        val raw = input.jsonObject["changes"]
        val parsed = if (raw == null || raw is JsonNull) {
            null
        } else {
            raw.jsonObject.mapValues { (_, v) ->
                val o = v.jsonObject
                AuditFromTo(from = nullableString(o["from"]), to = nullableString(o["to"]))
            }
        }
        when (val summary = summarizeAuditChanges(parsed)) {
            is AuditSummary.Absent -> JsonObject(mapOf("kind" to JsonPrimitive("absent")))
            is AuditSummary.MinorUpdate -> JsonObject(mapOf("kind" to JsonPrimitive("minorUpdate")))
            is AuditSummary.Changes -> JsonObject(
                mapOf(
                    "kind" to JsonPrimitive("changes"),
                    "entries" to JsonArray(summary.entries.map { changeToJson(it) }),
                )
            )
        }
    }
}
