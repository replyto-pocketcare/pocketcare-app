import Foundation

// Ported from packages/core/diagnostics/src/index.ts (P1.6b). Mirrors
// apps/android/domain/.../diagnostics/Diagnostics.kt (P1.6a). Support-log
// types and redaction. THE REDACTION IS THE POINT: this is a personal
// finance app, so a support log must never become a leak of someone's
// spending. Keeps what DIAGNOSES a problem (table names, operations, error
// codes, row ids, routes) and drops what merely describes a person's life
// (amounts, merchants, descriptions, emails, payment handles).
//
// This is the highest cross-engine-divergence-risk domain ported so far
// after receipts (P1.5): heavy \b-word-boundary regex, Unicode currency
// symbols (₹€£), and an order-sensitive multi-pass pipeline (secrets ->
// UUID-preservation -> code-protection -> amount-scrubbing) where each
// pass's output feeds the next. Every regex below is transcribed VERBATIM
// from the TS source, not re-derived, mirroring ReceiptsMoneyText.swift's
// established discipline for this same class of risk.

public let LOG_LEVEL_ERROR = "error"
public let LOG_LEVEL_WARN = "warn"
public let LOG_LEVEL_INFO = "info"

/// Reused from Reconcile.swift's RowValue in spirit, but a fresh type:
/// this domain's dynamic "detail" object is a distinct concept (redacted
/// support log extras, not a DB row), and keeping the two separate avoids
/// coupling an unrelated future change in either domain to the other.
/// `indirect` (on the whole enum, the simplest correct choice) since
/// `.arr`/`.obj` are self-referential.
public indirect enum DetailValue: Sendable {
    case null
    case str(String)
    case intNum(Int64)
    case doubleNum(Double)
    case bool(Bool)
    case arr([DetailValue])
    /// [DetailEntry], not a Dictionary: JSON.stringify (used by
    /// formatLog's detail rendering) is insertion-order-sensitive, unlike
    /// the vector comparator's object-equality checks elsewhere in this
    /// porting effort -- so unlike Reconcile.swift's RowValue.obj (a plain
    /// Dictionary is fine there), order must be preserved here. Swift has
    /// no ordered-dictionary in the standard library, hence the explicit
    /// entry array. No golden vector currently exercises a non-empty
    /// detail through formatLog, but this is kept correct anyway per this
    /// codebase's "unexercised branches stay reasonably faithful" standard.
    case obj([DetailEntry])
}

public struct DetailEntry: Sendable {
    public let key: String
    public let value: DetailValue
    public init(key: String, value: DetailValue) {
        self.key = key
        self.value = value
    }
}

/// Placeholder tokens -- deliberately obvious in a log so nothing looks real.
public enum Redacted {
    public static let amount = "[amount]"
    public static let email = "[email]"
    public static let vpa = "[upi-id]"
    public static let token = "[token]"
    public static let text = "[text]"
}

public struct LogEntry: Sendable {
    /// Epoch ms.
    public let at: Int64
    public let level: String // LOG_LEVEL_ERROR | LOG_LEVEL_WARN | LOG_LEVEL_INFO
    /// Where it came from: "sync", "console", "window", "app".
    public let scope: String
    public let message: String
    /// Route the user was on, for reproducing.
    public let route: String?
    /// Structured extras (already redacted) -- always `.obj` when present.
    public let detail: DetailValue?

    public init(at: Int64, level: String, scope: String, message: String, route: String? = nil, detail: DetailValue? = nil) {
        self.at = at
        self.level = level
        self.scope = scope
        self.message = message
        self.route = route
        self.detail = detail
    }
}

/// Keys whose VALUES are never diagnostic and often personal. Matched
/// case-insensitively, on substring, so `merchant_name` and `raw_text` are
/// both caught.
private let SENSITIVE_KEYS = [
    "amount", "total", "subtotal", "balance", "price", "share_amount", "paid_amount",
    "description", "note", "merchant", "title", "name", "label",
    "email", "vpa", "handle", "upi",
    "raw_text", "parsed_json", "token", "key", "secret", "password", "authorization",
]

private func isSensitiveKey(_ key: String) -> Bool {
    let k = key.lowercased()
    return SENSITIVE_KEYS.contains { k.contains($0) }
}

/// Keys holding free-form prose. Their values get the full number-scrubbing
/// treatment, because a message can carry an amount anywhere in it.
private let FREE_TEXT_KEYS = ["message", "msg", "error", "reason", "stack", "text", "body"]

private func isFreeTextKey(_ key: String) -> Bool {
    let k = key.lowercased()
    return FREE_TEXT_KEYS.contains { k == $0 || k.hasSuffix("_\($0)") }
}

/// Mirrors Kotlin's `Regex.replace(input) { transform }` / JS's
/// `String.replace(regex, fn)` -- replaces every match (global) with the
/// result of `transform`, which receives the match's captured groups
/// (index 0 = whole match, 1... = capture groups) as an array of optional
/// strings (nil when a group didn't participate). Builds on the existing
/// `allMatches` extension (ReceiptsMoneyText.swift, P1.5b) rather than
/// duplicating match-enumeration logic.
extension NSRegularExpression {
    func replacingMatches(in s: String, using transform: ([String?]) -> String) -> String {
        var result = ""
        var lastEnd = s.startIndex
        for match in allMatches(s) {
            guard let range = Range(match.range, in: s) else { continue }
            result += s[lastEnd..<range.lowerBound]
            var groups: [String?] = []
            for i in 0..<match.numberOfRanges {
                if let r = Range(match.range(at: i), in: s) {
                    groups.append(String(s[r]))
                } else {
                    groups.append(nil)
                }
            }
            result += transform(groups)
            lastEnd = range.upperBound
        }
        result += s[lastEnd...]
        return result
    }
}

/// Anything that looks like an id stays -- it's how we find the row.
private let UUID_RE = rx("\\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\b", [.caseInsensitive])
private let UUID_RESTORE_RE = rx(" UUID(\\d+) ")

/// Run `fn` with UUIDs stashed out of harm's way, then restore them.
private func preservingUuids(_ input: String, _ fn: (String) -> String) -> String {
    var uuids: [String] = []
    let masked = UUID_RE.replacingMatches(in: input) { groups in
        uuids.append(groups[0] ?? "")
        return " UUID\(uuids.count - 1) "
    }
    let transformed = fn(masked)
    return UUID_RESTORE_RE.replacingMatches(in: transformed) { groups in
        if let idxStr = groups[1], let idx = Int(idxStr), idx >= 0, idx < uuids.count {
            return uuids[idx]
        }
        return ""
    }
}

private let BEARER_RE = rx("\\bBearer\\s+[A-Za-z0-9._\\-]+", [.caseInsensitive])
private let EYJ_RE = rx("\\beyJ[A-Za-z0-9._\\-]{20,}")
private let SECRET_PREFIX_RE = rx("\\b(sk|pk|rzp|whsec)[-_][A-Za-z0-9_\\-]{8,}", [.caseInsensitive])
// Emails before VPAs -- an email is also `x@y` shaped.
private let EMAIL_RE = rx("\\b[\\w.+-]+@[\\w-]+\\.[\\w.-]{2,}\\b")
private let VPA_LOOSE_RE = rx("\\b[\\w.\\-]{2,}@[a-z]{2,}\\b", [.caseInsensitive])

/// Strip credentials and contact details only. NEVER touches numbers.
/// Used for values under keys we already know aren't money, where guessing
/// from shape would destroy the diagnosis.
public func redactSecrets(_ input: String) -> String {
    if input.isEmpty { return "" }
    return preservingUuids(input) { s in
        var out = s
        out = BEARER_RE.replacingAllMatches(in: out, with: "Bearer \(Redacted.token)")
        out = EYJ_RE.replacingAllMatches(in: out, with: Redacted.token)
        out = SECRET_PREFIX_RE.replacingAllMatches(in: out, with: Redacted.token)
        out = EMAIL_RE.replacingAllMatches(in: out, with: Redacted.email)
        out = VPA_LOOSE_RE.replacingAllMatches(in: out, with: Redacted.vpa)
        return out
    }
}

private let CODE_RE = rx(#"((?:"|')?\bcode(?:"|')?\s*[:=]\s*(?:"|')?)([A-Za-z0-9]{2,10})"#, [.caseInsensitive])
private let CODE_RESTORE_RE = rx(" CODE(\\d+) ")
private let SYMBOL_AMOUNT_RE = rx(#"(?:₹|Rs\.?|INR|\$|€|£)\s*-?[\d,]+(?:\.\d{1,2})?"#, [.caseInsensitive])
private let THOUSANDS_AMOUNT_RE = rx("\\b-?\\d{1,3}(?:,\\d{2,3})+(?:\\.\\d{1,2})?\\b")
private let DECIMAL_AMOUNT_RE = rx("\\b-?\\d+\\.\\d{1,2}\\b")
private let LONG_INT_AMOUNT_RE = rx("\\b\\d{4,}\\b")

/// Scrub a free-text string: secrets AND anything money-shaped. Used for
/// log MESSAGES, where there is no key to say what a number means, so we
/// assume the worst.
public func redactText(_ input: String) -> String {
    if input.isEmpty { return "" }
    return preservingUuids(redactSecrets(input)) { s in
        var out = s
        // Protect SQLSTATE / error codes before the money passes run -- a
        // serialised PostgREST error arrives here as free text where the
        // 5-digit code is shape-identical to an amount.
        var codes: [String] = []
        out = CODE_RE.replacingMatches(in: out) { groups in
            let lead = groups[1] ?? ""
            let code = groups[2] ?? ""
            codes.append(code)
            return "\(lead) CODE\(codes.count - 1) "
        }
        // Symbol-prefixed, or a bare number with a decimal or thousands group.
        out = SYMBOL_AMOUNT_RE.replacingAllMatches(in: out, with: Redacted.amount)
        out = THOUSANDS_AMOUNT_RE.replacingAllMatches(in: out, with: Redacted.amount)
        out = DECIMAL_AMOUNT_RE.replacingAllMatches(in: out, with: Redacted.amount)
        // Long bare integers are minor-unit amounts (1258784 = ₹12,587.84).
        out = LONG_INT_AMOUNT_RE.replacingAllMatches(in: out, with: Redacted.amount)
        return CODE_RESTORE_RE.replacingMatches(in: out) { groups in
            if let idxStr = groups[1], let idx = Int(idxStr), idx >= 0, idx < codes.count {
                return codes[idx]
            }
            return ""
        }
    }
}

/// Keep the SHAPE of a redacted value -- null vs missing vs present matters.
private func redactedPlaceholderFor(_ value: DetailValue) -> DetailValue {
    switch value {
    case .null: return value
    case .intNum, .doubleNum: return .str(Redacted.amount)
    default: return .str(Redacted.text)
    }
}

/// Scrub a structured object. Key-based rather than value-based wherever
/// possible: knowing that `share_amount` was present is diagnostic,
/// knowing it was ₹4,284.90 is not.
public func redactDetail(_ input: DetailValue, _ depth: Int = 0) -> DetailValue {
    if case .null = input { return input }
    if depth > 4 { return .str("[deep]") }

    switch input {
    case .null:
        return input // unreachable (handled above); kept for switch exhaustiveness
    case .str(let s):
        return .str(redactSecrets(s))
    case .intNum, .doubleNum, .bool:
        return input
    case .arr(let items):
        // Cap arrays: a 200-row upload batch is noise, its length is the signal.
        let capped = items.prefix(10).map { redactDetail($0, depth + 1) }
        if items.count > 10 {
            return .arr(Array(capped) + [.str("…+\(items.count - 10) more")])
        }
        return .arr(Array(capped))
    case .obj(let entries):
        var out: [DetailEntry] = []
        for e in entries {
            let newValue: DetailValue
            if isSensitiveKey(e.key) {
                newValue = redactedPlaceholderFor(e.value)
            } else if isFreeTextKey(e.key), case .str(let sv) = e.value {
                newValue = .str(redactText(sv))
            } else {
                newValue = redactDetail(e.value, depth + 1)
            }
            out.append(DetailEntry(key: e.key, value: newValue))
        }
        return .obj(out)
    }
}

/// Build a fully-scrubbed entry. The only supported way to create one.
public func makeEntry(level: String, scope: String, message: String, route: String? = nil, detail: DetailValue? = nil, at: Int64? = nil) -> LogEntry {
    LogEntry(
        at: at ?? Int64(Date().timeIntervalSince1970 * 1000),
        level: level,
        scope: scope,
        // Cap length: a stack trace or a giant JSON blob crowds out everything else.
        message: String(redactText(message).prefix(500)),
        route: (route?.isEmpty == false) ? route : nil,
        detail: detail.map { redactDetail($0) }
    )
}

/// Minimal JSON.stringify equivalent for a detail object -- NOT exercised
/// by any golden vector (both formatLog vectors carry no detail), but kept
/// insertion-order-faithful ([DetailEntry], not a Dictionary) since
/// formatLog's output is compared as an exact string, unlike the
/// object-keyed comparisons used everywhere else in this porting effort.
private func jsonStringify(_ v: DetailValue) -> String {
    switch v {
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .intNum(let n): return String(n)
    case .doubleNum(let n): return String(n)
    case .str(let s):
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    case .arr(let items):
        return "[" + items.map(jsonStringify).joined(separator: ",") + "]"
    case .obj(let entries):
        return "{" + entries.map { "\"\($0.key)\":\(jsonStringify($0.value))" }.joined(separator: ",") + "}"
    }
}

private func padEnd(_ s: String, _ length: Int) -> String {
    var out = s
    while out.count < length { out += " " }
    return out
}

private func hhmmssUtc(_ epochMs: Int64) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
    let comps = cal.dateComponents([.hour, .minute, .second], from: date)
    return String(format: "%02d:%02d:%02d", comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
}

/// Render the log as plain text for copy/share. Plain text on purpose: it
/// survives being pasted into WhatsApp, an email or a GitHub issue, which
/// is how it will actually reach us. `context` is an ordered array (not a
/// Dictionary) so multi-key head output stays insertion-order-faithful --
/// no golden vector currently exercises more than one context key, but
/// this avoids a real (if currently untested) divergence risk since
/// Swift's Dictionary has no ordering guarantee at all.
public func formatLog(_ entries: [LogEntry], _ context: [(key: String, value: String?)] = []) -> String {
    let head = context.map { "\($0.key): \($0.value ?? "—")" }.joined(separator: "\n")

    let body: String
    if entries.isEmpty {
        body = "(no events captured)"
    } else {
        body = entries.map { e -> String in
            let time = hhmmssUtc(e.at)
            var detailStr = ""
            if let d = e.detail, case .obj(let entryList) = d, !entryList.isEmpty {
                detailStr = " \(jsonStringify(d))"
            }
            let routeStr = (e.route?.isEmpty == false) ? " (\(e.route!))" : ""
            let levelPadded = padEnd(e.level.uppercased(), 5)
            return "\(time) \(levelPadded) [\(e.scope)]\(routeStr) \(e.message)\(detailStr)"
        }.joined(separator: "\n")
    }

    return "Sanvya diagnostics\n\(head)\n\n--- events (newest last, \(entries.count)) ---\n\(body)"
}
