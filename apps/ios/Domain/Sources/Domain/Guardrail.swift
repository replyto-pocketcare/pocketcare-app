import Foundation

// Ported from packages/core/guardrail/src/index.ts (P1.6b). Mirrors
// apps/android/domain/.../guardrail/Guardrail.kt (P1.6a). Deterministic
// pre-flight screening for the AI assistant -- a defense-in-depth layer
// that runs BEFORE the model call, deterministically rejecting the
// classes of prompt we never want to reach the LLM (prompt injection,
// data exfiltration, secret/credential harvesting, malware/code
// generation, and clearly harmful requests). Must stay pure (no I/O) so
// it runs identically wherever it's called from.
//
// Every regex below is transcribed VERBATIM from the TS source (character
// for character, via Swift raw string literals `#"..."#` so `\b`/`\s`/etc.
// need no re-escaping), not re-derived -- same discipline as
// ReceiptsMoneyText.swift/Diagnostics.swift for this class of cross-engine
// risk. None of these patterns use the `g` (global) flag in the TS
// source, only `i` (case-insensitive) -- `.caseInsensitive` plus
// `matchesAnywhere` (an existence check, matching JS's stateless
// `RegExp.test()` for a non-global pattern) is the faithful port.

public let GUARDRAIL_CATEGORY_INJECTION = "injection" // attempts to override/reveal system instructions
public let GUARDRAIL_CATEGORY_EXFILTRATION = "exfiltration" // attempts to read other users' or raw DB data
public let GUARDRAIL_CATEGORY_SECRETS = "secrets" // attempts to extract API keys / tokens / env
public let GUARDRAIL_CATEGORY_MALWARE = "malware" // requests to write exploits / malicious code
public let GUARDRAIL_CATEGORY_HARMFUL = "harmful" // weapons, CSAM, self-harm facilitation, etc.

public struct GuardrailResult: Sendable {
    public let allow: Bool
    public let category: String?
    public let reason: String?

    public init(allow: Bool, category: String? = nil, reason: String? = nil) {
        self.allow = allow
        self.category = category
        self.reason = reason
    }
}

private struct GuardrailRule {
    let category: String
    let reason: String
    let test: NSRegularExpression
}

// Each rule is intentionally narrow to avoid false positives on real
// financial questions. Ordering is priority order (first match wins).
private let GUARDRAIL_RULES: [GuardrailRule] = [
    // --- prompt injection / instruction override / prompt disclosure ---
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_INJECTION,
        reason: "Attempt to override system instructions.",
        test: rx(#"\b(ignore|disregard|forget|override|bypass)\b[\s\S]{0,40}\b(previous|prior|above|earlier|all)?\s*(instructions?|rules?|prompt|guidelines?|guardrails?)\b"#, [.caseInsensitive])
    ),
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_INJECTION,
        reason: "Attempt to reveal the system prompt.",
        test: rx(#"\b(reveal|show|print|repeat|output|display|leak|tell me)\b[\s\S]{0,40}\b(your\s+)?(system\s*prompt|initial\s*instructions?|persona|the\s+(text|prompt)\s+above|hidden\s+(prompt|instructions?))\b"#, [.caseInsensitive])
    ),
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_INJECTION,
        reason: "Jailbreak / role-override attempt.",
        test: rx(#"\b(you are now|pretend (to be|you)|act as (if|though|an?)|from now on you|developer mode|jailbreak|DAN mode|do anything now|unfiltered|no (restrictions|rules|guardrails))\b"#, [.caseInsensitive])
    ),
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_INJECTION,
        reason: "Injected control tokens / fake roles.",
        test: rx(#"(^|\n)\s*(system|assistant|developer)\s*:|</?(system|assistant|instructions?)>|\[/?INST\]|<\|.*?\|>"#, [.caseInsensitive])
    ),

    // --- data exfiltration (other users / raw DB) ---
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_EXFILTRATION,
        reason: "Attempt to access other users' data.",
        test: rx(#"\b(other|another|someone else'?s|every|all|other people'?s)\s+(users?|people|persons?|accounts?|customers?|members?)\b[\s\S]{0,40}\b(data|transactions?|balance|info|records?|passwords?|account)\b"#, [.caseInsensitive])
    ),
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_EXFILTRATION,
        reason: "Attempt to run raw database queries / dumps.",
        test: rx(#"(select\s+\*|drop\s+table|delete\s+from|insert\s+into|update\s+.+\s+set|dump (the )?(database|db|table)|raw (sql|query)|union\s+select)"#, [.caseInsensitive])
    ),
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_EXFILTRATION,
        reason: "Attempt to enumerate the whole database.",
        test: rx(#"\b(list|show|give me|export)\b[\s\S]{0,30}\b(all|every)\s+(users?|accounts?|rows?|records?|customers?)\b"#, [.caseInsensitive])
    ),

    // --- secret / credential harvesting ---
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_SECRETS,
        reason: "Attempt to extract secrets or credentials.",
        test: rx(#"\b(api[_\s-]?key|secret[_\s-]?key|service[_\s-]?role|access[_\s-]?token|bearer\s+token|env(ironment)?\s+(vars?|variables?)|\.env|private\s+key|password|credentials?|connection\s+string)\b"#, [.caseInsensitive])
    ),
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_SECRETS,
        reason: "Attempt to read server configuration.",
        test: rx(#"\b(anthropic|openai|supabase|alphavantage|stripe|razorpay)\b[\s\S]{0,20}\b(key|token|secret)\b"#, [.caseInsensitive])
    ),

    // --- malware / exploit code generation ---
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_MALWARE,
        reason: "Request to generate malicious code.",
        test: rx(#"\b(write|create|generate|build|give me)\b[\s\S]{0,40}\b(malware|ransomware|keylogger|virus|worm|trojan|exploit|(sql|xss|csrf)\s*injection|phishing (page|kit|site)|backdoor|rootkit|botnet|ddos)\b"#, [.caseInsensitive])
    ),

    // --- harmful content ---
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_HARMFUL,
        reason: "Request facilitating weapons of mass harm.",
        test: rx(#"\b(how (to|do i|can i|would i|to i)\s+(make|build|synthesize|create|obtain|produce)|instructions? for|recipe for|steps? to (make|build|synthesize))\b[\s\S]{0,40}\b(bomb|explosive|nerve agent|bioweapon|chemical weapon|nuclear (device|weapon)|meth(amphetamine)?|napalm|ricin)\b"#, [.caseInsensitive])
    ),
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_HARMFUL,
        reason: "Request involving sexual content with minors.",
        test: rx(#"\b(child|minor|underage|preteen|teen)\b[\s\S]{0,25}\b(sex|sexual|nude|naked|porn|explicit)\b"#, [.caseInsensitive])
    ),
    GuardrailRule(
        category: GUARDRAIL_CATEGORY_HARMFUL,
        reason: "Request facilitating self-harm.",
        test: rx(#"\b(how (can|do) i|best way to|help me)\b[\s\S]{0,25}\b(kill myself|end my life|commit suicide|overdose|hurt myself)\b"#, [.caseInsensitive])
    ),
]

/// Screen a user prompt. Returns `{allow:false, category, reason}` for any
/// disallowed class, else `{allow:true}`. Empty/whitespace input is
/// allowed (the model handles empty turns). Never throws.
public func screenPrompt(_ input: String?) -> GuardrailResult {
    let text = (input ?? "").precomposedStringWithCompatibilityMapping // Swift's NFKC normalization
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return GuardrailResult(allow: true)
    }
    for rule in GUARDRAIL_RULES {
        if rule.test.matchesAnywhere(text) {
            return GuardrailResult(allow: false, category: rule.category, reason: rule.reason)
        }
    }
    return GuardrailResult(allow: true)
}

/// Mirrors the TS source's `unknown` message content: a plain string, or
/// an array of content blocks (only `{text: string}`-shaped blocks
/// contribute; everything else contributes "").
public enum MessageContent: Sendable {
    case text(String)
    case blocks([ContentBlock])
    case other
}

public struct ContentBlock: Sendable {
    public let text: String?
    public init(text: String?) { self.text = text }
}

public struct ConversationMessage: Sendable {
    public let role: String
    public let content: MessageContent
    public init(role: String, content: MessageContent) {
        self.role = role
        self.content = content
    }
}

/// Convenience: the single most-recent user message from a messages array.
public func screenConversation(_ messages: [ConversationMessage]) -> GuardrailResult {
    guard let lastUser = messages.last(where: { $0.role == "user" }) else {
        return GuardrailResult(allow: true)
    }
    let text: String
    switch lastUser.content {
    case .text(let s): text = s
    case .blocks(let blocks): text = blocks.map { $0.text ?? "" }.joined(separator: " ")
    case .other: text = ""
    }
    return screenPrompt(text)
}

/// Standard refusal message shown when the guardrail blocks a prompt.
public let REFUSAL_MESSAGE =
    "I can only help with your own PocketCare finances — budgets, spending, goals, and the like. I can't help with that request."
