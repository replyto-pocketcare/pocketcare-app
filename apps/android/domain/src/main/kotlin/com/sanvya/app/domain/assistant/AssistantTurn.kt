package com.sanvya.app.domain.assistant

/**
 * One turn of the assistant conversation — what the model said, and what the
 * app is allowed to do about it.
 *
 * Ported from `runTurn`, `trimHistory` and `resolvePending` in
 * `apps/web/src/assistant/AssistantChat.tsx`. Everything here is pure: the
 * network call and the database writes are the app's, but the DECISIONS —
 * which tool runs without asking, which is silently refused, which reaches a
 * confirmation card — are the same on every client and are vector-pinned.
 *
 * **This is the safety-critical half of the feature.** A tool that ran without
 * confirmation on one platform and with it on another would not be a rendering
 * difference; it would be a write to someone's ledger that they were never
 * asked about. That is why it is here and not in two view models.
 *
 * Mirrors iOS's AssistantTurn.swift.
 */

/** A tool call the model asked for. */
data class ToolUse(val id: String, val name: String, val input: ToolInput)

/** The blocks a model turn can contain. `tool_result` is only ever sent BY us. */
sealed interface AssistantContent {
    data class Text(val text: String) : AssistantContent
    data class Use(val use: ToolUse) : AssistantContent
    data class Result(val toolUseId: String, val content: String) : AssistantContent
}

/**
 * What the app should do with a model turn.
 *
 * The three tool lists are disjoint and exhaustive over the turn's tool calls.
 */
data class TurnPlan(
    /** The prose to show, already joined and trimmed. Empty when the turn was tools only. */
    val text: String,
    /** Runs immediately, no confirmation. Only tools web's CONFIRM_TOOLS omits. */
    val autoRun: List<ToolUse>,
    /** Never shown to the user at all — the model is told why and asked to link instead. */
    val rejected: List<ToolUse>,
    /** Shown one at a time as a confirmation card. */
    val confirmQueue: List<ToolUse>,
)

/**
 * What the model is told when a financial tool call is refused before the user
 * ever sees it.
 *
 * Web's wording, verbatim, and it is doing two jobs: it explains the refusal AND
 * it teaches the correct alternative in the same breath, which is why it names
 * `<ui>` and a route. A terser "invalid input" would get the same call retried.
 */
const val ASSISTANT_TOOL_REJECTED: String =
    "Not run: placeholder/invalid input. To take the user to a screen or search, " +
        "reply with a <ui> action href (e.g. /search?q=…) or a markdown link — " +
        "do NOT use a tool for navigation."

/** What the model is told when the user declines a confirmation. */
const val ASSISTANT_TOOL_DECLINED: String = "User declined this action."

/**
 * Messages sent to the model per turn. Memory carries what falls off the end.
 *
 * Web's own cap. It is a cost control as much as a context one: every message in
 * the window is re-sent and re-billed on every turn of a multi-step tool
 * exchange.
 */
const val ASSISTANT_HISTORY_CAP: Int = 16

/** Headroom for the structured `<ui>` block on top of the prose. Web's number. */
const val ASSISTANT_MAX_TOKENS: Int = 900

/** A thread's title is the first message, truncated. Web's `slice(0, 60)`. */
const val ASSISTANT_TITLE_MAX: Int = 60

/** One message in the model conversation. [textContent] is null for a tool-block turn. */
data class ApiMessage(
    /** "user" | "assistant". */
    val role: String,
    val textContent: String? = null,
    val blocks: List<AssistantContent> = emptyList(),
)

/**
 * Trim the conversation to the last [cap] messages, starting on a clean user turn.
 *
 * The second half is the load-bearing one and is easy to drop. A window that
 * opens on a `tool_result` or on an assistant turn is REJECTED by the API — the
 * first message of a conversation has to be a plain user message. Web shifts
 * until it finds one, and falls back to the single last message rather than
 * sending nothing.
 */
fun trimAssistantHistory(messages: List<ApiMessage>, cap: Int = ASSISTANT_HISTORY_CAP): List<ApiMessage> {
    val window = messages.takeLast(cap).toMutableList()
    while (window.isNotEmpty()) {
        val first = window.first()
        if (first.role == "user" && first.textContent != null) break
        window.removeAt(0)
    }
    return if (window.isNotEmpty()) window else messages.takeLast(1)
}

/**
 * Decide what to do with a model turn.
 *
 * The ordering of the three buckets is web's and each one is a deliberate
 * policy:
 *
 * * **autoRun** is everything web's `CONFIRM_TOOLS` set does NOT list. Today
 *   that is `remember` alone — the one tool that writes no money.
 * * **rejected** is a financial call whose arguments do not survive
 *   [isValidToolInput]. It never becomes a card. Web's comment names the case:
 *   the model firing `record_transaction` with amount 0 because the user asked
 *   to be taken somewhere. Showing that as "authorise a ₹0 expense?" would
 *   train the user to tap through confirmations.
 * * **confirmQueue** is the rest, ONE at a time, because a user who agrees to
 *   "create this goal" has not agreed to the transaction queued behind it.
 */
fun planAssistantTurn(content: List<AssistantContent>): TurnPlan {
    val text = content
        .filterIsInstance<AssistantContent.Text>()
        .joinToString("\n") { it.text }
        .trim()

    val toolUses = content.filterIsInstance<AssistantContent.Use>().map { it.use }
    val autoRun = toolUses.filterNot { assistantToolNeedsConfirm(it.name) }
    val confirmable = toolUses.filter { assistantToolNeedsConfirm(it.name) }

    return TurnPlan(
        text = text,
        autoRun = autoRun,
        rejected = confirmable.filterNot { isValidToolInput(it.name, it.input) },
        confirmQueue = confirmable.filter { isValidToolInput(it.name, it.input) },
    )
}

/** A thread's title, from its first message. */
fun assistantThreadTitle(firstMessage: String): String = firstMessage.take(ASSISTANT_TITLE_MAX)

/**
 * The transcript line written when a confirmation is resolved.
 *
 * Web's own glyphs. They are the only record in the thread that a write
 * happened — the tool blocks themselves are never persisted, so if this line is
 * wrong the user has no way to audit what the assistant did on their behalf.
 */
fun assistantActionNote(name: String, input: ToolInput, baseCurrency: String, confirmed: Boolean): String =
    if (confirmed) {
        "✓ " + describeToolCall(name, input, baseCurrency)
    } else {
        "✗ Skipped: " + describeToolCall(name, input, baseCurrency)
    }

/**
 * Which error message a failed call should show.
 *
 * Returns an i18n KEY rather than a string: web's `friendly()` calls `t(...)`
 * inline, and the native ports have to resolve through their own catalogues.
 * The matching is web's, in web's order — `errModel`'s pattern would also match
 * some network errors, so the order is not incidental.
 */
fun assistantErrorKey(error: String?): String {
    if (error.isNullOrEmpty()) return "errDefault"
    if (Regex("not configured|ANTHROPIC", RegexOption.IGNORE_CASE).containsMatchIn(error)) return "errNotConfigured"
    if (Regex("^model:|not_found|model .* (not|isn)", RegexOption.IGNORE_CASE).containsMatchIn(error)) return "errModel"
    if (Regex("network|fetch|Failed to send", RegexOption.IGNORE_CASE).containsMatchIn(error)) return "errNetwork"
    return "errGeneric"
}
