package com.sanvya.app.domain.search

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires Search.kt into FunctionRegistry.
//
// Web's filter lives inside a `useMemo` in app/search/page.tsx and cannot be
// imported, so these vectors come from a reference implementation of the PORT
// that was diffed, case by case, against a literal transcription of web's
// component. The two agree everywhere except three min/max cases involving a
// JPY row -- web's hardcoded `* 100` makes a "1000" bound mean 100000 minor
// units in every currency. Those three are the deliberate divergence, and they
// are in here so that it stays deliberate.

private const val DOMAIN = "search"

/** Absent and null both mean "no value" -- the fixtures omit null fields. */
private fun optional(v: JsonElement?): String? =
    if (v == null || v is JsonNull) null else v.jsonPrimitive.content

private fun required(o: JsonObject, key: String): String = o.getValue(key).jsonPrimitive.content

private fun rows(arr: JsonArray): List<SearchRow> = arr.map { entry ->
    val o = entry.jsonObject
    SearchRow(
        id = required(o, "id"),
        type = required(o, "type"),
        accountId = required(o, "accountId"),
        toAccountId = optional(o["toAccountId"]),
        occurredAt = required(o, "occurredAt"),
        amountMinor = o.getValue("amountMinor").jsonPrimitive.long,
        currency = required(o, "currency"),
        labels = optional(o["labels"]),
        note = optional(o["note"]),
        description = optional(o["description"]),
        methodLabel = optional(o["methodLabel"]),
        categoryName = optional(o["categoryName"]),
        accountName = optional(o["accountName"]),
        accountType = optional(o["accountType"]),
    )
}

private fun criteria(o: JsonObject) = SearchCriteria(
    query = optional(o["query"]) ?: "",
    type = optional(o["type"]) ?: "all",
    accountId = optional(o["accountId"]) ?: "",
    from = optional(o["from"]) ?: "",
    to = optional(o["to"]) ?: "",
    min = optional(o["min"]) ?: "",
    max = optional(o["max"]) ?: "",
)

fun registerSearchVectors() {
    FunctionRegistry.register(DOMAIN, "searchTransactions") { input ->
        val o = input.jsonObject
        val result = searchTransactions(
            rows(o.getValue("rows").jsonArray),
            criteria(o.getValue("criteria").jsonObject),
        )
        // Ids, not whole rows: the vector pins WHICH rows survive and in what
        // order, which is the whole contract. Echoing the inputs back would
        // double the fixture and test nothing extra.
        JsonArray(result.map { JsonPrimitive(it.id) })
    }

    FunctionRegistry.register(DOMAIN, "activeFilterCount") { input ->
        JsonPrimitive(activeFilterCount(criteria(input.jsonObject.getValue("criteria").jsonObject)))
    }
}
