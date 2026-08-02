package com.sanvya.app.domain.syncpolicy

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// P1.6a: wires the real SyncPolicy.kt port into FunctionRegistry so
// sync-policy.json's vectors un-skip.

private fun JsonElement.asFailureInput(): FailureInput {
    val o = jsonObject
    return FailureInput(
        status = o["status"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.int,
        code = o["code"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
        message = o["message"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
    )
}

private fun JsonElement.asClassification(): Classification {
    val o = jsonObject
    return Classification(
        cls = o.getValue("cls").jsonPrimitive.content,
        reason = o.getValue("reason").jsonPrimitive.content,
    )
}

private fun Classification.toJson(): JsonElement =
    JsonObject(mapOf("cls" to JsonPrimitive(cls), "reason" to JsonPrimitive(reason)))

fun registerSyncPolicyVectors() {
    val domain = "sync-policy"

    // The vector JSON's "input" field IS the FailureInput object directly
    // (no extra field-name wrapper) -- confirmed by reading
    // sync-policy.json: {"fn":"classifyFailure","input":{"status":401}}.
    FunctionRegistry.register(domain, "classifyFailure") { input ->
        classifyFailure(input.asFailureInput()).toJson()
    }

    FunctionRegistry.register(domain, "shouldQuarantine") { input ->
        val o = input.jsonObject
        val c = o.getValue("c").asClassification()
        val attempts = o.getValue("attempts").jsonPrimitive.int
        JsonPrimitive(shouldQuarantine(c, attempts))
    }

    FunctionRegistry.register(domain, "backoffMs") { input ->
        val o = input.jsonObject
        val attempts = o.getValue("attempts").jsonPrimitive.int
        val base = o["base"]?.jsonPrimitive?.int ?: 1000
        val ceiling = o["ceiling"]?.jsonPrimitive?.int ?: 60_000
        JsonPrimitive(backoffMs(attempts, base, ceiling))
    }

    FunctionRegistry.register(domain, "explainForUser") { input ->
        JsonPrimitive(explainForUser(input.asFailureInput()))
    }
}
