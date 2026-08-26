package com.sanvya.app.domain.help

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires HelpSearch.kt into FunctionRegistry.
//
// Web's filter lives inside a component's `useMemo` and cannot be imported, so
// these vectors were generated from a transcription of it. Three of them pin
// details that are easy to get wrong: a whitespace-only query returns
// EVERYTHING (web trims this one, unlike the taxonomy search), section TITLES
// are not searched, and a needle may span the space web inserts between a
// question and its answer.

private const val DOMAIN = "help-search"

fun registerHelpSearchVectors() {
    FunctionRegistry.register(DOMAIN, "filterHelp") { input ->
        val o = input.jsonObject
        val sections = o.getValue("sections").jsonArray.map { entry ->
            val s = entry.jsonObject
            HelpSection(
                icon = s.getValue("icon").jsonPrimitive.content,
                color = s.getValue("color").jsonPrimitive.content,
                title = s.getValue("title").jsonPrimitive.content,
                items = s.getValue("items").jsonArray.map { i ->
                    val it = i.jsonObject
                    HelpItem(
                        question = it.getValue("q").jsonPrimitive.content,
                        answer = it.getValue("a").jsonPrimitive.content,
                    )
                },
            )
        }
        JsonArray(
            filterHelp(sections, o.getValue("query").jsonPrimitive.content).map { section ->
                JsonObject(
                    mapOf(
                        "title" to JsonPrimitive(section.title),
                        "items" to JsonArray(section.items.map { JsonPrimitive(it.question) }),
                    )
                )
            }
        )
    }
}
