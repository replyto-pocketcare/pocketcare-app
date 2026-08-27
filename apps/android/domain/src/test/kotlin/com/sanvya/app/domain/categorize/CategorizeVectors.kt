package com.sanvya.app.domain.categorize

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

// Wires Categorize.kt into FunctionRegistry.
//
// Every `expected` was produced by RUNNING web's real normalize.ts and seeds.ts
// against the same nineteen bank-statement descriptions -- UPI strings, POS
// dumps, NEFT lines, a mangled "swiggylimited", an accented merchant, a bare
// reference number.
//
// The ORDER of `tokens` is part of the expectation, not incidental: it decides
// which category is scored first, and `scoreTokens` breaks a tie by keeping the
// first. A hash-ordered set on either platform would make an equal-score tie a
// coin flip that differs between phones and between runs.

private const val DOMAIN = "categorize"

private fun JsonElement.toCategories(): List<CategoryData> = jsonArray.map {
    val o = it.jsonObject
    CategoryData(o.getValue("id").jsonPrimitive.content, o.getValue("name").jsonPrimitive.content)
}

private fun JsonElement.toRules(): List<CategoryRule> = jsonArray.map {
    val o = it.jsonObject
    CategoryRule(
        kind = o.getValue("kind").jsonPrimitive.content,
        key = o.getValue("key").jsonPrimitive.content,
        categoryId = o.getValue("categoryId").jsonPrimitive.content,
        weight = o.getValue("weight").jsonPrimitive.long,
        corrections = o.getValue("corrections").jsonPrimitive.long,
    )
}

private fun seedRowsToJson(rows: List<SeedEntry>): JsonElement = JsonArray(
    rows.map {
        JsonObject(
            mapOf(
                "keyword" to JsonPrimitive(it.keyword),
                "categoryId" to JsonPrimitive(it.categoryId),
            ),
        )
    },
)

fun registerCategorizeVectors() {
    FunctionRegistry.register(DOMAIN, "normalizeText") { input ->
        val n = normalizeText(input.jsonObject.getValue("text").jsonPrimitive.content)
        JsonObject(
            mapOf(
                "phrase" to JsonPrimitive(n.phrase),
                "tokens" to JsonArray(n.tokens.map { JsonPrimitive(it) }),
                "merchant" to JsonPrimitive(n.merchant),
            ),
        )
    }

    FunctionRegistry.register(DOMAIN, "buildSeedMap") { input ->
        val cats = input.jsonObject.getValue("categories").toCategories()
        seedRowsToJson(buildSeedMap(cats).map { SeedEntry(it.key, it.value) })
    }

    FunctionRegistry.register(DOMAIN, "buildSeedList") { input ->
        seedRowsToJson(buildSeedList(input.jsonObject.getValue("categories").toCategories()))
    }

    FunctionRegistry.register(DOMAIN, "classify") { input ->
        val o = input.jsonObject
        val classifier = BulkClassifier(
            rules = o.getValue("rules").toRules(),
            categories = o.getValue("categories").toCategories(),
        )
        classifier.classify(o.getValue("text").jsonPrimitive.content)
            ?.let { JsonPrimitive(it) } ?: JsonNull
    }
}
