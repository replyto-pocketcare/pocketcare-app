package com.sanvya.app.domain.guardrail

// Ported from packages/core/guardrail/src/index.ts (P1.6a). Deterministic
// pre-flight screening for the AI assistant -- a defense-in-depth layer
// that runs BEFORE the model call, deterministically rejecting the
// classes of prompt we never want to reach the LLM (prompt injection,
// data exfiltration, secret/credential harvesting, malware/code
// generation, and clearly harmful requests). Must stay pure (no I/O) so
// it runs identically wherever it's called from.
//
// Every regex below is transcribed VERBATIM from the TS source (character
// for character, via Kotlin triple-quoted raw strings so `\b`/`\s`/etc.
// need no re-escaping), not re-derived -- same discipline as
// ReceiptsMoneyText.kt/Diagnostics.kt for this class of cross-engine risk.
// None of these patterns use the `g` (global) flag in the TS source, only
// `i` (case-insensitive) -- `RegexOption.IGNORE_CASE` plus Kotlin's
// `containsMatchIn` (an existence check, matching JS's stateless
// `RegExp.test()` for a non-global pattern) is the faithful port; no
// `MatchResult`/lastIndex statefulness to worry about either way.

const val GUARDRAIL_CATEGORY_INJECTION = "injection" // attempts to override/reveal system instructions
const val GUARDRAIL_CATEGORY_EXFILTRATION = "exfiltration" // attempts to read other users' or raw DB data
const val GUARDRAIL_CATEGORY_SECRETS = "secrets" // attempts to extract API keys / tokens / env
const val GUARDRAIL_CATEGORY_MALWARE = "malware" // requests to write exploits / malicious code
const val GUARDRAIL_CATEGORY_HARMFUL = "harmful" // weapons, CSAM, self-harm facilitation, etc.

data class GuardrailResult(
    val allow: Boolean,
    val category: String? = null,
    val reason: String? = null,
)

private data class Rule(val category: String, val reason: String, val test: Regex)

// Each rule is intentionally narrow to avoid false positives on real
// financial questions. Ordering is priority order (first match wins).
private val RULES: List<Rule> = listOf(
    // --- prompt injection / instruction override / prompt disclosure ---
    Rule(
        GUARDRAIL_CATEGORY_INJECTION,
        "Attempt to override system instructions.",
        Regex(
            """\b(ignore|disregard|forget|override|bypass)\b[\s\S]{0,40}\b(previous|prior|above|earlier|all)?\s*(instructions?|rules?|prompt|guidelines?|guardrails?)\b""",
            RegexOption.IGNORE_CASE,
        ),
    ),
    Rule(
        GUARDRAIL_CATEGORY_INJECTION,
        "Attempt to reveal the system prompt.",
        Regex(
            """\b(reveal|show|print|repeat|output|display|leak|tell me)\b[\s\S]{0,40}\b(your\s+)?(system\s*prompt|initial\s*instructions?|persona|the\s+(text|prompt)\s+above|hidden\s+(prompt|instructions?))\b""",
            RegexOption.IGNORE_CASE,
        ),
    ),
    Rule(
        GUARDRAIL_CATEGORY_INJECTION,
        "Jailbreak / role-override attempt.",
        Regex(
            """\b(you are now|pretend (to be|you)|act as (if|though|an?)|from now on you|developer mode|jailbreak|DAN mode|do anything now|unfiltered|no (restrictions|rules|guardrails))\b""",
            RegexOption.IGNORE_CASE,
        ),
    ),
    Rule(
        GUARDRAIL_CATEGORY_INJECTION,
        "Injected control tokens / fake roles.",
        Regex(
            """(^|\n)\s*(system|assistant|developer)\s*:|</?(system|assistant|instructions?)>|\[/?INST\]|<\|.*?\|>""",
            RegexOption.IGNORE_CASE,
        ),
    ),

    // --- data exfiltration (other users / raw DB) ---
    Rule(
        GUARDRAIL_CATEGORY_EXFILTRATION,
        "Attempt to access other users' data.",
        Regex(
            """\b(other|another|someone else'?s|every|all|other people'?s)\s+(users?|people|persons?|accounts?|customers?|members?)\b[\s\S]{0,40}\b(data|transactions?|balance|info|records?|passwords?|account)\b""",
            RegexOption.IGNORE_CASE,
        ),
    ),
    Rule(
        GUARDRAIL_CATEGORY_EXFILTRATION,
        "Attempt to run raw database queries / dumps.",
        Regex(
            """(select\s+\*|drop\s+table|delete\s+from|insert\s+into|update\s+.+\s+set|dump (the )?(database|db|table)|raw (sql|query)|union\s+select)""",
            RegexOption.IGNORE_CASE,
        ),
    ),
    Rule(
        GUARDRAIL_CATEGORY_EXFILTRATION,
        "Attempt to enumerate the whole database.",
        Regex(
            """\b(list|show|give me|export)\b[\s\S]{0,30}\b(all|every)\s+(users?|accounts?|rows?|records?|customers?)\b""",
            RegexOption.IGNORE_CASE,
        ),
    ),

    // --- secret / credential harvesting ---
    Rule(
        GUARDRAIL_CATEGORY_SECRETS,
        "Attempt to extract secrets or credentials.",
        Regex(
            """\b(api[_\s-]?key|secret[_\s-]?key|service[_\s-]?role|access[_\s-]?token|bearer\s+token|env(ironment)?\s+(vars?|variables?)|\.env|private\s+key|password|credentials?|connection\s+string)\b""",
            RegexOption.IGNORE_CASE,
        ),
    ),
    Rule(
        GUARDRAIL_CATEGORY_SECRETS,
        "Attempt to read server configuration.",
        Regex(
            """\b(anthropic|openai|supabase|alphavantage|stripe|razorpay)\b[\s\S]{0,20}\b(key|token|secret)\b""",
            RegexOption.IGNORE_CASE,
        ),
    ),

    // --- malware / exploit code generation ---
    Rule(
        GUARDRAIL_CATEGORY_MALWARE,
        "Request to generate malicious code.",
        Regex(
            """\b(write|create|generate|build|give me)\b[\s\S]{0,40}\b(malware|ransomware|keylogger|virus|worm|trojan|exploit|(sql|xss|csrf)\s*injection|phishing (page|kit|site)|backdoor|rootkit|botnet|ddos)\b""",
            RegexOption.IGNORE_CASE,
        ),
    ),

    // --- harmful content ---
    Rule(
        GUARDRAIL_CATEGORY_HARMFUL,
        "Request facilitating weapons of mass harm.",
        Regex(
            """\b(how (to|do i|can i|would i|to i)\s+(make|build|synthesize|create|obtain|produce)|instructions? for|recipe for|steps? to (make|build|synthesize))\b[\s\S]{0,40}\b(bomb|explosive|nerve agent|bioweapon|chemical weapon|nuclear (device|weapon)|meth(amphetamine)?|napalm|ricin)\b""",
            RegexOption.IGNORE_CASE,
        ),
    ),
    Rule(
        GUARDRAIL_CATEGORY_HARMFUL,
        "Request involving sexual content with minors.",
        Regex(
            """\b(child|minor|underage|preteen|teen)\b[\s\S]{0,25}\b(sex|sexual|nude|naked|porn|explicit)\b""",
            RegexOption.IGNORE_CASE,
        ),
    ),
    Rule(
        GUARDRAIL_CATEGORY_HARMFUL,
        "Request facilitating self-harm.",
        Regex(
            """\b(how (can|do) i|best way to|help me)\b[\s\S]{0,25}\b(kill myself|end my life|commit suicide|overdose|hurt myself)\b""",
            RegexOption.IGNORE_CASE,
        ),
    ),
)

/**
 * Screen a user prompt. Returns `{allow=false, category, reason}` for any
 * disallowed class, else `{allow=true}`. Empty/whitespace input is
 * allowed (the model handles empty turns). Never throws.
 */
fun screenPrompt(input: String?): GuardrailResult {
    val text = java.text.Normalizer.normalize(input ?: "", java.text.Normalizer.Form.NFKC)
    if (text.isBlank()) return GuardrailResult(allow = true)
    for (rule in RULES) {
        if (rule.test.containsMatchIn(text)) {
            return GuardrailResult(allow = false, category = rule.category, reason = rule.reason)
        }
    }
    return GuardrailResult(allow = true)
}

data class ConversationMessage(val role: String, val content: MessageContent)

/** Mirrors the TS source's `unknown` message content: a plain string, or
 * an array of content blocks (only `{text: string}`-shaped blocks
 * contribute; everything else contributes ""). */
sealed class MessageContent {
    data class Text(val value: String) : MessageContent()
    data class Blocks(val value: List<ContentBlock>) : MessageContent()
    object Other : MessageContent()
}

data class ContentBlock(val text: String?)

/** Convenience: the single most-recent user message from a messages array. */
fun screenConversation(messages: List<ConversationMessage>): GuardrailResult {
    val lastUser = messages.lastOrNull { it.role == "user" } ?: return GuardrailResult(allow = true)
    val text = when (val c = lastUser.content) {
        is MessageContent.Text -> c.value
        is MessageContent.Blocks -> c.value.joinToString(" ") { it.text ?: "" }
        is MessageContent.Other -> ""
    }
    return screenPrompt(text)
}

/** Standard refusal message shown when the guardrail blocks a prompt. */
const val REFUSAL_MESSAGE =
    "I can only help with your own Sanvya finances — budgets, spending, goals, and the like. I can't help with that request."
