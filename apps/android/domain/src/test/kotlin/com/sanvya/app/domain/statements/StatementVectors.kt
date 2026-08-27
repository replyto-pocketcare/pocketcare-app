package com.sanvya.app.domain.statements

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// Wires the statements domain into FunctionRegistry.
//
// Every `expected` was produced by RUNNING web's real parseCsv.ts / analysis.ts
// / reconcile.ts, not by reading them -- so the fixtures carry two of web's own
// defects on purpose:
//
//   * the `semi` case pins web bug #4's SECOND site. "1.234,56" parses as
//     1.23456, so 1,234.56 euros import as 1.23. Reproduced, not fixed, because
//     a silent divergence on an amount is worse than a shared bug.
//   * the `jpy` case is the ONE expectation edited by hand, because the ports
//     deliberately fix web bug #8 (a hardcoded *100) with fromMajor().
//
// Two shape details are load-bearing, and both come from JSON.stringify
// dropping `undefined`:
//   * parseStatementCsv's rows have no `category`/`ref` keys at all (its object
//     literal never sets them), while the analysis fixtures do.
//   * the no-table early return has no `openingBalance`/`closingBalance` keys.

private const val DOMAIN = "statements"

private fun JsonElement.toStatementTxn(): StatementTxn {
    val o = jsonObject
    return StatementTxn(
        date = o.getValue("date").jsonPrimitive.content,
        description = o.getValue("description").jsonPrimitive.content,
        amount = o.getValue("amount").jsonPrimitive.long,
        balance = o["balance"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.long,
        category = o["category"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.contentOrNull,
        ref = o["ref"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.contentOrNull,
    )
}

private fun StatementTxn.toJson(withCategoryRef: Boolean): JsonElement = JsonObject(
    buildMap {
        put("date", JsonPrimitive(date))
        put("description", JsonPrimitive(description))
        put("amount", JsonPrimitive(amount))
        put("balance", balance?.let { JsonPrimitive(it) } ?: JsonNull)
        if (withCategoryRef) {
            put("category", category?.let { JsonPrimitive(it) } ?: JsonNull)
            put("ref", ref?.let { JsonPrimitive(it) } ?: JsonNull)
        }
    },
)

private fun ColumnMapping.toJson(): JsonElement = JsonObject(
    mapOf(
        "date" to (date?.let { JsonPrimitive(it) } ?: JsonNull),
        "description" to (description?.let { JsonPrimitive(it) } ?: JsonNull),
        "debit" to (debit?.let { JsonPrimitive(it) } ?: JsonNull),
        "credit" to (credit?.let { JsonPrimitive(it) } ?: JsonNull),
        "amount" to (amount?.let { JsonPrimitive(it) } ?: JsonNull),
        "balance" to (balance?.let { JsonPrimitive(it) } ?: JsonNull),
    ),
)

private fun ParsedStatement.toJson(): JsonElement = JsonObject(
    buildMap {
        put("kind", JsonPrimitive(kind))
        put("label", JsonPrimitive(label))
        put("currency", JsonPrimitive(currency))
        put(
            "period",
            JsonObject(
                mapOf(
                    "from" to (period.from?.let { JsonPrimitive(it) } ?: JsonNull),
                    "to" to (period.to?.let { JsonPrimitive(it) } ?: JsonNull),
                ),
            ),
        )
        // The no-table early return is the only path that never assigns these,
        // and it is identified by the warning it adds.
        if (!warnings.contains(WARN_NO_TABLE)) {
            put("openingBalance", openingBalance?.let { JsonPrimitive(it) } ?: JsonNull)
            put("closingBalance", closingBalance?.let { JsonPrimitive(it) } ?: JsonNull)
        }
        put("txns", JsonArray(txns.map { it.toJson(withCategoryRef = false) }))
        put("warnings", JsonArray(warnings.map { JsonPrimitive(it) }))
        put("mapping", mapping?.toJson() ?: JsonNull)
    },
)

private fun JsonElement.toRecordedTxn(): RecordedTxn {
    val o = jsonObject
    return RecordedTxn(
        id = o.getValue("id").jsonPrimitive.content,
        amount = o.getValue("amount").jsonPrimitive.long,
        date = o.getValue("date").jsonPrimitive.content,
        description = o.getValue("description").jsonPrimitive.content,
    )
}

private fun RecordedTxn.toJson(): JsonElement = JsonObject(
    mapOf(
        "id" to JsonPrimitive(id),
        "amount" to JsonPrimitive(amount),
        "date" to JsonPrimitive(date),
        "description" to JsonPrimitive(description),
    ),
)

private fun JsonElement.txnList(): List<StatementTxn> = jsonArray.map { it.toStatementTxn() }

fun registerStatementVectors() {
    FunctionRegistry.register(DOMAIN, "parseStatementDate") { input ->
        val raw = input.jsonObject["s"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.contentOrNull
        parseStatementDate(raw)?.let { JsonPrimitive(it) } ?: JsonNull
    }

    FunctionRegistry.register(DOMAIN, "parseStatementCsv") { input ->
        val o = input.jsonObject
        parseStatementCsv(
            text = o.getValue("text").jsonPrimitive.content,
            currency = o.getValue("currency").jsonPrimitive.content,
            kind = o.getValue("kind").jsonPrimitive.content,
        ).toJson()
    }

    FunctionRegistry.register(DOMAIN, "summarize") { input ->
        val s = summarize(input.jsonObject.getValue("txns").txnList())
        JsonObject(
            mapOf(
                "count" to JsonPrimitive(s.count),
                "credits" to JsonPrimitive(s.credits),
                "debits" to JsonPrimitive(s.debits),
                "net" to JsonPrimitive(s.net),
                "from" to (s.from?.let { JsonPrimitive(it) } ?: JsonNull),
                "to" to (s.to?.let { JsonPrimitive(it) } ?: JsonNull),
            ),
        )
    }

    FunctionRegistry.register(DOMAIN, "byCategory") { input ->
        JsonArray(
            byCategory(input.jsonObject.getValue("txns").txnList()).map {
                JsonObject(
                    mapOf(
                        "name" to JsonPrimitive(it.name),
                        "total" to JsonPrimitive(it.total),
                        "count" to JsonPrimitive(it.count),
                    ),
                )
            },
        )
    }

    FunctionRegistry.register(DOMAIN, "byMonth") { input ->
        JsonArray(
            byMonth(input.jsonObject.getValue("txns").txnList()).map {
                JsonObject(
                    mapOf(
                        "ym" to JsonPrimitive(it.ym),
                        "debit" to JsonPrimitive(it.debit),
                        "credit" to JsonPrimitive(it.credit),
                    ),
                )
            },
        )
    }

    FunctionRegistry.register(DOMAIN, "byDay") { input ->
        JsonArray(
            byDay(input.jsonObject.getValue("txns").txnList()).map {
                JsonObject(mapOf("date" to JsonPrimitive(it.date), "debit" to JsonPrimitive(it.debit)))
            },
        )
    }

    FunctionRegistry.register(DOMAIN, "outliers") { input ->
        JsonArray(
            outliers(input.jsonObject.getValue("txns").txnList()).map {
                JsonObject(
                    mapOf(
                        "txn" to it.txn.toJson(withCategoryRef = true),
                        "amount" to JsonPrimitive(it.amount),
                        "reason" to JsonPrimitive(it.reason),
                    ),
                )
            },
        )
    }

    FunctionRegistry.register(DOMAIN, "normalizeMerchant") { input ->
        JsonPrimitive(normalizeMerchant(input.jsonObject.getValue("s").jsonPrimitive.content))
    }

    FunctionRegistry.register(DOMAIN, "recurringCandidates") { input ->
        JsonArray(
            recurringCandidates(input.jsonObject.getValue("txns").txnList()).map { c ->
                JsonObject(
                    mapOf(
                        "label" to JsonPrimitive(c.label),
                        "key" to JsonPrimitive(c.key),
                        "amount" to JsonPrimitive(c.amount),
                        "count" to JsonPrimitive(c.count),
                        "cadence" to JsonPrimitive(c.cadence),
                        "sample" to JsonArray(c.sample.map { it.toJson(withCategoryRef = true) }),
                    ),
                )
            },
        )
    }

    FunctionRegistry.register(DOMAIN, "reconcileStatement") { input ->
        val o = input.jsonObject
        val r = reconcileStatement(
            parsed = o.getValue("parsed").txnList(),
            recorded = o.getValue("recorded").jsonArray.map { it.toRecordedTxn() },
            dayWindow = o.getValue("dayWindow").jsonPrimitive.int,
        )
        JsonObject(
            mapOf(
                "matched" to JsonArray(
                    r.matched.map {
                        JsonObject(
                            mapOf(
                                "parsed" to it.parsed.toJson(withCategoryRef = true),
                                "recorded" to it.recorded.toJson(),
                                "score" to JsonPrimitive(it.score),
                            ),
                        )
                    },
                ),
                "missingOnPlatform" to JsonArray(r.missingOnPlatform.map { it.toJson(withCategoryRef = true) }),
                "onlyOnPlatform" to JsonArray(r.onlyOnPlatform.map { it.toJson() }),
            ),
        )
    }
}
