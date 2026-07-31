package care.pocket.domain.finance

import care.pocket.domain.vectors.FunctionRegistry
import care.pocket.domain.vectors.jsonNumber
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// P1.3a: wires the real Finance.kt port into FunctionRegistry so
// finance.json's vectors un-skip. Registered under (domain="finance",
// fn=<name>) to match tools/golden-vectors/vectors/finance.json exactly.
// Field names and the money-string-vs-plain-number split below were read
// directly off tools/golden-vectors/export.ts's finance section, not
// guessed -- in particular, subscriptionImpact's and projectCashflow's
// money-shaped fields (totalPaid/opportunityCost/income/payments/...) are
// NOT stringified in the exported vectors (the exporter's rec() call sites
// for those two functions never wrap the result in amt()/mny()), unlike
// every other money-shaped result in this domain, which IS stringified.

private const val DOMAIN = "finance"

private fun JsonElement.asRecurringLike(): RecurringLike {
    val o = jsonObject
    return RecurringLike(o.getValue("amount").jsonPrimitive.long, o.getValue("frequency").jsonPrimitive.content)
}

private fun JsonElement.asCashflowInputs(): CashflowInputs {
    val o = jsonObject
    return CashflowInputs(
        monthlyIncome = o.getValue("monthlyIncome").jsonPrimitive.long,
        monthlyPayments = o.getValue("monthlyPayments").jsonPrimitive.long,
        monthlySavings = o.getValue("monthlySavings").jsonPrimitive.long,
        currentSavings = o.getValue("currentSavings").jsonPrimitive.long,
        annualReturnPct = o.getValue("annualReturnPct").jsonPrimitive.double,
        annualInflationPct = o.getValue("annualInflationPct").jsonPrimitive.double,
        incomeGrowthPct = o["incomeGrowthPct"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
    )
}

private fun YearProjection.toJson(): JsonElement = JsonObject(
    mapOf(
        "year" to JsonPrimitive(year),
        "income" to JsonPrimitive(income),
        "payments" to JsonPrimitive(payments),
        "savingsContributed" to JsonPrimitive(savingsContributed),
        "netCashflow" to JsonPrimitive(netCashflow),
        "savingsBalance" to JsonPrimitive(savingsBalance),
        "realSavingsBalance" to JsonPrimitive(realSavingsBalance),
    )
)

private fun AmortRow.toJson(): JsonElement = JsonObject(
    mapOf(
        "month" to JsonPrimitive(month),
        "emi" to JsonPrimitive(emi.toString()),
        "interest" to JsonPrimitive(interest.toString()),
        "principal" to JsonPrimitive(principal.toString()),
        "balance" to JsonPrimitive(balance.toString()),
    )
)

private fun nullableString(e: JsonElement): String? =
    if (e is JsonNull) null else e.jsonPrimitive.contentOrNull

private fun nullableInt(e: JsonElement?): Int? =
    if (e == null || e is JsonNull) null else e.jsonPrimitive.int

fun registerFinanceVectors() {
    FunctionRegistry.register(DOMAIN, "futureValue") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            futureValue(
                o.getValue("principal").jsonPrimitive.long,
                o.getValue("contribution").jsonPrimitive.long,
                o.getValue("periodicRate").jsonPrimitive.double,
                o.getValue("periods").jsonPrimitive.int,
            ).toString()
        )
    }

    FunctionRegistry.register(DOMAIN, "periodicRateFromAnnual") { input ->
        val o = input.jsonObject
        jsonNumber(periodicRateFromAnnual(o.getValue("annualPct").jsonPrimitive.double, o.getValue("period").jsonPrimitive.content))
    }

    FunctionRegistry.register(DOMAIN, "periodsToGoal") { input ->
        val o = input.jsonObject
        jsonNumber(
            periodsToGoal(
                o.getValue("current").jsonPrimitive.long,
                o.getValue("target").jsonPrimitive.long,
                o.getValue("contribution").jsonPrimitive.long,
                o.getValue("periodicRate").jsonPrimitive.double,
            )
        )
    }

    FunctionRegistry.register(DOMAIN, "monthlyEquivalent") { input ->
        val o = input.jsonObject
        JsonPrimitive(monthlyEquivalent(o.getValue("amount").jsonPrimitive.long, o.getValue("period").jsonPrimitive.content).toString())
    }

    FunctionRegistry.register(DOMAIN, "recurringMonthlyTotal") { input ->
        val o = input.jsonObject
        val items = o.getValue("items").jsonArray.map { it.asRecurringLike() }
        JsonPrimitive(recurringMonthlyTotal(items).toString())
    }

    FunctionRegistry.register(DOMAIN, "percentOfIncome") { input ->
        val o = input.jsonObject
        jsonNumber(percentOfIncome(o.getValue("monthlyAmount").jsonPrimitive.long, o.getValue("monthlyIncome").jsonPrimitive.long))
    }

    FunctionRegistry.register(DOMAIN, "subscriptionImpact") { input ->
        val o = input.jsonObject
        val r = subscriptionImpact(
            o.getValue("amount").jsonPrimitive.long,
            o.getValue("frequency").jsonPrimitive.content,
            o.getValue("years").jsonPrimitive.double,
            o.getValue("annualReturnPct").jsonPrimitive.double,
        )
        // NOT stringified -- see file header comment.
        JsonObject(mapOf("totalPaid" to JsonPrimitive(r.totalPaid), "opportunityCost" to JsonPrimitive(r.opportunityCost)))
    }

    FunctionRegistry.register(DOMAIN, "projectCashflow") { input ->
        val o = input.jsonObject
        val rows = projectCashflow(o.getValue("inp").asCashflowInputs(), o.getValue("years").jsonPrimitive.int)
        JsonArray(rows.map { it.toJson() })
    }

    FunctionRegistry.register(DOMAIN, "yearlyEquivalent") { input ->
        val o = input.jsonObject
        JsonPrimitive(yearlyEquivalent(o.getValue("amount").jsonPrimitive.long, o.getValue("period").jsonPrimitive.content).toString())
    }

    FunctionRegistry.register(DOMAIN, "emiFromPrincipal") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            emiFromPrincipal(
                o.getValue("principal").jsonPrimitive.long,
                o.getValue("annualRatePct").jsonPrimitive.double,
                o.getValue("tenureMonths").jsonPrimitive.int,
            ).toString()
        )
    }

    FunctionRegistry.register(DOMAIN, "amortizationSchedule") { input ->
        val o = input.jsonObject
        val rows = amortizationSchedule(
            o.getValue("principal").jsonPrimitive.long,
            o.getValue("annualRatePct").jsonPrimitive.double,
            o.getValue("emi").jsonPrimitive.long,
            o.getValue("maxMonths").jsonPrimitive.int,
        )
        JsonArray(rows.map { it.toJson() })
    }

    FunctionRegistry.register(DOMAIN, "timeframeTotal") { input ->
        val o = input.jsonObject
        JsonPrimitive(timeframeTotal(o.getValue("monthlyAmount").jsonPrimitive.long, o.getValue("timeframe").jsonPrimitive.content).toString())
    }

    FunctionRegistry.register(DOMAIN, "emiDueDate") { input ->
        val o = input.jsonObject
        val result = emiDueDate(
            nullableString(o.getValue("startIso")),
            nullableInt(o["dueDay"]),
            o.getValue("emiNo").jsonPrimitive.int,
        )
        if (result == null) JsonNull else JsonPrimitive(result)
    }

    FunctionRegistry.register(DOMAIN, "isDuePassed") { input ->
        val o = input.jsonObject
        JsonPrimitive(isDuePassed(nullableString(o.getValue("dueIso")), o.getValue("asOfIso").jsonPrimitive.content))
    }

    FunctionRegistry.register(DOMAIN, "effectivePaidEmis") { input ->
        val o = input.jsonObject
        val manual = o.getValue("manual").jsonArray.map { it.jsonPrimitive.int }
        val opts = o["opts"]?.jsonObject
        val result = effectivePaidEmis(
            manual = manual,
            totalEmis = o.getValue("totalEmis").jsonPrimitive.int,
            autoMark = opts?.get("autoMark")?.jsonPrimitive?.boolean ?: false,
            startIso = opts?.get("startIso")?.let { nullableString(it) },
            dueDay = opts?.get("dueDay")?.let { nullableInt(it) },
            asOfIso = opts?.get("asOfIso")?.jsonPrimitive?.content ?: "1970-01-01",
        )
        JsonArray(result.sorted().map { JsonPrimitive(it) })
    }
}
