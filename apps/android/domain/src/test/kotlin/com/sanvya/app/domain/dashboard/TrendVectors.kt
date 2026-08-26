package com.sanvya.app.domain.dashboard

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// Wires Trend.kt's buildTrend() and monthlyCashflow() into FunctionRegistry.
//
// Like dashboard-grid.json, these vectors have no web function to be recorded
// FROM in a runnable sense -- web's buildTrend reads the clock and returns
// English labels. They pin the ARITHMETIC that survives the port, including the
// one-day overlap in web's four weekly windows, which is preserved on purpose.

private const val DOMAIN = "dashboard-trend"

private fun bucketsJson(buckets: List<TrendBucket>) = JsonArray(
    buckets.map {
        JsonObject(
            mapOf(
                "startIso" to JsonPrimitive(it.startIso),
                "totalMinor" to JsonPrimitive(it.totalMinor),
            )
        )
    }
)

fun registerTrendVectors() {
    FunctionRegistry.register(DOMAIN, "buildTrend") { input ->
        val o = input.jsonObject
        val daily = o.getValue("dailyTotals").jsonObject
            .mapValues { (_, v) -> v.jsonPrimitive.long }
        bucketsJson(
            buildTrend(
                dailyTotals = daily,
                period = TrendPeriod.from(o.getValue("period").jsonPrimitive.content),
                todayIso = o.getValue("todayIso").jsonPrimitive.content,
            )
        )
    }

    FunctionRegistry.register(DOMAIN, "monthlyCashflow") { input ->
        val o = input.jsonObject
        val rows = o.getValue("rows").jsonArray.map { entry ->
            val row = entry.jsonArray
            Triple(
                row[0].jsonPrimitive.content,
                row[1].jsonPrimitive.content,
                row[2].jsonPrimitive.long,
            )
        }
        JsonArray(
            monthlyCashflow(rows, o.getValue("months").jsonPrimitive.int).map {
                JsonObject(
                    mapOf(
                        "month" to JsonPrimitive(it.month),
                        "incomeMinor" to JsonPrimitive(it.incomeMinor),
                        "expenseMinor" to JsonPrimitive(it.expenseMinor),
                    )
                )
            }
        )
    }
}
