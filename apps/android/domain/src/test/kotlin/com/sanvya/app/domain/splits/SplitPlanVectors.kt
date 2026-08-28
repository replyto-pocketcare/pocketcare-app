package com.sanvya.app.domain.splits

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// Wires SplitPlan.kt into FunctionRegistry.
//
// A SPEC, not a capture: the rules live in a `useMemo` inside a React component
// and cannot be imported. They were transcribed from
// `apps/web/app/transactions/new/page.tsx` and the transcription was run.
//
// ONE fixture deliberately does NOT match what a browser would produce, and it
// is the JPY one: web's `toMinor` is `Math.round(Number(v) * 100)`, so an
// exact-mode split of a 3000-yen dinner reads every typed share as a hundredth
// of itself, never balances, and the user cannot save at all. This port uses
// `fromMajor(major, currency)`. For INR, USD and EUR the two agree byte for
// byte; the JPY and KWD fixtures are where they part, and they are here so that
// the divergence stays deliberate.
//
// Money travels as STRINGS, per the corpus rule. `percentSum` does not -- it is
// a percentage, not an amount. `participants[].value` is the awkward one: it
// carries a percent in percent mode and MINOR UNITS in exact mode, because that
// is the single field `createSplitExpense` takes. It stays a JSON number in
// both, since a field that changes type by mode would be worse than one that
// changes meaning.

private const val DOMAIN = "split-plan"

private fun JsonElement.textMap(): Map<String, String> =
    jsonObject.mapValues { (_, v) -> v.jsonPrimitive.content }

private fun JsonElement.strings(): List<String> = jsonArray.map { it.jsonPrimitive.content }

fun registerSplitPlanVectors() {
    FunctionRegistry.register(DOMAIN, "splitPlan") { input ->
        val o = input.jsonObject
        val plan = splitPlan(
            groupId = o.getValue("groupId").jsonPrimitive.content,
            mode = o.getValue("mode").jsonPrimitive.content,
            memberIds = o.getValue("memberIds").strings(),
            me = o.getValue("me").jsonPrimitive.content,
            totalMinor = o.getValue("totalMinor").jsonPrimitive.content.toLong(),
            currency = o.getValue("currency").jsonPrimitive.content,
            shareText = o.getValue("shareText").textMap(),
            multiPayer = o.getValue("multiPayer").jsonPrimitive.boolean,
            paidText = o.getValue("paidText").textMap(),
            hasAccount = o.getValue("hasAccount").jsonPrimitive.boolean,
        )
        JsonObject(
            mapOf(
                "shares" to JsonArray(plan.shares.map { JsonPrimitive(it.toString()) }),
                "sharesSum" to JsonPrimitive(plan.sharesSum.toString()),
                "percentSum" to JsonPrimitive(plan.percentSum),
                "paidSum" to JsonPrimitive(plan.paidSum.toString()),
                "valid" to JsonPrimitive(plan.valid),
                "participants" to JsonArray(
                    plan.participants.map { p ->
                        JsonObject(
                            buildMap {
                                put("userId", JsonPrimitive(p.userId))
                                // Absent, not null, in equal mode -- web builds
                                // the object with `value: undefined` there and
                                // JSON.stringify drops it.
                                p.value?.let { put("value", JsonPrimitive(it)) }
                            },
                        )
                    },
                ),
                "payers" to JsonArray(
                    plan.payers.map { p ->
                        JsonObject(
                            mapOf(
                                "userId" to JsonPrimitive(p.userId),
                                "paidMinor" to JsonPrimitive(p.paidMinor.toString()),
                                "isMe" to JsonPrimitive(p.isMe),
                            ),
                        )
                    },
                ),
            ),
        )
    }

    FunctionRegistry.register(DOMAIN, "splitActive") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            splitActive(
                type = o.getValue("type").jsonPrimitive.content,
                splitOn = o.getValue("splitOn").jsonPrimitive.boolean,
                groupId = o.getValue("groupId").jsonPrimitive.content,
                memberCount = o.getValue("memberCount").jsonPrimitive.content.toInt(),
            ),
        )
    }

    FunctionRegistry.register(DOMAIN, "forOtherActive") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            forOtherActive(
                type = o.getValue("type").jsonPrimitive.content,
                splitOn = o.getValue("splitOn").jsonPrimitive.boolean,
                forOtherOn = o.getValue("forOtherOn").jsonPrimitive.boolean,
                otherUserId = o.getValue("otherUserId").jsonPrimitive.content,
                totalMinor = o.getValue("totalMinor").jsonPrimitive.content.toLong(),
            ),
        )
    }

    FunctionRegistry.register(DOMAIN, "autoSplitGroupFor") { input ->
        val o = input.jsonObject
        val groups = o.getValue("groups").jsonArray.map { row ->
            val g = row.jsonObject
            AutoSplitCandidate(
                id = g.getValue("id").jsonPrimitive.content,
                startDate = g["startDate"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
                endDate = g["endDate"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
                autoSplit = g.getValue("autoSplit").jsonPrimitive.booleanOrNull ?: false,
            )
        }
        val result = autoSplitGroupFor(groups, o.getValue("dateIso").jsonPrimitive.content)
        if (result == null) JsonNull else JsonPrimitive(result)
    }
}
