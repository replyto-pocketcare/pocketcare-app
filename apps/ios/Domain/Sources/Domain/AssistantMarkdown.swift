import Foundation

/**
 The assistant's message parser — prose and the structured block it may append.

 Ported from the JSX-free half of `apps/web/src/assistant/richMessage.tsx`. The
 split is the same one the PDF work uses: what the model says is parsed
 identically on every client, and only the drawing is per-platform. A phone that
 disagreed with the browser about whether a line is a table row would render a
 different answer to the same question.

 Mirrors Android's AssistantMarkdown.kt.
 */

/**
 `Number.prototype.toFixed(1)`, which is not `String(format: "%.1f", …)`.

 Three languages, three answers, and the differences are visible: `1.15` formats
 as `1.1` in JS (nearest on the EXACT BINARY value, which is 1.14999…), as `1.2`
 through Java's `%.1f` (HALF_UP on the DECIMAL text), and C's printf — which
 `String(format:)` uses — rounds ties to EVEN and disagrees with both.

 ECMA-262 strips the sign FIRST and then breaks ties toward the larger digit, so
 a tie on a negative rounds AWAY from zero: `(-1.25).toFixed(1)` is `"-1.3"`,
 not `"-1.2"`. `Decimal(x)` is exact-binary and `.plain` on a positive is
 exactly that rule.
 */
func jsToFixed1(_ x: Double) -> String {
    let negative = x < 0
    var input = Decimal(negative ? -x : x)
    var rounded = Decimal()
    NSDecimalRound(&rounded, &input, 1, .plain)
    let text = NSDecimalNumber(decimal: rounded).stringValue
    // stringValue drops a trailing zero ("1.0" comes back as "1"), and toFixed
    // never does.
    let padded = text.contains(".") ? text : text + ".0"
    return (negative ? "-" : "") + padded
}

/// `Math.round` — half UP (toward +infinity), not half-away-from-zero.
private func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }

/**
 Indian-scale compact number: 1.2k, 3.4L, 1.2Cr.

 Lakh and crore rather than M and B, deliberately — this is web's own scale, and
 it is the one every other number on these screens uses.
 */
public func assistantCompactNum(_ n: Double) -> String {
    let magnitude = abs(n)
    if magnitude >= 1e7 { return "\(jsToFixed1(n / 1e7))Cr" }
    if magnitude >= 1e5 { return "\(jsToFixed1(n / 1e5))L" }
    if magnitude >= 1e3 { return "\(jsToFixed1(n / 1e3))k" }
    // `${Math.round(n)}` on a Double: JS prints -0 as "0", and so does this once
    // the value goes through Int.
    return String(Int(jsRound(n)))
}

// MARK: - inline formatting

/// What a run of inline text is.
public enum InlineKind: String, Sendable {
    case text, bold, italic, code, link
}

/// One run. `href` is set only for `.link`.
public struct InlineSpan: Equatable, Sendable {
    public let kind: InlineKind
    public let text: String
    public let href: String?
    public init(kind: InlineKind, text: String, href: String? = nil) {
        self.kind = kind
        self.text = text
        self.href = href
    }
}

/**
 The regex is web's, character for character. Its branch ORDER is load-bearing
 too: a link is tried before emphasis, so `[**a**](/x)` is a link whose label
 happens to contain asterisks rather than bold text followed by junk.
 */
private let inlineRxPattern =
    "\\[([^\\]]+)\\]\\(([^)\\s]+)\\)|\\*\\*([^*]+)\\*\\*|__([^_]+)__|\\*([^*\\n]+)\\*|`([^`]+)`"

/**
 Split a line into formatted runs.

 **The link filter is a security control, not formatting.** Only an internal
 route (`/…`) or an explicit http(s) URL becomes a link; anything else —
 `javascript:`, `data:`, a bare `evil.test` — degrades to the label as plain
 text. Web does the same and for the same reason: this string came from a
 language model, which can be talked into emitting whatever a user's transaction
 description tells it to.
 */
public func assistantInlineSpans(_ s: String) -> [InlineSpan] {
    guard let rx = try? NSRegularExpression(pattern: inlineRxPattern) else {
        return s.isEmpty ? [] : [InlineSpan(kind: .text, text: s)]
    }
    let ns = s as NSString
    var out: [InlineSpan] = []
    var last = 0

    for m in rx.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
        let whole = m.range(at: 0)
        if whole.location > last {
            out.append(InlineSpan(kind: .text, text: ns.substring(with: NSRange(location: last, length: whole.location - last))))
        }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        if let label = group(1) {
            let href = group(2) ?? ""
            if href.hasPrefix("/") {
                out.append(InlineSpan(kind: .link, text: label, href: href))
            } else if href.range(of: "^https?://", options: .regularExpression) != nil {
                out.append(InlineSpan(kind: .link, text: label, href: href))
            } else {
                out.append(InlineSpan(kind: .text, text: label))
            }
        } else if let bold = group(3) ?? group(4) {
            // `m[3] ?? m[4]` in JS is nullish, not falsy: an EMPTY capture would
            // still win the branch. The regex requires one or more characters,
            // so it cannot be empty — but the ordering is copied rather than
            // reasoned about, because the day the regex changes this comment is
            // the only warning.
            out.append(InlineSpan(kind: .bold, text: bold))
        } else if let italic = group(5), !italic.isEmpty {
            out.append(InlineSpan(kind: .italic, text: italic))
        } else if let code = group(6), !code.isEmpty {
            out.append(InlineSpan(kind: .code, text: code))
        }
        last = whole.location + whole.length
    }
    if last < ns.length {
        out.append(InlineSpan(kind: .text, text: ns.substring(from: last)))
    }
    return out
}

// MARK: - block structure

/// One bullet. `task` and `checked` only mean anything for a `- [ ]` item.
public struct AssistantListItem: Equatable, Sendable {
    public let text: String
    public let task: Bool
    public let checked: Bool
    public init(text: String, task: Bool = false, checked: Bool = false) {
        self.text = text
        self.task = task
        self.checked = checked
    }
}

/// The GitHub-flavoured subset the assistant is allowed to use.
public enum AssistantBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(lines: [String])
    case bullets(items: [AssistantListItem])
    case ordered(items: [String])
    case quote(lines: [String])
    case table(header: [String], rows: [[String]])
    case rule
    case code(text: String)
}

private func matches(_ pattern: String, _ s: String) -> Bool {
    s.range(of: pattern, options: .regularExpression) != nil
}

/// Replace the FIRST match only — JS's non-global `String#replace`.
private func replaceFirst(_ s: String, _ pattern: String, _ replacement: String) -> String {
    guard let r = s.range(of: pattern, options: .regularExpression) else { return s }
    return s.replacingCharacters(in: r, with: replacement)
}

private func captures(_ pattern: String, _ s: String) -> [String?]? {
    guard let rx = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = s as NSString
    guard let m = rx.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<m.numberOfRanges).map { i in
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }
}

private let rxFence = "^```"
private let rxRule = "^\\s*([-*_])\\1\\1[-*_ ]*$"
private let rxHeading = "^(#{1,6})\\s+(.*)$"
private let rxTableSep = "^\\s*\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{1,}:?\\s*)*\\|?\\s*$"
private let rxQuote = "^\\s*>\\s?"
private let rxBullet = "^\\s*[-*+]\\s+"
private let rxOrdered = "^\\s*\\d+[.)]\\s+"
private let rxTask = "^\\[( |x|X)\\]\\s+"
private let rxBlockStart = "^(#{1,6}\\s|>\\s?|\\s*[-*+]\\s+|\\s*\\d+[.)]\\s+|```)"

private func splitRow(_ l: String) -> [String] {
    var t = l.trimmingCharacters(in: .whitespacesAndNewlines)
    t = replaceFirst(t, "^\\|", "")
    t = replaceFirst(t, "\\|$", "")
    return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private func isBlockStart(_ l: String) -> Bool {
    matches(rxBlockStart, l) || matches(rxRule, l)
}

private func isBlank(_ l: String) -> Bool {
    l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/**
 Parse assistant prose into blocks.

 A straight port of web's `parseBlocks`, including the details that look like
 accidents and are not:

 * a table needs its separator row to be the NEXT line, so a lone pipe in a
   sentence stays a sentence.
 * an unterminated fence swallows the rest of the message, because the
   alternative — treating it as prose — would print raw backticks.
 * a paragraph stops at the first line that STARTS a block, which is why
   `isBlockStart` exists separately from the dispatch above it.
 */
public func parseAssistantBlocks(_ src: String) -> [AssistantBlock] {
    let lines = src.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    var blocks: [AssistantBlock] = []
    var i = 0

    while i < lines.count {
        let line = lines[i]
        if isBlank(line) { i += 1; continue }

        if matches(rxFence, line) {
            var buf: [String] = []
            i += 1
            while i < lines.count && !matches(rxFence, lines[i]) { buf.append(lines[i]); i += 1 }
            i += 1
            blocks.append(.code(text: buf.joined(separator: "\n")))
            continue
        }
        if matches(rxRule, line) { blocks.append(.rule); i += 1; continue }

        if let h = captures(rxHeading, line), let hashes = h[1], let text = h[2] {
            blocks.append(.heading(level: hashes.count, text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
            i += 1
            continue
        }

        if line.contains("|"), i + 1 < lines.count, matches(rxTableSep, lines[i + 1]) {
            let header = splitRow(line)
            i += 2
            var rows: [[String]] = []
            while i < lines.count && lines[i].contains("|") && !isBlank(lines[i]) {
                rows.append(splitRow(lines[i]))
                i += 1
            }
            blocks.append(.table(header: header, rows: rows))
            continue
        }
        if matches(rxQuote, line) {
            var buf: [String] = []
            while i < lines.count && matches(rxQuote, lines[i]) {
                buf.append(replaceFirst(lines[i], rxQuote, ""))
                i += 1
            }
            blocks.append(.quote(lines: buf))
            continue
        }
        if matches(rxBullet, line) {
            var items: [AssistantListItem] = []
            while i < lines.count && matches(rxBullet, lines[i]) {
                let it = replaceFirst(lines[i], rxBullet, "")
                if let task = captures(rxTask, it), let mark = task[1] {
                    items.append(
                        AssistantListItem(
                            text: replaceFirst(it, rxTask, ""),
                            task: true,
                            checked: mark.lowercased() == "x"
                        )
                    )
                } else {
                    items.append(AssistantListItem(text: it))
                }
                i += 1
            }
            blocks.append(.bullets(items: items))
            continue
        }
        if matches(rxOrdered, line) {
            var items: [String] = []
            while i < lines.count && matches(rxOrdered, lines[i]) {
                items.append(replaceFirst(lines[i], rxOrdered, ""))
                i += 1
            }
            blocks.append(.ordered(items: items))
            continue
        }

        var buf: [String] = []
        while i < lines.count && !isBlank(lines[i]) && !isBlockStart(lines[i]) { buf.append(lines[i]); i += 1 }
        blocks.append(.paragraph(lines: buf))
    }
    return blocks
}

// MARK: - the <ui> block

/**
 The card shapes the model is allowed to emit.

 "Allowed" is the operative word. Everything below is validated defensively and
 anything that does not fit is DROPPED, not rendered best-effort — a language
 model that has been talked into emitting a malformed card should cost the user
 a card, not a broken screen.
 */
public struct AssistantStatCard: Equatable, Sendable {
    public let label: String
    public let value: String
    public let sub: String?
    /// "accent" | "positive" | "negative" | "neutral". Anything else becomes "accent".
    public let tone: String
}

public struct AssistantProgressCard: Equatable, Sendable {
    public let label: String
    public let value: String?
    public let pct: Double
}

public struct AssistantBreakdownItem: Equatable, Sendable {
    public let label: String
    public let value: String?
    public let pct: Double?
}

public struct AssistantBreakdownCard: Equatable, Sendable {
    public let label: String
    public let items: [AssistantBreakdownItem]
}

public struct AssistantChartPoint: Equatable, Sendable {
    public let x: String
    public let y: Double
}

public struct AssistantChartCard: Equatable, Sendable {
    public let label: String
    /// "line" | "bar".
    public let chart: String
    public let points: [AssistantChartPoint]
    public let value: String?
}

public enum AssistantCard: Equatable, Sendable {
    case stat(AssistantStatCard)
    case progress(AssistantProgressCard)
    case breakdown(AssistantBreakdownCard)
    case chart(AssistantChartCard)
}

/// A suggestion: either sends a chat message or opens an app route, never both.
public struct AssistantAction: Equatable, Sendable {
    public let label: String
    public let send: String?
    public let href: String?
}

public struct AssistantUi: Equatable, Sendable {
    public let cards: [AssistantCard]
    public let actions: [AssistantAction]
}

let assistantMaxCards = 4
let assistantMaxActions = 4
let assistantMaxBreakdownItems = 6
let assistantMaxChartPoints = 12
let assistantMinChartPoints = 2

/// Web's UI_RE. Non-greedy, so a second block is left in the prose rather than swallowed.
let assistantUiPattern = "<ui>\\s*([\\s\\S]*?)\\s*</ui>"

/// `Math.min(100, Math.max(0, …))`, with a non-finite or non-numeric value as 0.
func clampPct(_ v: Double?) -> Double {
    guard let v, v.isFinite else { return 0 }
    return min(100, max(0, v))
}

/**
 A parsed JSON value, in the smallest shape this validator needs.

 **Why Domain declares its own instead of taking a library's.** The `<ui>` block
 is JSON, so something has to parse it — but Android's `:domain` has no JSON
 dependency in its main source set, and that symmetry is the thing that makes
 the two Domains provably the same code. Foundation's `JSONSerialization` hands
 back `Any`, which is exactly what an adapter would have to consume anyway.

 Each platform adapts its own parser into this and everything downstream is
 shared and vector-pinned.
 */
public indirect enum AssistantJson: Equatable, Sendable {
    case str(String)
    case num(Double)
    case bool(Bool)
    case arr([AssistantJson])
    case obj([String: AssistantJson])
    case null
}

private extension AssistantJson {
    /// `typeof v === "string" && v.length > 0` — an empty string is NOT a value here.
    var stringValue: String? {
        if case let .str(s) = self, !s.isEmpty { return s }
        return nil
    }
    var numberValue: Double? {
        if case let .num(n) = self { return n }
        return nil
    }
    var objectValue: [String: AssistantJson]? {
        if case let .obj(o) = self { return o }
        return nil
    }
    var arrayValue: [AssistantJson]? {
        if case let .arr(a) = self { return a }
        return nil
    }
}

private func toCard(_ raw: AssistantJson) -> AssistantCard? {
    guard let c = raw.objectValue else { return nil }
    switch c["kind"]?.stringValue {
    case "stat":
        guard let label = c["label"]?.stringValue, let value = c["value"]?.stringValue else { return nil }
        let rawTone = c["tone"]?.stringValue
        let tone = (rawTone == "positive" || rawTone == "negative" || rawTone == "neutral") ? rawTone! : "accent"
        return .stat(AssistantStatCard(label: label, value: value, sub: c["sub"]?.stringValue, tone: tone))

    case "progress":
        guard let label = c["label"]?.stringValue else { return nil }
        return .progress(AssistantProgressCard(
            label: label,
            value: c["value"]?.stringValue,
            pct: clampPct(c["pct"]?.numberValue)
        ))

    case "breakdown":
        guard let label = c["label"]?.stringValue, let rawItems = c["items"]?.arrayValue else { return nil }
        let items = rawItems
            .compactMap { $0.objectValue }
            .filter { $0["label"]?.stringValue != nil }
            .prefix(assistantMaxBreakdownItems)
            .map { o -> AssistantBreakdownItem in
                // An ABSENT pct means "no bar", a present-but-nonsense one means
                // "a bar at zero". Collapsing the two would draw a full-width
                // empty bar for every item.
                let pct: Double?
                if let raw = o["pct"], raw != .null { pct = clampPct(raw.numberValue) } else { pct = nil }
                return AssistantBreakdownItem(
                    label: o["label"]?.stringValue ?? "",
                    value: o["value"]?.stringValue,
                    pct: pct
                )
            }
        return items.isEmpty ? nil : .breakdown(AssistantBreakdownCard(label: label, items: Array(items)))

    case "chart":
        guard let label = c["label"]?.stringValue,
              let chart = c["chart"]?.stringValue,
              chart == "line" || chart == "bar",
              let rawPoints = c["points"]?.arrayValue else { return nil }
        let points = rawPoints
            .compactMap { $0.objectValue }
            .compactMap { o -> AssistantChartPoint? in
                guard let x = o["x"]?.stringValue, let y = o["y"]?.numberValue, y.isFinite else { return nil }
                return AssistantChartPoint(x: x, y: y)
            }
            .prefix(assistantMaxChartPoints)
        // Two points or it is not a chart, it is a number with axes.
        guard points.count >= assistantMinChartPoints else { return nil }
        return .chart(AssistantChartCard(
            label: label, chart: chart, points: Array(points), value: c["value"]?.stringValue
        ))

    default:
        return nil
    }
}

private func toAction(_ raw: AssistantJson) -> AssistantAction? {
    guard let a = raw.objectValue, let label = a["label"]?.stringValue else { return nil }
    if let send = a["send"]?.stringValue { return AssistantAction(label: label, send: send, href: nil) }
    // Internal routes only. An `href` the model invented pointing anywhere else
    // is dropped entirely rather than rendered as an external link.
    if let href = a["href"]?.stringValue, href.hasPrefix("/") {
        return AssistantAction(label: label, send: nil, href: href)
    }
    return nil
}

/// Validate a parsed `<ui>` payload. Nil when nothing in it survived.
public func assistantUiFrom(_ parsed: AssistantJson) -> AssistantUi? {
    guard let root = parsed.objectValue else { return nil }
    let cards = (root["cards"]?.arrayValue ?? []).compactMap(toCard).prefix(assistantMaxCards)
    let actions = (root["actions"]?.arrayValue ?? []).compactMap(toAction).prefix(assistantMaxActions)
    if cards.isEmpty && actions.isEmpty { return nil }
    return AssistantUi(cards: Array(cards), actions: Array(actions))
}

/// The prose and the raw `<ui>` payload, separated.
public struct AssistantSplit: Equatable, Sendable {
    public let text: String
    public let json: String?
}

/**
 Split a raw assistant message into prose and the `<ui>` payload.

 Separate from `assistantUiFrom` because this half needs no JSON parser at all,
 and keeping it that way is what lets the platform supply one.
 */
public func splitAssistantUi(_ raw: String) -> AssistantSplit {
    guard let groups = captures(assistantUiPattern, raw), let payload = groups[1] else {
        return AssistantSplit(text: raw.trimmingCharacters(in: .whitespacesAndNewlines), json: nil)
    }
    // `raw.replace(UI_RE, "")` in JS with a NON-global regex replaces only the
    // first match, and so does this. A model that emits two blocks keeps the
    // second one visible in the prose, which is the loud failure.
    let text = replaceFirst(raw, assistantUiPattern, "").trimmingCharacters(in: .whitespacesAndNewlines)
    return AssistantSplit(text: text, json: payload)
}
