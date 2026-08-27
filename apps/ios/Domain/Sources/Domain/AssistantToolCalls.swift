import Foundation

/**
 Validating and describing a tool call before it runs.

 Ported from `apps/web/src/assistant/tools.ts` — `isValidToolInput` and
 `describeToolCall`. Executing a call is repository work and lives in the app;
 deciding whether it is even worth showing, and what the confirm card says, is
 not, and both have to read identically on every client.

 `describeToolCall`'s string is what the user reads before authorising a write to
 their ledger. That makes it the single most consequential sentence in this
 feature, and the reason it is here under vectors rather than formatted at each
 call site.

 Mirrors Android's AssistantToolCalls.kt.
 */

/// A tool call's arguments, as the model sent them.
public typealias ToolInput = [String: AssistantJson]

private extension Dictionary where Key == String, Value == AssistantJson {
    func string(_ key: String) -> String? {
        if case let .str(s) = self[key] { return s }
        return nil
    }

    /// `typeof v === "string" && v.trim().length > 0`.
    func nonBlank(_ key: String) -> Bool {
        guard let s = string(key) else { return false }
        return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `typeof v === "number" && Number.isFinite(v) && v > 0`.
    func positive(_ key: String) -> Bool {
        guard case let .num(n) = self[key] else { return false }
        return n.isFinite && n > 0
    }

    /**
     How a value the model sent is spelled back to the user.

     Web interpolates the raw value into a template literal, so a number arrives
     through JS's own number-to-string. `79900` reads as "79900" there and would
     read as "79900.0" through a naive `"\(d)"`, on the one line in this feature
     the user is asked to authorise.
     */
    func text(_ key: String) -> String {
        switch self[key] {
        case .none, .some(.null): return "undefined"
        case let .some(.str(s)): return s
        case let .some(.bool(b)): return b ? "true" : "false"
        case let .some(.num(n)): return jsonNumber(n)
        case .some(.arr), .some(.obj): return "[object]"
        }
    }

    /// JS truthiness for the optional trailing clauses: absent, empty or 0 all drop the clause.
    func truthy(_ key: String) -> Bool {
        switch self[key] {
        case .none, .some(.null): return false
        case let .some(.str(s)): return !s.isEmpty
        case let .some(.bool(b)): return b
        case let .some(.num(n)): return n != 0 && !n.isNaN
        case .some(.arr), .some(.obj): return true
        }
    }
}

/**
 Reject obviously-invalid or placeholder calls.

 Web's own comment names the case this exists for: the model firing
 `record_transaction` with amount 0 for what was really a navigation request. An
 invalid call is never shown as a confirm card at all — the model is told to use
 a link instead — so this is the difference between a stray token and a dialog
 asking the user to authorise a zero-rupee expense.

 An UNKNOWN name returns true, matching web's `default`. That is deliberate:
 this function's job is catching nonsense arguments, not policing the tool list,
 and the tool list is generated from one source anyway.
 */
public func isValidToolInput(_ name: String, _ input: ToolInput) -> Bool {
    switch name {
    case "record_transaction":
        return input.positive("amount")
            && (input.string("type") == "expense" || input.string("type") == "income")
    case "create_goal": return input.nonBlank("name") && input.positive("target_amount")
    case "reserve_to_goal": return input.nonBlank("goal_name") && input.positive("amount")
    case "create_budget": return input.nonBlank("name") && input.positive("limit_amount")
    case "create_subscription": return input.nonBlank("name") && input.positive("amount")
    case "create_group": return input.nonBlank("name")
    default: return true
    }
}

/**
 One line describing a proposed action, for the confirm card.

 The curly quotes and the middle dots are web's, character for character. They
 are not decoration: this is the string the two apps and the browser must all
 show for the same call, and `Create goal "X"` versus `Create goal “X”` is a
 visible difference on the one screen where trust is being asked for.
 */
public func describeToolCall(_ name: String, _ input: ToolInput, baseCurrency: String) -> String {
    let cur = input.string("currency").flatMap { $0.isEmpty ? nil : $0 } ?? baseCurrency
    switch name {
    case "create_goal":
        let by = input.truthy("by_date") ? " by \(input.text("by_date"))" : ""
        return "Create goal “\(input.text("name"))” — target \(cur) \(input.text("target_amount"))\(by)"

    case "reserve_to_goal":
        return "Reserve \(cur) \(input.text("amount")) toward “\(input.text("goal_name"))”"

    case "create_budget":
        return "Create \(input.text("period")) budget “\(input.text("name"))” — limit \(cur) \(input.text("limit_amount"))"

    case "record_transaction":
        let desc = input.truthy("description") ? " — \(input.text("description"))" : ""
        let acct = input.truthy("account") ? " (\(input.text("account")))" : ""
        return "Record \(input.text("type")) of \(cur) \(input.text("amount"))\(desc)\(acct)"

    case "create_subscription":
        // `String(input.billing_cycle).replace("ly", "")` — a STRING pattern, so
        // JS replaces only the FIRST occurrence. "monthly" becomes "month"
        // either way; the distinction is copied because the day a cycle contains
        // a second "ly" the two must still agree.
        let cycle = input.text("billing_cycle")
        let trimmed: String
        if let r = cycle.range(of: "ly") {
            trimmed = cycle.replacingCharacters(in: r, with: "")
        } else {
            trimmed = cycle
        }
        return "Add subscription “\(input.text("name"))” — \(cur) \(input.text("amount"))/\(trimmed)"

    case "create_group":
        var dates = ""
        if input.truthy("start_date") {
            let end = input.truthy("end_date") ? "–\(input.text("end_date"))" : ""
            dates = " · \(input.text("start_date"))\(end)"
        }
        let auto = input.truthy("auto_split") ? " · auto-split" : ""
        return "Create \(input.text("kind")) “\(input.text("name"))”\(dates)\(auto)"

    case "remember":
        return "Remembered: \(input.text("fact"))"

    default:
        return "Run \(name)"
    }
}
