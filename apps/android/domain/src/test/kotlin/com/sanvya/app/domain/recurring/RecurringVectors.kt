package com.sanvya.app.domain.recurring

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires Recurring.kt's advance() into FunctionRegistry so
// recurring-advance.json's 23 vectors run instead of being skipped.
//
// The vectors existed before any implementation did -- they were re-pinned to
// CLAMPING semantics on 2026-08-23 after web's setMonth() overflow was found
// (Jan 31 -> Mar 3 -> Apr 3, skipping February and then sticking on the 3rd).
// Nothing consumed them until now, which meant the decision was recorded and
// unenforced.

private const val DOMAIN = "recurring-advance"

fun registerRecurringAdvanceVectors() {
    FunctionRegistry.register(DOMAIN, "advance") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            advance(
                dateIso = o.getValue("date").jsonPrimitive.content,
                // The raw column value, through the same forgiving parse the
                // engine uses -- not a pre-validated enum. If fromDb() ever
                // stopped recognising "monthly", these vectors should fail.
                frequency = o.getValue("frequency").jsonPrimitive.content,
                n = o.getValue("n").jsonPrimitive.int,
            )
        )
    }
}
