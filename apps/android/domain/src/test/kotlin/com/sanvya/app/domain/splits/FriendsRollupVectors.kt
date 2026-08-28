package com.sanvya.app.domain.splits

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires FriendsRollup.kt into FunctionRegistry.
//
// A SPEC, not a capture: the rules live in three `useMemo`s inside a React
// component and cannot be imported. They were transcribed and the
// transcription was run.
//
// Money travels as STRINGS, per the corpus rule.
//
// The fixtures that matter are the ones both ports were getting wrong: a
// balance that exists ONLY inside a group. Reading `direct` alone -- which is
// what SplitsViewModel did on both platforms -- returns an empty list for the
// first four cases here.
//
// ORDER is asserted, not incidental. `friendNets` returns FIRST-APPEARANCE
// order because web spreads a JS Map, and `everyoneYouShareWith` sorts by the
// SIZE of the balance and then by NAME -- the two-group fixture pins both, and
// the all-square fixture pins that a settled person is still listed at all.

private const val DOMAIN = "splits-rollup"

private fun JsonElement.people(): List<PersonNet> = jsonArray.map {
    val o = it.jsonObject
    PersonNet(
        userId = o.getValue("userId").jsonPrimitive.content,
        net = o.getValue("net").jsonPrimitive.content.toLong(),
    )
}

private fun JsonElement.groupsOfPeople(): List<List<PersonNet>> = jsonArray.map { it.people() }

private fun JsonElement.idGroups(): List<List<String>> =
    jsonArray.map { group -> group.jsonArray.map { it.jsonPrimitive.content } }

private fun emit(people: List<PersonNet>): JsonElement = JsonArray(
    people.map {
        JsonObject(
            mapOf(
                "userId" to JsonPrimitive(it.userId),
                "net" to JsonPrimitive(it.net.toString()),
            ),
        )
    },
)

fun registerFriendsRollupVectors() {
    FunctionRegistry.register(DOMAIN, "friendNets") { input ->
        val o = input.jsonObject
        emit(friendNets(o.getValue("groupPerUser").groupsOfPeople(), o.getValue("direct").people()))
    }
    FunctionRegistry.register(DOMAIN, "owedToYou") { input ->
        emit(owedToYou(input.jsonObject.getValue("nets").people()))
    }
    FunctionRegistry.register(DOMAIN, "youOwe") { input ->
        emit(youOwe(input.jsonObject.getValue("nets").people()))
    }
    FunctionRegistry.register(DOMAIN, "everyoneYouShareWith") { input ->
        val o = input.jsonObject
        emit(
            everyoneYouShareWith(
                groupMemberIds = o.getValue("groupMemberIds").idGroups(),
                direct = o.getValue("direct").people(),
                nets = o.getValue("nets").people(),
                names = o.getValue("names").jsonObject.mapValues { (_, v) -> v.jsonPrimitive.content },
            ),
        )
    }
}
