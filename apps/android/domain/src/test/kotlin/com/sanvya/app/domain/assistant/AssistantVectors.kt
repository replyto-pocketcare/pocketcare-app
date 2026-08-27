package com.sanvya.app.domain.assistant

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.Json

// Wires the assistant's parser into FunctionRegistry.
//
// Where the fixtures come from, which differs per function and matters:
//
//   * `assistantCompactNum`, `parseAssistantBlocks` and `parseAssistantMessage`
//     were produced by RUNNING web's real code. The JSX-free functions were
//     lifted out of richMessage.tsx verbatim -- every extracted block was
//     diffed back against the source to prove nothing changed -- and executed.
//   * `assistantInlineSpans` could NOT be, because web's `inline()` returns
//     React elements and there is no value to capture. Its regex and branch
//     order were copied character-for-character and verified against the
//     source; the reference that produced these expectations emits spans
//     instead of elements. It proves Android and iOS agree, not that either
//     matches a browser.
//
// The serialisers below drop nulls rather than emitting them, because
// JSON.stringify drops `undefined` and web's card literals set `sub`/`value`/
// `pct` to exactly that when absent. A `"sub": null` in the output would fail
// against every fixture.

private const val DOMAIN = "assistant"

/** kotlinx's JsonElement -> Domain's own tree. This is the adapter the app needs too. */
private fun JsonElement.toAssistantJson(): AssistantJson = when (this) {
    is JsonNull -> AssistantJson.Null
    is JsonObject -> AssistantJson.Obj(mapValues { (_, v) -> v.toAssistantJson() })
    is JsonArray -> AssistantJson.Arr(map { it.toAssistantJson() })
    is JsonPrimitive -> when {
        isString -> AssistantJson.Str(content)
        booleanOrNull != null -> AssistantJson.Bool(booleanOrNull!!)
        doubleOrNull != null -> AssistantJson.Num(double)
        else -> AssistantJson.Null
    }
}

private fun obj(vararg pairs: Pair<String, JsonElement?>): JsonObject =
    JsonObject(pairs.mapNotNull { (k, v) -> v?.let { k to it } }.toMap())

private fun AssistantBlock.toJson(): JsonElement = when (this) {
    is AssistantBlock.Heading -> obj("t" to JsonPrimitive("h"), "level" to JsonPrimitive(level), "text" to JsonPrimitive(text))
    is AssistantBlock.Paragraph -> obj("t" to JsonPrimitive("p"), "lines" to JsonArray(lines.map { JsonPrimitive(it) }))
    is AssistantBlock.Bullets -> obj(
        "t" to JsonPrimitive("ul"),
        "items" to JsonArray(
            items.map {
                obj(
                    "text" to JsonPrimitive(it.text),
                    // Absent, not false: a plain bullet has no `task` key at all.
                    "task" to if (it.task) JsonPrimitive(true) else null,
                    "checked" to if (it.task) JsonPrimitive(it.checked) else null,
                )
            },
        ),
    )
    is AssistantBlock.Ordered -> obj("t" to JsonPrimitive("ol"), "items" to JsonArray(items.map { JsonPrimitive(it) }))
    is AssistantBlock.Quote -> obj("t" to JsonPrimitive("quote"), "lines" to JsonArray(lines.map { JsonPrimitive(it) }))
    is AssistantBlock.Table -> obj(
        "t" to JsonPrimitive("table"),
        "header" to JsonArray(header.map { JsonPrimitive(it) }),
        "rows" to JsonArray(rows.map { r -> JsonArray(r.map { JsonPrimitive(it) }) }),
    )
    AssistantBlock.Rule -> obj("t" to JsonPrimitive("hr"))
    is AssistantBlock.Code -> obj("t" to JsonPrimitive("code"), "text" to JsonPrimitive(text))
}

private fun AssistantCard.toJson(): JsonElement = when (this) {
    is AssistantCard.Stat -> obj(
        "kind" to JsonPrimitive("stat"),
        "label" to JsonPrimitive(label),
        "value" to JsonPrimitive(value),
        "sub" to sub?.let { JsonPrimitive(it) },
        "tone" to JsonPrimitive(tone),
    )
    is AssistantCard.Progress -> obj(
        "kind" to JsonPrimitive("progress"),
        "label" to JsonPrimitive(label),
        "value" to value?.let { JsonPrimitive(it) },
        "pct" to JsonPrimitive(pct),
    )
    is AssistantCard.Breakdown -> obj(
        "kind" to JsonPrimitive("breakdown"),
        "label" to JsonPrimitive(label),
        "items" to JsonArray(
            items.map {
                obj(
                    "label" to JsonPrimitive(it.label),
                    "value" to it.value?.let { v -> JsonPrimitive(v) },
                    "pct" to it.pct?.let { p -> JsonPrimitive(p) },
                )
            },
        ),
    )
    is AssistantCard.Chart -> obj(
        "kind" to JsonPrimitive("chart"),
        "label" to JsonPrimitive(label),
        "chart" to JsonPrimitive(chart),
        "points" to JsonArray(points.map { obj("x" to JsonPrimitive(it.x), "y" to JsonPrimitive(it.y)) }),
        "value" to value?.let { JsonPrimitive(it) },
    )
}

private fun AssistantAction.toJson(): JsonElement = obj(
    "label" to JsonPrimitive(label),
    "send" to send?.let { JsonPrimitive(it) },
    "href" to href?.let { JsonPrimitive(it) },
)

private fun InlineSpan.toJson(): JsonElement = obj(
    "t" to JsonPrimitive(kind.name.lowercase()),
    "s" to JsonPrimitive(text),
    "href" to href?.let { JsonPrimitive(it) },
)

fun registerAssistantVectors() {
    FunctionRegistry.register(DOMAIN, "assistantCompactNum") { input ->
        JsonPrimitive(assistantCompactNum(input.jsonObject.getValue("n").jsonPrimitive.double))
    }

    FunctionRegistry.register(DOMAIN, "parseAssistantBlocks") { input ->
        JsonArray(parseAssistantBlocks(input.jsonObject.getValue("src").jsonPrimitive.content).map { it.toJson() })
    }

    FunctionRegistry.register(DOMAIN, "assistantInlineSpans") { input ->
        JsonArray(assistantInlineSpans(input.jsonObject.getValue("s").jsonPrimitive.content).map { it.toJson() })
    }

    FunctionRegistry.register(DOMAIN, "parseAssistantMessage") { input ->
        // The composition a real screen performs: split, hand the payload to the
        // platform's JSON parser, validate. Registering it composed is the
        // point -- it is the whole pipeline that has to match web, not the
        // halves.
        val raw = input.jsonObject.getValue("raw").jsonPrimitive.content
        val split = splitAssistantUi(raw)
        val ui = split.json
            ?.let { runCatching { Json.parseToJsonElement(it) }.getOrNull() }
            ?.toAssistantJson()
            ?.let { assistantUiFrom(it) }
        JsonObject(
            mapOf(
                "text" to JsonPrimitive(split.text),
                "ui" to (
                    ui?.let {
                        JsonObject(
                            mapOf(
                                "cards" to JsonArray(it.cards.map { c -> c.toJson() }),
                                "actions" to JsonArray(it.actions.map { a -> a.toJson() }),
                            ),
                        )
                    } ?: JsonNull
                    ),
            ),
        )
    }
}
