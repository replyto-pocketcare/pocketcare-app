package com.sanvya.app.domain.dashboard

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires TileGrid.kt's packRows() into FunctionRegistry.
//
// These vectors have no web counterpart to be generated FROM -- the browser
// does this in CSS -- so they are the specification rather than a recording of
// one. That makes them the only place the row-packing rules are written down
// as behaviour: no dense back-fill, clamp rather than drop an over-wide tile,
// and one column when a caller asks for zero.

private const val DOMAIN = "dashboard-grid"

fun registerTileGridVectors() {
    FunctionRegistry.register(DOMAIN, "packRows") { input ->
        val o = input.jsonObject
        val items = o.getValue("tiles").jsonArray.map { entry ->
            val t = entry.jsonObject
            GridItem(
                id = t.getValue("id").jsonPrimitive.content,
                columns = t.getValue("columns").jsonPrimitive.int,
            )
        }
        JsonArray(
            packRows(items, o.getValue("columns").jsonPrimitive.int)
                .map { row -> JsonArray(row.map { JsonPrimitive(it) }) }
        )
    }
}
