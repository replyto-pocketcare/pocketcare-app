package com.sanvya.app.domain.budget

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// Wires SpendSeries.kt's cumulativeSpendSeries() into FunctionRegistry.
//
// Like dashboard-grid.json and dashboard-trend.json, these vectors have no web
// function to be recorded FROM in a runnable sense -- web's version is inlined
// in a React component, reads the clock and returns localised day labels. They
// pin the ARITHMETIC that survives the port: the clamp to today, the 92-day
// step threshold, the always-sampled last day, and the `max(1, ...)` floor that
// makes a not-yet-started window come back empty rather than looping backwards.
//
// Minor-unit amounts are plain JSON numbers here rather than the decimal
// STRINGS export.ts writes for `Money` values, matching dashboard-trend.json --
// this corpus is hand-authored in the same family and its inputs are a
// day-to-total map, not a Money.

private const val DOMAIN = "budget-spend-series"

fun registerSpendSeriesVectors() {
    FunctionRegistry.register(DOMAIN, "cumulativeSpendSeries") { input ->
        val o = input.jsonObject
        val daily = o.getValue("dailyTotals").jsonObject.mapValues { (_, v) -> v.jsonPrimitive.long }
        val points = cumulativeSpendSeries(
            dailyTotals = daily,
            startIso = o.getValue("startIso").jsonPrimitive.content,
            endIso = o.getValue("endIso").jsonPrimitive.content,
            todayIso = o.getValue("todayIso").jsonPrimitive.content,
        )
        JsonArray(
            points.map {
                JsonObject(
                    mapOf(
                        "dayIso" to JsonPrimitive(it.dayIso),
                        "cumulativeMinor" to JsonPrimitive(it.cumulativeMinor),
                    )
                )
            }
        )
    }
}
