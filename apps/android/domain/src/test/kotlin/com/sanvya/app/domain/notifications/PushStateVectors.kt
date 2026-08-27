package com.sanvya.app.domain.notifications

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires PushState.kt into FunctionRegistry.
//
// The whole cross-product of the three inputs, because the one that matters --
// BLOCKED vs OFF -- looks identical on screen and only one of them can be fixed
// by tapping the switch.

private const val DOMAIN = "push-state"

fun registerPushStateVectors() {
    FunctionRegistry.register(DOMAIN, "pushState") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            pushState(
                supported = o.getValue("supported").jsonPrimitive.boolean,
                permission = o.getValue("permission").jsonPrimitive.content,
                prefEnabled = o.getValue("prefEnabled").jsonPrimitive.boolean,
            ).name.lowercase(),
        )
    }

    FunctionRegistry.register(DOMAIN, "shouldRegisterAtLaunch") { input ->
        val o = input.jsonObject
        JsonPrimitive(
            shouldRegisterAtLaunch(
                permission = o.getValue("permission").jsonPrimitive.content,
                prefEnabled = o.getValue("prefEnabled").jsonPrimitive.boolean,
            ),
        )
    }
}
