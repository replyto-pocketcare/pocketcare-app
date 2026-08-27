package com.sanvya.app.domain.feedback

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires Feedback.kt's key derivation into FunctionRegistry.
//
// The expectations are hand-written from web's own AREAS list, because web has
// no such function to run: it renders the raw English into its picker. That is
// exactly why these vectors exist. The two sides of this port must agree on the
// mapping from a STORED value ("Accounts & Cards", which goes into the column
// and must not be translated) to an i18n KEY (`areaAccountsCards`, which is
// what the user reads) -- and the derivation is string surgery, which is where
// Kotlin and Swift are most likely to differ quietly.
//
// The whole point is caught by two cases: "Accounts & Cards" (an ampersand
// surrounded by spaces, so a naive camel-case leaves a stray capital) and
// "Sync / Offline" (a slash, likewise).

private const val DOMAIN = "feedback"

fun registerFeedbackVectors() {
    FunctionRegistry.register(DOMAIN, "feedbackAreaKey") { input ->
        JsonPrimitive(feedbackAreaKey(input.jsonObject.getValue("area").jsonPrimitive.content))
    }

    FunctionRegistry.register(DOMAIN, "feedbackSeverityKey") { input ->
        JsonPrimitive(feedbackSeverityKey(input.jsonObject.getValue("severity").jsonPrimitive.content))
    }
}
