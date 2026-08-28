package com.sanvya.app.domain.cards

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires CardCycle.kt into FunctionRegistry.
//
// A SPEC, not a capture: `cardDueDate` lives inside a page module in
// `apps/web/app/accounts/new/page.tsx` and cannot be imported. It was
// transcribed and the transcription was run.
//
// ONE fixture family deliberately does NOT match what a browser would produce.
// Web builds the due date as LOCAL midnight and stores
// `.toISOString().slice(0, 10)`, which is UTC -- so every user east of
// Greenwich is given a due date one day EARLY. These fixtures carry the
// calendar date the user was actually shown. See CardCycle.kt.
//
// `clampCardDay` is the boring half and is here anyway: it is the only thing
// standing between a typed "31" and a due date of 31 February, and its
// `Number(v) || fallback` reads "0" as "unset", which is not obvious and is
// worth a fixture.

private const val DOMAIN = "card-cycle"

fun registerCardCycleVectors() {
    FunctionRegistry.register(DOMAIN, "cardDueDate") { input ->
        val o = input.jsonObject
        val due = cardDueDate(
            createdIso = o.getValue("createdIso").jsonPrimitive.content,
            statementDay = o.getValue("statementDay").jsonPrimitive.int,
            dueDay = o.getValue("dueDay").jsonPrimitive.int,
        )
        JsonObject(
            mapOf(
                "dueOn" to JsonPrimitive(due.dueOn),
                "thisCycle" to JsonPrimitive(due.thisCycle),
            ),
        )
    }
    FunctionRegistry.register(DOMAIN, "clampCardDay") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            clampCardDay(
                raw = o.getValue("raw").jsonPrimitive.content,
                fallback = o.getValue("fallback").jsonPrimitive.int,
            ),
        )
    }
}
