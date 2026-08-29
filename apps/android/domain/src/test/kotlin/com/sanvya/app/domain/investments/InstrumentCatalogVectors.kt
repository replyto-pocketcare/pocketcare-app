package com.sanvya.app.domain.investments

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires InstrumentCatalog.kt into FunctionRegistry.
//
// `seedInstrumentKeys` is the unusual one and the reason this corpus exists at
// all. The seed table is the only hand-transcribed DATA in this port -- 58 rows
// written out twice, once per platform -- and a search vector cannot protect
// it, because the search takes its candidate list as an argument. Pinning the
// keys makes a dropped or misspelled row a red test instead of a ticker that
// quietly exists on one phone and not the other.

private const val DOMAIN = "instrument-catalog"

private fun instrumentsOf(input: JsonArray): List<Instrument> = input.map { entry ->
    val i = entry.jsonObject
    Instrument(
        symbol = i.getValue("symbol").jsonPrimitive.content,
        name = i.getValue("name").jsonPrimitive.content,
        exchange = i.getValue("exchange").jsonPrimitive.content,
        currency = i.getValue("currency").jsonPrimitive.content,
    )
}

fun registerInstrumentCatalogVectors() {
    FunctionRegistry.register(DOMAIN, "seedInstrumentKeys") { _ ->
        JsonArray(seedInstrumentKeys().map { JsonPrimitive(it) })
    }

    FunctionRegistry.register(DOMAIN, "instrumentKey") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            instrumentKey(
                o.getValue("symbol").jsonPrimitive.content,
                o.getValue("exchange").jsonPrimitive.content,
            )
        )
    }

    FunctionRegistry.register(DOMAIN, "knownExchanges") { input ->
        JsonArray(
            knownExchanges(instrumentsOf(input.jsonObject.getValue("list").jsonArray))
                .map { JsonPrimitive(it) }
        )
    }

    FunctionRegistry.register(DOMAIN, "searchInstruments") { input ->
        val o = input.jsonObject
        // `exchange` is null in the corpus for "all exchanges"; JsonNull is a
        // present key with a null value, not an absent one, so it has to be
        // unwrapped explicitly rather than read through getValue().content.
        val exchangeNode: JsonElement = o.getValue("exchange")
        val exchange = if (exchangeNode is JsonNull) null else exchangeNode.jsonPrimitive.content
        val results = searchInstruments(
            all = instrumentsOf(o.getValue("list").jsonArray),
            query = o.getValue("query").jsonPrimitive.content,
            exchange = exchange,
            limit = o.getValue("limit").jsonPrimitive.int,
        )
        JsonArray(results.map { JsonPrimitive(instrumentKey(it.symbol, it.exchange)) })
    }
}
