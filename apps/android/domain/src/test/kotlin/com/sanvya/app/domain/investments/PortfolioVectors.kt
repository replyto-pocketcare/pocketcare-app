package com.sanvya.app.domain.investments

import com.sanvya.app.domain.insights.DivEvent
import com.sanvya.app.domain.vectors.FunctionRegistry
import com.sanvya.app.domain.vectors.jsonNumber
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// Wires Portfolio.kt into FunctionRegistry.
//
// These vectors are the SPECIFICATION, not a recording. All four pieces of
// maths live inside React components on web -- a `useMemo` in
// investments/page.tsx, another in ProjectionPanel.tsx -- and cannot be
// imported into node, which is the same situation dashboard-grid and
// category-tree are in. They were transcribed from those components and then
// pinned here.
//
// Two of the cases exist because they are the ones that would silently differ
// between the platforms rather than fail loudly:
//
//   - `financialYear("2026-03-31")` vs `("2026-04-01")`. Web reads
//     `getMonth() >= 3`, which is APRIL, because JS months are zero-based.
//     Both ports use one-based months, so the boundary had to move by one and
//     an off-by-one here would mis-date every dividend card for a whole month.
//   - `projectPortfolio` with `years = 0`. Web's `for (m = 1; m <= 0; m++)`
//     simply does not run; Kotlin's `1..0` is likewise empty but Swift's
//     `1...0` is a CRASH, so the Swift port guards on it and this vector is
//     what keeps that guard honest.

private const val DOMAIN = "investments-portfolio"

/** Rebuilds a [Group] from the corpus. `holdings` is irrelevant to every
 * function here -- all of them read only the subtotals -- so it is empty
 * rather than a fixture nobody looks at. */
private fun groupsOf(input: JsonArray): List<Group> = input.map { entry ->
    val g = entry.jsonObject
    val cost = g.getValue("cost").jsonPrimitive.long
    val value = g.getValue("value").jsonPrimitive.long
    Group(
        key = g.getValue("key").jsonPrimitive.content,
        label = g.getValue("label").jsonPrimitive.content,
        holdings = emptyList(),
        cost = cost,
        value = value,
        gain = g.getValue("gain").jsonPrimitive.long,
        gainPct = if (cost > 0) ((value - cost).toDouble() / cost.toDouble()) * 100.0 else 0.0,
    )
}

fun registerPortfolioVectors() {
    FunctionRegistry.register(DOMAIN, "allocationSlices") { input ->
        JsonArray(
            allocationSlices(groupsOf(input.jsonObject.getValue("groups").jsonArray)).map {
                JsonObject(
                    mapOf(
                        "key" to JsonPrimitive(it.key),
                        "label" to JsonPrimitive(it.label),
                        "valueBase" to JsonPrimitive(it.valueBase),
                        "sharePct" to jsonNumber(it.sharePct),
                    )
                )
            }
        )
    }

    FunctionRegistry.register(DOMAIN, "gainBars") { input ->
        JsonArray(
            gainBars(groupsOf(input.jsonObject.getValue("groups").jsonArray)).map {
                JsonObject(
                    mapOf(
                        "key" to JsonPrimitive(it.key),
                        "label" to JsonPrimitive(it.label),
                        "gainBase" to JsonPrimitive(it.gainBase),
                    )
                )
            }
        )
    }

    FunctionRegistry.register(DOMAIN, "fyStart") { input ->
        JsonPrimitive(fyStart(input.jsonObject.getValue("today").jsonPrimitive.content))
    }

    FunctionRegistry.register(DOMAIN, "financialYear") { input ->
        val fy = financialYear(input.jsonObject.getValue("today").jsonPrimitive.content)
        JsonObject(
            mapOf(
                "startYear" to JsonPrimitive(fy.startYear),
                "endYearShort" to JsonPrimitive(fy.endYearShort),
            )
        )
    }

    FunctionRegistry.register(DOMAIN, "inCurrentFyToDate") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            inCurrentFyToDate(
                o.getValue("iso").jsonPrimitive.content,
                o.getValue("today").jsonPrimitive.content,
            )
        )
    }

    FunctionRegistry.register(DOMAIN, "dividendsThisFy") { input ->
        val o = input.jsonObject
        val events = o.getValue("events").jsonArray.map { entry ->
            val e = entry.jsonObject
            DivEvent(
                date = e.getValue("date").jsonPrimitive.content,
                base = e.getValue("base").jsonPrimitive.long,
                upcoming = e.getValue("upcoming").jsonPrimitive.boolean,
            )
        }
        JsonPrimitive(dividendsThisFy(events, o.getValue("today").jsonPrimitive.content))
    }

    FunctionRegistry.register(DOMAIN, "dividendYieldRate") { input ->
        val o = input.jsonObject
        jsonNumber(
            dividendYieldRate(
                o.getValue("annualDividendBase").jsonPrimitive.long,
                o.getValue("currentValueBase").jsonPrimitive.long,
            )
        )
    }

    FunctionRegistry.register(DOMAIN, "projectPortfolio") { input ->
        val o = input.jsonObject
        val p = projectPortfolio(
            currentValueBase = o.getValue("currentValueBase").jsonPrimitive.long,
            growthPctPerYear = o.getValue("growthPctPerYear").jsonPrimitive.double,
            monthlyContributionBase = o.getValue("monthlyContributionBase").jsonPrimitive.long,
            years = o.getValue("years").jsonPrimitive.int,
            reinvestDividends = o.getValue("reinvestDividends").jsonPrimitive.boolean,
            dividendYieldRate = o.getValue("dividendYieldRate").jsonPrimitive.double,
        )
        JsonObject(
            mapOf(
                "points" to JsonArray(
                    p.points.map {
                        JsonObject(
                            mapOf(
                                "yearsOut" to JsonPrimitive(it.yearsOut),
                                "valueBase" to JsonPrimitive(it.valueBase),
                                "contributedBase" to JsonPrimitive(it.contributedBase),
                            )
                        )
                    }
                ),
                "endValueBase" to JsonPrimitive(p.endValueBase),
                "contributedBase" to JsonPrimitive(p.contributedBase),
                "growthBase" to JsonPrimitive(p.growthBase),
            )
        )
    }

    FunctionRegistry.register(DOMAIN, "clampSipDay") { input ->
        JsonPrimitive(clampSipDay(input.jsonObject.getValue("day").jsonPrimitive.int))
    }
}
