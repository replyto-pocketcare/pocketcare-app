import Foundation

// Ported from packages/core/receipts/src/money-text.ts (P1.5b). Mirrors
// apps/android/domain/.../receipts/ReceiptsMoneyText.kt (P1.5a). Parsing
// money and quantities out of OCR text -- deliberately separate from
// Money.swift, which deals in already-trusted values; this file deals in
// whatever a thermal printer and an OCR engine conspired to produce.
// Everything here returns nil rather than guessing.
//
// Every NSRegularExpression pattern is transcribed VERBATIM from the TS
// source (character for character), not re-derived. NSRegularExpression's
// \b, without the `.useUnicodeWordBoundaries` option (never set anywhere in
// this file), uses ICU's traditional simple word/non-word character
// classification -- the same ASCII-based definition JS's \b uses without
// its /u flag (also never used by the TS source). Verified via search
// (regular-expressions.info's own Unicode-boundaries article, and Apple's
// NSRegularExpression option docs), not assumed -- word-boundary/Unicode
// divergence is exactly the class of cross-engine risk this codebase
// treats with "never guess" caution (same standard as money rounding/dates).

/// Builds a static NSRegularExpression from a pattern known-good at compile
/// time. fatalError on failure is intentional: every pattern here is a
/// fixed string literal transcribed from a TS source that already compiles
/// as valid JS regex syntax, so a failure here would mean a transcription
/// bug, not a runtime data problem -- the same class of "should never
/// happen, fail loudly if it does" as parseIsoMillis's fatalError.
func rx(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else {
        fatalError("invalid regex pattern: \(pattern)")
    }
    return re
}

extension NSRegularExpression {
    func matchesAnywhere(_ s: String) -> Bool {
        firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
    func allMatches(_ s: String) -> [NSTextCheckingResult] {
        matches(in: s, range: NSRange(s.startIndex..., in: s))
    }
    /// Replaces every match (mirrors JS's /g flag, which every caller here uses).
    func replacingAllMatches(in s: String, with template: String) -> String {
        stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}

extension NSTextCheckingResult {
    /// Group `i`'s substring, or "" if that group didn't participate (mirrors
    /// how call sites here only ever read groups they know matched).
    func group(_ i: Int, in s: String) -> String {
        guard i < numberOfRanges, let r = Range(range(at: i), in: s) else { return "" }
        return String(s[r])
    }
}

/// Currency symbols/codes we strip before parsing, and map for detection.
private let CURRENCY_SYMBOLS: [(NSRegularExpression, String)] = [
    (rx(#"₹|\brs\.?\b|\binr\b"#, .caseInsensitive), "INR"),
    (rx(#"\$|\busd\b"#, .caseInsensitive), "USD"),
    (rx(#"€|\beur\b"#, .caseInsensitive), "EUR"),
    (rx(#"£|\bgbp\b"#, .caseInsensitive), "GBP"),
    (rx(#"¥|\bjpy\b"#, .caseInsensitive), "JPY"),
    (rx(#"\baed\b|\bdhs?\b"#, .caseInsensitive), "AED"),
]

/// First currency mentioned anywhere in the text, or nil.
public func detectCurrency(_ text: String) -> String? {
    for (re, code) in CURRENCY_SYMBOLS where re.matchesAnywhere(text) { return code }
    return nil
}

private let PAREN_NEGATIVE_RE = rx(#"^\(.*\)$"#)
private let TRAILING_MINUS_RE = rx(#"-\s*$"#)
private let NON_MONEY_CHARS_RE = rx(#"[^\d.,-]"#)
// Not private: ReceiptsParse.swift's parseReceipt digit-count guard and
// findMerchant reuse this exact pattern rather than declaring a second copy.
let DIGIT_RE = rx(#"\d"#)
private let SEPARATOR_CHARS_RE = rx(#"[.,]"#)

/// Parse a money-ish string to integer minor units.
///
/// Handles both separator conventions by looking at what comes AFTER the
/// last separator rather than assuming a locale: "1,234.56" and "1.234,56"
/// both give 123456, and Indian lakh grouping ("1,23,456") falls out for free.
public func parseMoney(_ raw: String, _ minorDigits: Int = 2) -> Int64? {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return nil }

    var negative = false
    if PAREN_NEGATIVE_RE.matchesAnywhere(s) { negative = true; s = String(s.dropFirst().dropLast()) } // (12.34)
    if TRAILING_MINUS_RE.matchesAnywhere(s) { negative = true } // 12.34-

    s = NON_MONEY_CHARS_RE.replacingAllMatches(in: s, with: "")
    if s.hasPrefix("-") { negative = true }
    s = s.replacingOccurrences(of: "-", with: "")
    if !DIGIT_RE.matchesAnywhere(s) { return nil }

    // More than 12 digits is a phone number, GSTIN or invoice reference.
    if DIGIT_RE.allMatches(s).count > 12 { return nil }

    let chars = Array(s)
    let lastDot = chars.lastIndex(of: ".")
    let lastComma = chars.lastIndex(of: ",")
    let lastSep: Int? = [lastDot, lastComma].compactMap { $0 }.max()
    var decIdx = -1
    if let sep = lastSep {
        let after = chars.count - sep - 1
        let bothPresent = lastDot != nil && lastComma != nil
        // Both separators present: the last one must be the decimal point.
        // Only one: it is a decimal point when it isn't grouping three digits.
        if bothPresent { decIdx = sep }
        else if after == minorDigits || after == 1 { decIdx = sep }
    }

    let intPartRaw = decIdx >= 0 ? String(chars[0..<decIdx]) : s
    let fracPartRaw = decIdx >= 0 ? String(chars[(decIdx + 1)...]) : ""
    let intPart = SEPARATOR_CHARS_RE.replacingAllMatches(in: intPartRaw, with: "")
    var fracPart = SEPARATOR_CHARS_RE.replacingAllMatches(in: fracPartRaw, with: "")
    if intPart.isEmpty && fracPart.isEmpty { return nil }
    fracPart = String((fracPart + String(repeating: "0", count: minorDigits)).prefix(minorDigits))

    // Integer arithmetic throughout (not pow-then-round-trip through
    // Double) -- exact, and this is a money value.
    var scale: Int64 = 1
    for _ in 0..<minorDigits { scale *= 10 }
    let value = (Int64(intPart.isEmpty ? "0" : intPart) ?? 0) * scale + (Int64(fracPart.isEmpty ? "0" : fracPart) ?? 0)
    return negative ? -value : value
}

/// A numeric run found in a line, with where it sat.
public struct NumberMatch: Sendable {
    public let raw: String
    public let start: Int
    public let end: Int
    public let value: Int64
}

private let NUMBER_RE = rx(#"-?\d[\d.,]*\d|-?\d"#)

/// Every parseable number in a line, left to right. `start`/`end` are UTF-16
/// code-unit offsets (matching JS String indices, which are also UTF-16
/// code units) -- consistent with every other index computed against OCR
/// text elsewhere in this domain.
public func findNumbers(_ line: String, _ minorDigits: Int = 2) -> [NumberMatch] {
    let ns = line as NSString
    var out: [NumberMatch] = []
    for m in NUMBER_RE.allMatches(line) {
        let raw = ns.substring(with: m.range)
        guard let value = parseMoney(raw, minorDigits) else { continue }
        out.append(NumberMatch(raw: raw, start: m.range.location, end: m.range.location + m.range.length, value: value))
    }
    return out
}

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

private let MONTHS: [String: Int] = [
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
]

private func isoDateString(_ y: Int, _ m: Int, _ d: Int) -> String {
    // POSIX locale explicitly, mirroring Finance.swift's isoOf() -- %d is
    // digit-only so this shouldn't matter in practice, but this is a
    // byte-for-byte-compared vector string.
    String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"), y, m, d)
}

private func isValidDate(_ y: Int, _ m: Int, _ d: Int) -> Bool {
    m >= 1 && m <= 12 && d >= 1 && d <= 31 && y >= 2000 && y <= 2100
}

private let ISO_DATE_RE = rx(#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#)
private let NUMERIC_DATE_RE = rx(#"\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b"#)
private let TEXTUAL_DAY_FIRST_RE = rx(#"\b(\d{1,2})[\s\-]([A-Za-z]{3,9})[\s\-,]+(\d{2,4})\b"#)
private let TEXTUAL_MONTH_FIRST_RE = rx(#"\b([A-Za-z]{3,9})[\s\-](\d{1,2})[\s\-,]+(\d{2,4})\b"#)

/// Find a date in receipt text. Day-first (India is the primary market), but
/// an unambiguous day > 12 flips the interpretation. Future dates are
/// rejected -- a receipt cannot be from tomorrow, so a "future" read means
/// we misparsed.
public func findDate(_ text: String, _ today: String? = nil) -> String? {
    // Every vector always passes `today` explicitly; this fallback mirrors
    // the TS source's own `new Date().toISOString().slice(0,10)` default,
    // which is always UTC -- explicit UTC calendar here for the same
    // reason, and to match the Kotlin port's explicit ZoneOffset.UTC.
    // Never exercised by a golden vector either way.
    let cutoff: String
    if let today {
        cutoff = today
    } else {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = utcCalendar.dateComponents([.year, .month, .day], from: Date())
        cutoff = isoDateString(comps.year!, comps.month!, comps.day!)
    }
    var candidates: [String] = []

    // ISO: 2026-07-25
    for m in ISO_DATE_RE.allMatches(text) {
        let y = Int(m.group(1, in: text)) ?? 0
        let mo = Int(m.group(2, in: text)) ?? 0
        let d = Int(m.group(3, in: text)) ?? 0
        if isValidDate(y, mo, d) { candidates.append(isoDateString(y, mo, d)) }
    }

    // Numeric: 25/07/2026, 25-07-26, 25.07.2026
    for m in NUMERIC_DATE_RE.allMatches(text) {
        var a = Int(m.group(1, in: text)) ?? 0
        var b = Int(m.group(2, in: text)) ?? 0
        let yStr = m.group(3, in: text)
        let y = yStr.count == 2 ? 2000 + (Int(yStr) ?? 0) : (Int(yStr) ?? 0)
        // Day-first unless the second field can only be a day.
        if b > 12 && a <= 12 { let t = a; a = b; b = t }
        if isValidDate(y, b, a) { candidates.append(isoDateString(y, b, a)) }
    }

    // Textual: 25 Jul 2026 / Jul 25, 2026
    for m in TEXTUAL_DAY_FIRST_RE.allMatches(text) {
        let d = Int(m.group(1, in: text)) ?? 0
        let mo = MONTHS[String(m.group(2, in: text).prefix(3)).lowercased()]
        let yStr = m.group(3, in: text)
        let y = yStr.count == 2 ? 2000 + (Int(yStr) ?? 0) : (Int(yStr) ?? 0)
        if let mo, isValidDate(y, mo, d) { candidates.append(isoDateString(y, mo, d)) }
    }
    for m in TEXTUAL_MONTH_FIRST_RE.allMatches(text) {
        let mo = MONTHS[String(m.group(1, in: text).prefix(3)).lowercased()]
        let d = Int(m.group(2, in: text)) ?? 0
        let yStr = m.group(3, in: text)
        let y = yStr.count == 2 ? 2000 + (Int(yStr) ?? 0) : (Int(yStr) ?? 0)
        if let mo, isValidDate(y, mo, d) { candidates.append(isoDateString(y, mo, d)) }
    }

    let usable = candidates.filter { $0 <= cutoff }
    if usable.isEmpty { return nil }
    // The latest plausible date: receipts print the transaction date
    // alongside older things like "member since" or a validity date.
    return usable.sorted().last
}

// ---------------------------------------------------------------------------
// Quantities
// ---------------------------------------------------------------------------

public let UNIT_WORDS =
    "kg|kgs|g|gm|gms|gram|grams|l|ltr|ltrs|litre|litres|ml|pcs|pc|piece|pieces|nos|no|unit|units|dozen|dz|pkt|pack|packs|box|btl|bottle|bottles"

// A unit only counts when it directly follows a number. Without that
// anchor, the single-letter units match inside ordinary words -- "Parle-G"
// reads as grams, "Model L" as litres.
private let UNIT_RE = rx(#"\d\s*(\#(UNIT_WORDS))\b"#, .caseInsensitive)

/// Canonical-ish unit label, or nil. Keeps whatever the receipt printed.
public func findUnit(_ text: String) -> String? {
    guard let m = UNIT_RE.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return m.group(1, in: text).lowercased()
}

private let CURRENCY_STRIP_RE = rx(#"[₹$€£¥]|\b(rs|inr|usd|eur|gbp)\b\.?"#, .caseInsensitive)
private let TRAILING_PUNCT_RE = rx(#"[\s\-–:|@.,*]+$"#)
private let LEADING_PUNCT_RE = rx(#"^[\s\-–:|@.,*]+"#)
// Not private: ReceiptsParse.swift's groupIntoLines/linesFromText reuse
// this exact pattern rather than declaring a second copy.
let WHITESPACE_RE = rx(#"\s+"#)

/// Trailing currency symbols and separators left behind after slicing an amount off.
public func tidyDescription(_ text: String) -> String {
    var t = text
    t = CURRENCY_STRIP_RE.replacingAllMatches(in: t, with: " ")
    t = TRAILING_PUNCT_RE.replacingAllMatches(in: t, with: "")
    t = LEADING_PUNCT_RE.replacingAllMatches(in: t, with: "")
    t = WHITESPACE_RE.replacingAllMatches(in: t, with: " ")
    return t.trimmingCharacters(in: .whitespacesAndNewlines)
}
