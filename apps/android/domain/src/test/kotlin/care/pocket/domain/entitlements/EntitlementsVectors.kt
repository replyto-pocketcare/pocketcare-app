package care.pocket.domain.entitlements

import care.pocket.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// P1.7a: wires the real Entitlements.kt port into FunctionRegistry so
// entitlements.json's vectors un-skip.

fun registerEntitlementsVectors() {
    val domain = "entitlements"

    FunctionRegistry.register(domain, "canUse") { input ->
        val o = input.jsonObject
        JsonPrimitive(canUse(o.getValue("feature").jsonPrimitive.content, o.getValue("tier").jsonPrimitive.content))
    }
    FunctionRegistry.register(domain, "isPremiumFeature") { input ->
        JsonPrimitive(isPremiumFeature(input.jsonObject.getValue("feature").jsonPrimitive.content))
    }
}
