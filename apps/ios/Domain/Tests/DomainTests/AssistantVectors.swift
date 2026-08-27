import Foundation
@testable import Domain

// Wires the assistant's parser into FunctionRegistry.
//
// Where the fixtures come from, which differs per function and matters:
//
//   * `assistantCompactNum`, `parseAssistantBlocks` and `parseAssistantMessage`
//     were produced by RUNNING web's real code. The JSX-free functions were
//     lifted out of richMessage.tsx verbatim — every extracted block was diffed
//     back against the source to prove nothing changed — and executed.
//   * `assistantInlineSpans` could NOT be, because web's `inline()` returns
//     React elements and there is no value to capture. Its regex and branch
//     order were copied character-for-character and verified against the source;
//     the reference that produced these expectations emits spans instead of
//     elements. It proves Android and iOS agree, not that either matches a
//     browser.
//
// The serialisers below drop nils rather than emitting NSNull, because
// JSON.stringify drops `undefined` and web's card literals set `sub`/`value`/
// `pct` to exactly that when absent.

/// Foundation's `Any` tree -> Domain's own. This is the adapter the app needs too.
private func toAssistantJson(_ any: Any) -> AssistantJson {
    switch any {
    case is NSNull:
        return .null
    case let s as String:
        return .str(s)
    case let n as NSNumber:
        // NSNumber does not distinguish a Bool from a 0/1 Int by type, only by
        // its ObjC type encoding. Getting this wrong would turn `true` into 1
        // and quietly change what `clampPct` sees.
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
        return .num(n.doubleValue)
    case let a as [Any]:
        return .arr(a.map(toAssistantJson))
    case let o as [String: Any]:
        return .obj(o.mapValues(toAssistantJson))
    default:
        return .null
    }
}

private func drop(_ pairs: [(String, Any?)]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (k, v) in pairs where v != nil { out[k] = v! }
    return out
}

private func blockToJson(_ b: AssistantBlock) -> [String: Any] {
    switch b {
    case let .heading(level, text):
        return ["t": "h", "level": level, "text": text]
    case let .paragraph(lines):
        return ["t": "p", "lines": lines]
    case let .bullets(items):
        return [
            "t": "ul",
            "items": items.map { it in
                drop([
                    ("text", it.text),
                    // Absent, not false: a plain bullet has no `task` key at all.
                    ("task", it.task ? true : nil),
                    ("checked", it.task ? it.checked : nil),
                ])
            },
        ]
    case let .ordered(items):
        return ["t": "ol", "items": items]
    case let .quote(lines):
        return ["t": "quote", "lines": lines]
    case let .table(header, rows):
        return ["t": "table", "header": header, "rows": rows]
    case .rule:
        return ["t": "hr"]
    case let .code(text):
        return ["t": "code", "text": text]
    }
}

private func cardToJson(_ c: AssistantCard) -> [String: Any] {
    switch c {
    case let .stat(s):
        return drop([("kind", "stat"), ("label", s.label), ("value", s.value), ("sub", s.sub), ("tone", s.tone)])
    case let .progress(p):
        return drop([("kind", "progress"), ("label", p.label), ("value", p.value), ("pct", p.pct)])
    case let .breakdown(b):
        return [
            "kind": "breakdown",
            "label": b.label,
            "items": b.items.map { drop([("label", $0.label), ("value", $0.value), ("pct", $0.pct)]) },
        ]
    case let .chart(ch):
        return drop([
            ("kind", "chart"),
            ("label", ch.label),
            ("chart", ch.chart),
            ("points", ch.points.map { ["x": $0.x, "y": $0.y] as [String: Any] }),
            ("value", ch.value),
        ])
    }
}

private func actionToJson(_ a: AssistantAction) -> [String: Any] {
    drop([("label", a.label), ("send", a.send), ("href", a.href)])
}

private func spanToJson(_ s: InlineSpan) -> [String: Any] {
    drop([("t", s.kind.rawValue), ("s", s.text), ("href", s.href)])
}

private func toSummary(_ any: Any) -> FinancialSummary {
    let d = any as! [String: Any]
    func num(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
    func str(_ k: String) -> String { d[k] as? String ?? "" }
    func rows(_ k: String) -> [[String: Any]] { d[k] as? [[String: Any]] ?? [] }

    let splits = d["splits"] as? [String: Any] ?? [:]
    return FinancialSummary(
        baseCurrency: str("baseCurrency"),
        today: str("today"),
        accounts: rows("accounts").map {
            SummaryAccount(
                id: $0["id"] as! String,
                name: $0["name"] as! String,
                type: $0["type"] as! String,
                currency: $0["currency"] as! String,
                balance: ($0["balance"] as! NSNumber).doubleValue
            )
        },
        liquidSavings: num("liquidSavings"),
        avgMonthlyIncome: num("avgMonthlyIncome"),
        avgMonthlyExpense: num("avgMonthlyExpense"),
        monthlySurplus: num("monthlySurplus"),
        fixedMonthlyObligations: num("fixedMonthlyObligations"),
        goals: rows("goals").map {
            SummaryGoal(
                name: $0["name"] as! String,
                target: ($0["target"] as! NSNumber).doubleValue,
                saved: ($0["saved"] as! NSNumber).doubleValue,
                currency: $0["currency"] as! String
            )
        },
        upcoming: rows("upcoming").map {
            SummaryUpcoming(
                name: $0["name"] as! String,
                date: $0["date"] as! String,
                amount: ($0["amount"] as! NSNumber).doubleValue,
                currency: $0["currency"] as! String
            )
        },
        splits: SummarySplits(
            owed: (splits["owed"] as? NSNumber)?.doubleValue ?? 0,
            owe: (splits["owe"] as? NSNumber)?.doubleValue ?? 0,
            groups: (splits["groups"] as? NSNumber)?.intValue ?? 0
        ),
        monthlyCashflow: rows("monthlyCashflow").map {
            SummaryMonth(
                ym: $0["ym"] as! String,
                income: ($0["income"] as! NSNumber).doubleValue,
                expense: ($0["expense"] as! NSNumber).doubleValue
            )
        },
        topCategories: rows("topCategories").map {
            SummaryCategory(name: $0["name"] as! String, amount: ($0["amount"] as! NSNumber).doubleValue)
        }
    )
}

private func assistantJsonToAny(_ j: AssistantJson) -> Any {
    switch j {
    case let .str(v): return v
    case let .num(v): return v
    case let .bool(v): return v
    case let .arr(v): return v.map(assistantJsonToAny)
    case let .obj(v): return v.mapValues(assistantJsonToAny)
    case .null: return NSNull()
    }
}

private func toContentBlock(_ any: Any) -> AssistantContent {
    let d = any as! [String: Any]
    switch d["type"] as! String {
    case "text":
        return .text(d["text"] as! String)
    case "tool_use":
        guard case let .obj(args) = toAssistantJson(d["input"] ?? [String: Any]()) else {
            return .use(ToolUse(id: d["id"] as! String, name: d["name"] as! String, input: [:]))
        }
        return .use(ToolUse(id: d["id"] as! String, name: d["name"] as! String, input: args))
    default:
        return .result(toolUseId: d["tool_use_id"] as! String, content: d["content"] as! String)
    }
}

private func contentBlockToJson(_ b: AssistantContent) -> [String: Any] {
    switch b {
    case let .text(t):
        return ["type": "text", "text": t]
    case let .use(u):
        return ["type": "tool_use", "id": u.id, "name": u.name, "input": u.input.mapValues(assistantJsonToAny)]
    case let .result(id, content):
        return ["type": "tool_result", "tool_use_id": id, "content": content]
    }
}

private func toApiMessage(_ any: Any) -> ApiMessage {
    let d = any as! [String: Any]
    return ApiMessage(
        role: d["role"] as! String,
        textContent: d["text"] as? String,
        blocks: (d["blocks"] as? [Any])?.map(toContentBlock) ?? []
    )
}

private func apiMessageToJson(_ m: ApiMessage) -> [String: Any] {
    var out: [String: Any] = ["role": m.role]
    // Absent, not NSNull: web's messages carry EITHER a string content or a
    // block array, never both, and JSON.stringify drops the other.
    if let t = m.textContent { out["text"] = t }
    if !m.blocks.isEmpty { out["blocks"] = m.blocks.map(contentBlockToJson) }
    return out
}

private func voiceStatus(_ input: Any) -> VoiceStatus {
    let d = input as! [String: Any]
    return VoiceStatus(rawValue: d["status"] as! String)!
}

func registerAssistantVectors() {
    let domain = "assistant"

    FunctionRegistry.register(domain: domain, fn: "trimAssistantHistory") { input in
        let d = input as! [String: Any]
        let msgs = (d["messages"] as! [Any]).map(toApiMessage)
        return trimAssistantHistory(msgs).map(apiMessageToJson)
    }

    FunctionRegistry.register(domain: domain, fn: "planAssistantTurn") { input in
        let d = input as! [String: Any]
        let plan = planAssistantTurn((d["content"] as! [Any]).map(toContentBlock))
        return [
            "text": plan.text,
            // Ids only: the fixture proves which BUCKET each call landed in, and
            // the calls themselves are the input.
            "autoRun": plan.autoRun.map(\.id),
            "rejected": plan.rejected.map(\.id),
            "confirmQueue": plan.confirmQueue.map(\.id),
        ] as [String: Any]
    }

    FunctionRegistry.register(domain: domain, fn: "mergeDictation") { input in
        let d = input as! [String: Any]
        return mergeDictation(base: d["base"] as! String, spoken: d["spoken"] as! String)
    }

    // The three status-shaped ones travel by NAME, not by ordinal: an enum's
    // ordinal is a property of the declaration order, and the whole point of a
    // shared fixture is that it survives someone reordering one platform's.
    FunctionRegistry.register(domain: domain, fn: "voiceLabelKey") { input in
        voiceLabelKey(voiceStatus(input))
    }

    FunctionRegistry.register(domain: domain, fn: "voiceActive") { input in
        voiceActive(voiceStatus(input))
    }

    FunctionRegistry.register(domain: domain, fn: "voiceTappable") { input in
        voiceTappable(voiceStatus(input))
    }

    FunctionRegistry.register(domain: domain, fn: "assistantErrorKey") { input in
        let d = input as! [String: Any]
        return assistantErrorKey(d["error"] as? String)
    }

    FunctionRegistry.register(domain: domain, fn: "jsonNumber") { input in
        let d = input as! [String: Any]
        // NaN and the infinities cannot survive a JSON fixture, so they travel
        // as a name and are rebuilt here.
        let v: Double
        switch d["special"] as? String {
        case "NaN": v = Double.nan
        case "Infinity": v = Double.infinity
        case "-Infinity": v = -Double.infinity
        default: v = (d["v"] as! NSNumber).doubleValue
        }
        return jsonNumber(v)
    }

    FunctionRegistry.register(domain: domain, fn: "assistantCompactNum") { input in
        let d = input as! [String: Any]
        return assistantCompactNum((d["n"] as! NSNumber).doubleValue)
    }

    FunctionRegistry.register(domain: domain, fn: "parseAssistantBlocks") { input in
        let d = input as! [String: Any]
        return parseAssistantBlocks(d["src"] as! String).map(blockToJson)
    }

    FunctionRegistry.register(domain: domain, fn: "assistantInlineSpans") { input in
        let d = input as! [String: Any]
        return assistantInlineSpans(d["s"] as! String).map(spanToJson)
    }

    FunctionRegistry.register(domain: domain, fn: "isValidToolInput") { input in
        let d = input as! [String: Any]
        guard case let .obj(args) = toAssistantJson(d["args"]!) else { return false }
        return isValidToolInput(d["tool"] as! String, args)
    }

    FunctionRegistry.register(domain: domain, fn: "describeToolCall") { input in
        let d = input as! [String: Any]
        guard case let .obj(args) = toAssistantJson(d["args"]!) else { return "" }
        return describeToolCall(
            d["tool"] as! String,
            args,
            baseCurrency: d["baseCurrency"] as! String
        )
    }

    FunctionRegistry.register(domain: domain, fn: "summaryForPrompt") { input in
        let d = input as! [String: Any]
        return summaryForPrompt(toSummary(d["summary"]!))
    }

    FunctionRegistry.register(domain: domain, fn: "parseAssistantMessage") { input in
        // The composition a real screen performs: split, hand the payload to the
        // platform's JSON parser, validate. Registering it composed is the point
        // — it is the whole pipeline that has to match web, not the halves.
        let d = input as! [String: Any]
        let split = splitAssistantUi(d["raw"] as! String)
        var ui: AssistantUi?
        if let payload = split.json,
           let data = payload.data(using: .utf8),
           let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            ui = assistantUiFrom(toAssistantJson(any))
        }
        var out: [String: Any] = ["text": split.text]
        if let ui {
            out["ui"] = [
                "cards": ui.cards.map(cardToJson),
                "actions": ui.actions.map(actionToJson),
            ] as [String: Any]
        } else {
            out["ui"] = NSNull()
        }
        return out
    }
}
