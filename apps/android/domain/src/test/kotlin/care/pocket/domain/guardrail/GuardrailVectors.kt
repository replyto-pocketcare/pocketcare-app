package care.pocket.domain.guardrail

import care.pocket.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// P1.6a: wires the real Guardrail.kt port into FunctionRegistry so
// guardrail.json's vectors un-skip.

private fun JsonElement.asContentBlock(): ContentBlock {
    val o = this as? JsonObject
    val t = o?.get("text")
    val text = if (t is JsonPrimitive && t.isString) t.content else null
    return ContentBlock(text = text)
}

private fun JsonElement.asMessageContent(): MessageContent = when (this) {
    is JsonPrimitive -> if (this.isString) MessageContent.Text(this.content) else MessageContent.Other
    is JsonArray -> MessageContent.Blocks(this.map { it.asContentBlock() })
    else -> MessageContent.Other
}

private fun JsonElement.asConversationMessage(): ConversationMessage {
    val o = jsonObject
    return ConversationMessage(
        role = o.getValue("role").jsonPrimitive.content,
        content = o.getValue("content").asMessageContent(),
    )
}

/** GuardrailResult's category/reason are OPTIONAL TS fields, omitted from
 * the JSON entirely when absent -- same convention established for
 * ReceiptDraft.rawText (P1.5), UpiTarget's optional fields, and
 * UpiParseResult's discriminated-union shape (both P1.6a, this session). */
private fun GuardrailResult.toJson(): JsonElement = JsonObject(
    buildMap {
        put("allow", JsonPrimitive(allow))
        if (category != null) put("category", JsonPrimitive(category))
        if (reason != null) put("reason", JsonPrimitive(reason))
    }
)

fun registerGuardrailVectors() {
    val domain = "guardrail"

    FunctionRegistry.register(domain, "screenPrompt") { input ->
        val raw = input.jsonObject["input"]
        val text = if (raw == null || raw is JsonNull) null else raw.jsonPrimitive.content
        screenPrompt(text).toJson()
    }

    FunctionRegistry.register(domain, "screenConversation") { input ->
        val messages = input.jsonObject.getValue("messages").jsonArray.map { it.asConversationMessage() }
        screenConversation(messages).toJson()
    }
}
