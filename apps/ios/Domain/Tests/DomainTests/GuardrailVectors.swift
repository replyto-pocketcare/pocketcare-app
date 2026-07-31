import Foundation
@testable import Domain

// P1.6b: wires the real Guardrail.swift port into FunctionRegistry so
// guardrail.json's vectors un-skip. Mirrors Android's GuardrailVectors.kt.

private func asContentBlock(_ any: Any) -> ContentBlock {
    let d = any as? [String: Any]
    return ContentBlock(text: d?["text"] as? String)
}

private func asMessageContent(_ any: Any) -> MessageContent {
    if let s = any as? String { return .text(s) }
    if let arr = any as? [Any] { return .blocks(arr.map(asContentBlock)) }
    return .other
}

private func asConversationMessage(_ any: Any) -> ConversationMessage {
    let d = any as! [String: Any]
    return ConversationMessage(role: d["role"] as! String, content: asMessageContent(d["content"] as Any))
}

/// GuardrailResult's category/reason are OPTIONAL TS fields, omitted from
/// the JSON entirely when absent -- same convention established for
/// ReceiptDraft.rawText (P1.5), UpiTarget's optional fields, and
/// UpiParseResult's discriminated-union shape (both P1.6b, this session).
private func guardrailResultToJson(_ r: GuardrailResult) -> [String: Any] {
    var out: [String: Any] = ["allow": r.allow]
    if let category = r.category { out["category"] = category }
    if let reason = r.reason { out["reason"] = reason }
    return out
}

func registerGuardrailVectors() {
    let domain = "guardrail"

    FunctionRegistry.register(domain: domain, fn: "screenPrompt") { input in
        let d = input as! [String: Any]
        let raw = d["input"]
        let text: String? = (raw == nil || raw is NSNull) ? nil : (raw as? String)
        return guardrailResultToJson(screenPrompt(text))
    }

    FunctionRegistry.register(domain: domain, fn: "screenConversation") { input in
        let d = input as! [String: Any]
        let messages = (d["messages"] as! [Any]).map(asConversationMessage)
        return guardrailResultToJson(screenConversation(messages))
    }
}
