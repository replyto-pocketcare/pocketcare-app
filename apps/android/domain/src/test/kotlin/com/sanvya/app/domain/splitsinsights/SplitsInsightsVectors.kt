package com.sanvya.app.domain.splitsinsights

import com.sanvya.app.domain.vectors.FunctionRegistry
import com.sanvya.app.domain.vectors.jsonNumber
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// P1.4a: wires the real SplitsInsights.kt port into FunctionRegistry so
// splits-insights.json's vectors un-skip. Registered under
// (domain="splits-insights", fn=<name>) to match
// tools/golden-vectors/vectors/splits-insights.json exactly. Every field
// here is a plain JSON number/string/bool -- this domain's exporter calls
// never wrap results with amt()/mny(), confirmed by reading the actual
// generated vector file, not assumed from earlier domains.

private const val DOMAIN = "splits-insights"

private fun JsonElement.asDebtLike(): DebtLike {
    val o = jsonObject
    return DebtLike(o.getValue("at").jsonPrimitive.content, o.getValue("amount").jsonPrimitive.long)
}

private fun JsonElement.asPaymentLike(): PaymentLike {
    val o = jsonObject
    return PaymentLike(o.getValue("at").jsonPrimitive.content, o.getValue("amount").jsonPrimitive.long)
}

private fun JsonElement.asFriendEdge(): FriendEdge {
    val o = jsonObject
    return FriendEdge(
        friendId = o.getValue("friendId").jsonPrimitive.content,
        groupId = o.getValue("groupId").jsonPrimitive.content,
        at = o.getValue("at").jsonPrimitive.content,
        amount = o.getValue("amount").jsonPrimitive.long,
    )
}

private fun JsonElement.asFriendSettlement(): FriendSettlement {
    val o = jsonObject
    return FriendSettlement(
        friendId = o.getValue("friendId").jsonPrimitive.content,
        at = o.getValue("at").jsonPrimitive.content,
        amount = o.getValue("amount").jsonPrimitive.long,
    )
}

private fun JsonElement.asFriendStats(): FriendStats {
    val o = jsonObject
    return FriendStats(
        friendId = o.getValue("friendId").jsonPrimitive.content,
        net = o.getValue("net").jsonPrimitive.long,
        youCovered = o.getValue("youCovered").jsonPrimitive.long,
        theyCovered = o.getValue("theyCovered").jsonPrimitive.long,
        lent = o.getValue("lent").jsonPrimitive.long,
        borrowed = o.getValue("borrowed").jsonPrimitive.long,
        groups = o.getValue("groups").jsonPrimitive.int,
        groupsOwing = o.getValue("groupsOwing").jsonPrimitive.int,
        groupsOwed = o.getValue("groupsOwed").jsonPrimitive.int,
        expenses = o.getValue("expenses").jsonPrimitive.int,
        avgSettleDays = o["avgSettleDays"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.double,
        settledDebts = o.getValue("settledDebts").jsonPrimitive.int,
    )
}

private fun AverageSettleResult.toJson(): JsonElement = JsonObject(
    mapOf(
        "avgDays" to (avgDays?.let { jsonNumber(it) } ?: JsonNull),
        "clearedCount" to JsonPrimitive(clearedCount),
    )
)

private fun FriendStats.toJson(): JsonElement = JsonObject(
    mapOf(
        "friendId" to JsonPrimitive(friendId),
        "net" to JsonPrimitive(net),
        "youCovered" to JsonPrimitive(youCovered),
        "theyCovered" to JsonPrimitive(theyCovered),
        "lent" to JsonPrimitive(lent),
        "borrowed" to JsonPrimitive(borrowed),
        "groups" to JsonPrimitive(groups),
        "groupsOwing" to JsonPrimitive(groupsOwing),
        "groupsOwed" to JsonPrimitive(groupsOwed),
        "expenses" to JsonPrimitive(expenses),
        "avgSettleDays" to (avgSettleDays?.let { jsonNumber(it) } ?: JsonNull),
        "settledDebts" to JsonPrimitive(settledDebts),
    )
)

private fun FriendInsight.toJson(): JsonElement = JsonObject(
    mapOf(
        "key" to JsonPrimitive(key),
        "friendId" to JsonPrimitive(friendId),
        "value" to jsonNumber(value),
        "evidence" to JsonPrimitive(evidence),
    )
)

// The same fixture edges/settlements export.ts's pickFriendInsights vector
// reuses from its own computeFriendStats vector -- that vector's
// input.stats field is just the descriptive placeholder string
// "computeFriendStats(edges,settlements) above", not real data, so this
// adapter reconstructs the identical fixture rather than trying to parse
// it (read directly off tools/golden-vectors/export.ts's splits-insights
// section, not guessed).
private val FIXTURE_EDGES = listOf(
    FriendEdge("f1", "g1", "2026-01-01T00:00:00Z", 500L),
    FriendEdge("f1", "g1", "2026-01-10T00:00:00Z", 300L),
    FriendEdge("f2", "g2", "2026-01-05T00:00:00Z", -200L),
)
private val FIXTURE_SETTLEMENTS = listOf(
    FriendSettlement("f1", "2026-01-15T00:00:00Z", 500L),
)

fun registerSplitsInsightsVectors() {
    FunctionRegistry.register(DOMAIN, "averageSettleDays") { input ->
        val o = input.jsonObject
        val debts = o.getValue("debts").jsonArray.map { it.asDebtLike() }
        val payments = o.getValue("payments").jsonArray.map { it.asPaymentLike() }
        averageSettleDays(debts, payments).toJson()
    }

    FunctionRegistry.register(DOMAIN, "computeFriendStats") { input ->
        val o = input.jsonObject
        val edges = o.getValue("edges").jsonArray.map { it.asFriendEdge() }
        val settlements = o.getValue("settlements").jsonArray.map { it.asFriendSettlement() }
        JsonArray(computeFriendStats(edges, settlements).map { it.toJson() })
    }

    FunctionRegistry.register(DOMAIN, "pickFriendInsights") { input ->
        val statsField = input.jsonObject.getValue("stats")
        val stats = if (statsField is JsonArray) {
            statsField.map { it.asFriendStats() }
        } else {
            computeFriendStats(FIXTURE_EDGES, FIXTURE_SETTLEMENTS)
        }
        JsonArray(pickFriendInsights(stats).map { it.toJson() })
    }
}
