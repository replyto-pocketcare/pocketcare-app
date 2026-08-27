import Foundation

/**
 One turn of the assistant conversation — what the model said, and what the app
 is allowed to do about it.

 Ported from `runTurn`, `trimHistory` and `resolvePending` in
 `apps/web/src/assistant/AssistantChat.tsx`. Everything here is pure: the network
 call and the database writes are the app's, but the DECISIONS — which tool runs
 without asking, which is silently refused, which reaches a confirmation card —
 are the same on every client and are vector-pinned.

 **This is the safety-critical half of the feature.** A tool that ran without
 confirmation on one platform and with it on another would not be a rendering
 difference; it would be a write to someone's ledger that they were never asked
 about. That is why it is here and not in two view models.

 Mirrors Android's AssistantTurn.kt.
 */

/// A tool call the model asked for.
public struct ToolUse: Equatable, Sendable {
    public let id: String
    public let name: String
    public let input: ToolInput
    public init(id: String, name: String, input: ToolInput) {
        self.id = id
        self.name = name
        self.input = input
    }
}

/// The blocks a model turn can contain. `tool_result` is only ever sent BY us.
public enum AssistantContent: Equatable, Sendable {
    case text(String)
    case use(ToolUse)
    case result(toolUseId: String, content: String)
}

/**
 What the app should do with a model turn.

 The three tool lists are disjoint and exhaustive over the turn's tool calls.
 */
public struct TurnPlan: Equatable, Sendable {
    /// The prose to show, already joined and trimmed. Empty when the turn was tools only.
    public let text: String
    /// Runs immediately, no confirmation. Only tools web's CONFIRM_TOOLS omits.
    public let autoRun: [ToolUse]
    /// Never shown to the user at all — the model is told why and asked to link instead.
    public let rejected: [ToolUse]
    /// Shown one at a time as a confirmation card.
    public let confirmQueue: [ToolUse]
}

/**
 What the model is told when a financial tool call is refused before the user
 ever sees it.

 Web's wording, verbatim, and it is doing two jobs: it explains the refusal AND
 it teaches the correct alternative in the same breath, which is why it names
 `<ui>` and a route. A terser "invalid input" would get the same call retried.
 */
public let assistantToolRejected =
    "Not run: placeholder/invalid input. To take the user to a screen or search, "
    + "reply with a <ui> action href (e.g. /search?q=…) or a markdown link — "
    + "do NOT use a tool for navigation."

/// What the model is told when the user declines a confirmation.
public let assistantToolDeclined = "User declined this action."

/**
 Messages sent to the model per turn. Memory carries what falls off the end.

 Web's own cap. It is a cost control as much as a context one: every message in
 the window is re-sent and re-billed on every turn of a multi-step tool exchange.
 */
public let assistantHistoryCap = 16

/// Headroom for the structured `<ui>` block on top of the prose. Web's number.
public let assistantMaxTokens = 900

/// A thread's title is the first message, truncated. Web's `slice(0, 60)`.
public let assistantTitleMax = 60

/// One message in the model conversation. `textContent` is nil for a tool-block turn.
public struct ApiMessage: Equatable, Sendable {
    /// "user" | "assistant".
    public let role: String
    public let textContent: String?
    public let blocks: [AssistantContent]

    public init(role: String, textContent: String? = nil, blocks: [AssistantContent] = []) {
        self.role = role
        self.textContent = textContent
        self.blocks = blocks
    }
}

/**
 Trim the conversation to the last `cap` messages, starting on a clean user turn.

 The second half is the load-bearing one and is easy to drop. A window that opens
 on a `tool_result` or on an assistant turn is REJECTED by the API — the first
 message of a conversation has to be a plain user message. Web shifts until it
 finds one, and falls back to the single last message rather than sending nothing.
 */
public func trimAssistantHistory(_ messages: [ApiMessage], cap: Int = assistantHistoryCap) -> [ApiMessage] {
    var window = Array(messages.suffix(cap))
    while let first = window.first {
        if first.role == "user" && first.textContent != nil { break }
        window.removeFirst()
    }
    return window.isEmpty ? Array(messages.suffix(1)) : window
}

/**
 Decide what to do with a model turn.

 The ordering of the three buckets is web's and each one is a deliberate policy:

 * **autoRun** is everything web's `CONFIRM_TOOLS` set does NOT list. Today that
   is `remember` alone — the one tool that writes no money.
 * **rejected** is a financial call whose arguments do not survive
   `isValidToolInput`. It never becomes a card. Web's comment names the case: the
   model firing `record_transaction` with amount 0 because the user asked to be
   taken somewhere. Showing that as "authorise a ₹0 expense?" would train the
   user to tap through confirmations.
 * **confirmQueue** is the rest, ONE at a time, because a user who agrees to
   "create this goal" has not agreed to the transaction queued behind it.
 */
public func planAssistantTurn(_ content: [AssistantContent]) -> TurnPlan {
    var texts: [String] = []
    var toolUses: [ToolUse] = []
    for block in content {
        switch block {
        case let .text(t): texts.append(t)
        case let .use(u): toolUses.append(u)
        case .result: break
        }
    }
    let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    let confirmable = toolUses.filter { assistantToolNeedsConfirm($0.name) }

    return TurnPlan(
        text: text,
        autoRun: toolUses.filter { !assistantToolNeedsConfirm($0.name) },
        rejected: confirmable.filter { !isValidToolInput($0.name, $0.input) },
        confirmQueue: confirmable.filter { isValidToolInput($0.name, $0.input) }
    )
}

/// A thread's title, from its first message.
public func assistantThreadTitle(_ firstMessage: String) -> String {
    String(firstMessage.prefix(assistantTitleMax))
}

/**
 The transcript line written when a confirmation is resolved.

 Web's own glyphs. They are the only record in the thread that a write happened —
 the tool blocks themselves are never persisted, so if this line is wrong the
 user has no way to audit what the assistant did on their behalf.
 */
public func assistantActionNote(
    _ name: String,
    _ input: ToolInput,
    baseCurrency: String,
    confirmed: Bool
) -> String {
    let described = describeToolCall(name, input, baseCurrency: baseCurrency)
    return confirmed ? "✓ " + described : "✗ Skipped: " + described
}

/**
 Which error message a failed call should show.

 Returns an i18n KEY rather than a string: web's `friendly()` calls `t(…)` inline,
 and the native ports have to resolve through their own catalogues. The matching
 is web's, in web's order — `errModel`'s pattern would also match some network
 errors, so the order is not incidental.
 */
public func assistantErrorKey(_ error: String?) -> String {
    guard let error, !error.isEmpty else { return "errDefault" }
    func hit(_ pattern: String) -> Bool {
        error.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    if hit("not configured|ANTHROPIC") { return "errNotConfigured" }
    if hit("^model:|not_found|model .* (not|isn)") { return "errModel" }
    if hit("network|fetch|Failed to send") { return "errNetwork" }
    return "errGeneric"
}

/**
 The remaining-queries chip, as both screens draw it.

 Web renders `{planLeft} / {total}` plus a `+N credits` suffix, and colours the
 chip when nothing is left. Splitting plan allowance from purchased credits is
 the load-bearing part: credits never expire and the plan allowance refills, so
 "3 / 50 +12 credits" and "15 / 50" are different situations wearing similar
 numbers.
 */
public struct EntitlementQuota: Equatable, Sendable {
    /// What is left of the monthly allowance, floored at zero.
    public let planLeft: Int
    public let total: Int
    /// Purchased credits, which do not expire.
    public let purchased: Int
    /// planLeft + purchased. Zero means the composer is disabled.
    public let left: Int
    /// ISO date the monthly allowance refills, when known.
    public let resetDate: String?

    public init(planLeft: Int, total: Int, purchased: Int, left: Int, resetDate: String?) {
        self.planLeft = planLeft
        self.total = total
        self.purchased = purchased
        self.left = left
        self.resetDate = resetDate
    }
}

