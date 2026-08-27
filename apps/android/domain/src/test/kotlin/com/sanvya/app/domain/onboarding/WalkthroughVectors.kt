package com.sanvya.app.domain.onboarding

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires Walkthrough.kt into FunctionRegistry.
//
// The whole truth table -- 96 combinations -- because the four guards exist to
// stop the dialog appearing at the wrong moment, and "does not appear" is the
// case nobody notices is broken until a returning user is told to set up from
// scratch.

private const val DOMAIN = "walkthrough"

fun registerWalkthroughVectors() {
    FunctionRegistry.register(DOMAIN, "shouldShowWalkthrough") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            shouldShowWalkthrough(
                done = o.getValue("done").jsonPrimitive.boolean,
                skipped = o.getValue("skipped").jsonPrimitive.boolean,
                syncPending = o.getValue("syncPending").jsonPrimitive.boolean,
                accountCountLoaded = o.getValue("accountCountLoaded").jsonPrimitive.boolean,
                realAccountCount = o.getValue("realAccountCount").jsonPrimitive.int,
                signedIn = o.getValue("signedIn").jsonPrimitive.boolean,
            )
        )
    }

    FunctionRegistry.register(DOMAIN, "walkthroughProgress") { input ->
        val p = walkthroughProgress(input.jsonObject.getValue("step").jsonPrimitive.int)
        JsonObject(mapOf("step" to JsonPrimitive(p.step), "of" to JsonPrimitive(p.of)))
    }
}
