package com.sanvya.app.domain.taxonomy

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires CategoryTree.kt into FunctionRegistry.
//
// The logic lives inside a React component on web and cannot be imported, so
// these vectors were generated from a transcription of that render, diffed
// against it line by line. The expected value is ids only -- the rows
// themselves are echoed back unchanged, so comparing them would double the
// fixture and test nothing.

private const val DOMAIN = "category-tree"

private fun nullableString(v: JsonElement?): String? =
    if (v == null || v is JsonNull) null else v.jsonPrimitive.content

fun registerCategoryTreeVectors() {
    FunctionRegistry.register(DOMAIN, "categoryTree") { input ->
        val o = input.jsonObject
        val categories = o.getValue("categories").jsonArray.map { entry ->
            val c = entry.jsonObject
            TaxonomyCategory(
                id = c.getValue("id").jsonPrimitive.content,
                name = c.getValue("name").jsonPrimitive.content,
                kind = c.getValue("kind").jsonPrimitive.content,
                parentId = nullableString(c["parentId"]),
            )
        }
        val search = o.getValue("search").jsonPrimitive.content
        val expanded = o.getValue("expanded").jsonArray.map { it.jsonPrimitive.content }.toSet()
        JsonArray(
            categoryTree(categories, search, expanded).map { node ->
                JsonObject(
                    mapOf(
                        "id" to JsonPrimitive(node.category.id),
                        "childCount" to JsonPrimitive(node.childCount),
                        "isOpen" to JsonPrimitive(node.isOpen),
                        "children" to JsonArray(node.children.map { JsonPrimitive(it.id) }),
                    )
                )
            }
        )
    }
}
