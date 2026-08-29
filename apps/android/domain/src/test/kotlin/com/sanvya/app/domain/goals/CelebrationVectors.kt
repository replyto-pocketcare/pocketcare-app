package com.sanvya.app.domain.goals

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires Celebration.kt's goalCelebration() into FunctionRegistry.
//
// Vectors as SPEC, like dashboard-trend.json: web's version is a `useEffect`
// over a ref and localStorage, so there is nothing to record FROM. What is
// pinned is the truth table -- above all that a NULL `wasFunded` (the first
// observation of a goal) seeds without celebrating, which is the one rule a
// hand-written port gets wrong in a way no screenshot would reveal.
//
// The persisted set is carried as a SORTED array on both sides of the call:
// a Set has no order, and comparing an unordered structure against JSON would
// make the corpus pass or fail on hash iteration order.

private const val DOMAIN = "goal-celebration"

fun registerCelebrationVectors() {
    FunctionRegistry.register(DOMAIN, "goalCelebration") { input ->
        val o = input.jsonObject
        val decision = goalCelebration(
            goalId = o.getValue("goalId").jsonPrimitive.content,
            wasFunded = o.getValue("wasFunded").jsonPrimitive.booleanOrNull,
            funded = o.getValue("funded").jsonPrimitive.boolean,
            celebrated = o.getValue("celebrated").jsonArray.map { it.jsonPrimitive.content }.toSet(),
        )
        JsonObject(
            mapOf(
                "celebrate" to JsonPrimitive(decision.celebrate),
                "celebrated" to JsonArray(decision.celebrated.sorted().map { JsonPrimitive(it) }),
            )
        )
    }
}
