package care.pocket.domain.budget

import care.pocket.domain.money.Money
import care.pocket.domain.vectors.FunctionRegistry
import care.pocket.domain.vectors.jsonNumber
import java.time.LocalDate
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// P1.3a: wires the real Budget.kt port into FunctionRegistry so
// budget.json's vectors un-skip. Registered under (domain="budget",
// fn=<name>) to match tools/golden-vectors/vectors/budget.json exactly.
//
// periodBounds/billingCycle's date inputs ("2026-07-31T12:00:00Z") are
// truncated to their first 10 characters to get the UTC calendar day --
// mirrors the TS source's own utcMidnight() truncation, and sidesteps ever
// parsing a full timestamp/timezone on the Kotlin side. Their DateWindow/
// BillingCycle outputs are re-expanded to full "YYYY-MM-DDT00:00:00.000Z"
// strings to match the exported vectors exactly (JS's Date -> JSON.stringify
// always writes milliseconds + "Z").

private const val DOMAIN = "budget"

private fun parseUtcDay(iso: String): LocalDate = LocalDate.parse(iso.take(10))
private fun LocalDate.toJsIso(): String = "${this}T00:00:00.000Z"

private fun JsonElement.asMoney(): Money {
    val o = jsonObject
    return Money(o.getValue("amount").jsonPrimitive.long, o.getValue("currency").jsonPrimitive.content)
}

private fun Money.toJson(): JsonElement = JsonObject(
    mapOf("amount" to JsonPrimitive(amount.toString()), "currency" to JsonPrimitive(currency))
)

fun registerBudgetVectors() {
    FunctionRegistry.register(DOMAIN, "periodBounds") { input ->
        val o = input.jsonObject
        val w = periodBounds(o.getValue("period").jsonPrimitive.content, parseUtcDay(o.getValue("date").jsonPrimitive.content))
        JsonObject(mapOf("start" to JsonPrimitive(w.start.toJsIso()), "endExclusive" to JsonPrimitive(w.endExclusive.toJsIso())))
    }

    FunctionRegistry.register(DOMAIN, "budgetProgress") { input ->
        val o = input.jsonObject
        val p = budgetProgress(
            o.getValue("limit").asMoney(),
            o.getValue("spent").asMoney(),
            o.getValue("thresholdPct").jsonPrimitive.double,
        )
        JsonObject(
            mapOf(
                "pct" to jsonNumber(p.pct),
                "remaining" to p.remaining.toJson(),
                "atOrOverThreshold" to JsonPrimitive(p.atOrOverThreshold),
                "overLimit" to JsonPrimitive(p.overLimit),
            )
        )
    }

    FunctionRegistry.register(DOMAIN, "crossedThreshold") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            crossedThreshold(
                o.getValue("previousSpent").asMoney(),
                o.getValue("newSpent").asMoney(),
                o.getValue("limit").asMoney(),
                o.getValue("thresholdPct").jsonPrimitive.double,
            )
        )
    }

    FunctionRegistry.register(DOMAIN, "billingCycle") { input ->
        val o = input.jsonObject
        val c = billingCycle(
            o.getValue("statementDay").jsonPrimitive.int,
            o.getValue("dueDay").jsonPrimitive.int,
            parseUtcDay(o.getValue("asOf").jsonPrimitive.content),
        )
        JsonObject(
            mapOf(
                "cycleStart" to JsonPrimitive(c.cycleStart.toJsIso()),
                "statementDate" to JsonPrimitive(c.statementDate.toJsIso()),
                "dueDate" to JsonPrimitive(c.dueDate.toJsIso()),
            )
        )
    }
}
