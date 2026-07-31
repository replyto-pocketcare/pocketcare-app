import Foundation

// Ported from packages/core/receipts/src/parse.ts (P1.5b). Mirrors
// apps/android/domain/.../receipts/ReceiptsParse.kt (P1.5a). Turning OCR
// output into a structured receipt. Every regex pattern here is transcribed
// verbatim from the TS source -- see ReceiptsMoneyText.swift's header
// comment for why that transcription is trustworthy across
// NSRegularExpression (ICU) and JS's engine.
//
// Guiding rule (mirrors the TS source): NEVER invent a number. Anything
// unsure of is left off and surfaced by reconcile() failing.

// ---------------------------------------------------------------------------
// Input shapes
// ---------------------------------------------------------------------------

public struct OcrToken: Sendable {
    public let text: String
    public let x0: Double
    public let x1: Double
    public let y0: Double
    public let y1: Double
    public let confidence: Int
    public init(text: String, x0: Double, x1: Double, y0: Double, y1: Double, confidence: Int) {
        self.text = text
        self.x0 = x0; self.x1 = x1; self.y0 = y0; self.y1 = y1
        self.confidence = confidence
    }
}

public struct TextLine: Sendable {
    public let text: String
    public let tokens: [OcrToken]
    /// Vertical centre, used only for ordering.
    public let y: Double
    /// Mean token confidence, 0-100.
    public let confidence: Int
    public init(text: String, tokens: [OcrToken], y: Double, confidence: Int) {
        self.text = text
        self.tokens = tokens
        self.y = y
        self.confidence = confidence
    }
}

/// Rebuild lines from loose tokens.
///
/// Tesseract's own line grouping gives up on the two- and three-column
/// layouts grocery bills use, so lines are regrouped by vertical overlap
/// using the median glyph height as tolerance -- adapts to image scale
/// instead of hard-coding pixels.
public func groupIntoLines(_ tokens: [OcrToken]) -> [TextLine] {
    if tokens.isEmpty { return [] }

    let heights = tokens.map { max(1.0, $0.y1 - $0.y0) }.sorted()
    let medianHeight = heights[heights.count / 2]
    let tolerance = medianHeight * 0.6

    let sorted = tokens.sorted { ($0.y0 + $0.y1) / 2 < ($1.y0 + $1.y1) / 2 }
    var rows: [[OcrToken]] = []
    var current: [OcrToken] = []
    var currentY = Double.nan

    for t in sorted {
        let y = (t.y0 + t.y1) / 2
        if current.isEmpty || abs(y - currentY) <= tolerance {
            current.append(t)
            // Running mean keeps a slightly skewed line from drifting away.
            currentY = currentY.isNaN ? y : (currentY * Double(current.count - 1) + y) / Double(current.count)
        } else {
            rows.append(current)
            current = [t]
            currentY = y
        }
    }
    if !current.isEmpty { rows.append(current) }

    return rows.map { row in
        let ordered = row.sorted { $0.x0 < $1.x0 }
        let joined = ordered.map { $0.text }.joined(separator: " ")
        let meanConfidence = ordered.reduce(0.0) { $0 + Double($1.confidence) } / Double(ordered.count)
        return TextLine(
            text: WHITESPACE_RE.replacingAllMatches(in: joined, with: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            tokens: ordered,
            y: ordered.reduce(0.0) { $0 + ($1.y0 + $1.y1) / 2 } / Double(ordered.count),
            confidence: Int(jsMathRound(meanConfidence))
        )
    }
}

/// Wrap plain text (PDF text layer, or a paste) as lines with no geometry.
public func linesFromText(_ text: String, _ confidence: Int = 100) -> [TextLine] {
    text.components(separatedBy: RETURN_NEWLINE_RE)
        .enumerated()
        .map { i, raw in TextLine(text: WHITESPACE_RE.replacingAllMatches(in: raw, with: " ").trimmingCharacters(in: .whitespacesAndNewlines), tokens: [], y: Double(i), confidence: confidence) }
        .filter { !$0.text.isEmpty }
}

// String's built-in components(separatedBy:) only takes a literal
// String/CharacterSet, not a regex -- \r?\n is split by hand via
// NSRegularExpression instead, since a bare "\n" split would leave a
// stray "\r" on Windows-style input (never actually present in these
// vectors, but matching the TS source's regex split exactly rather than a
// narrower manual split is cheap insurance).
private let RETURN_NEWLINE_RE = rx(#"\r?\n"#)
private extension String {
    func components(separatedBy pattern: NSRegularExpression) -> [String] {
        let ns = self as NSString
        var result: [String] = []
        var last = 0
        for m in pattern.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            result.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        result.append(ns.substring(from: last))
        return result
    }
}

// ---------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------

/// Lines that carry numbers but are NOT part of the bill's arithmetic.
/// Getting this list wrong is the most common way to double-count.
private let IGNORE_PATTERNS: [NSRegularExpression] = [
    rx(#"\b(cash|change|tendered|tender|card|visa|master(card)?|maestro|rupay|amex|upi|paytm|gpay|phonepe|wallet|pin|contactless)\b"#, .caseInsensitive),
    rx(#"\b(balance|due|payable\s*by|received|payment\s*mode|mode\s*of\s*payment)\b.*\b(card|cash|upi)\b"#, .caseInsensitive),
    rx(#"\b(gstin|gst\s*no|tin|pan|fssai|cin|vat\s*no|btw[\s-]*nr|tax\s*invoice|invoice\s*(no|#)|bill\s*(no|#)|order\s*(no|#)|receipt\s*(no|#)|token)\b"#, .caseInsensitive),
    rx(#"\b(thank\s*you|visit\s*again|welcome|customer\s*copy|merchant\s*copy|bedankt|dhanyavaad|have\s*a\s*(nice|great))\b"#, .caseInsensitive),
    rx(#"\b(table|server|waiter|cashier|counter|terminal|till|operator|staff)\b"#, .caseInsensitive),
    // NOTE: no trailing \b after "ph\s*[:.]" -- a word boundary cannot
    // follow a colon, which silently disables part of this alternation.
    // Transcribed verbatim from the TS source's own quirk, not "fixed".
    rx(#"\bphone\b|\btel\b|\bmob(ile)?\b|\bcontact\b|\bph\b\s*[:.]|www\.|https?:|@\w+\.(com|in|co|nl)"#, .caseInsensitive),
    rx(#"\b(total\s*(qty|items?|quantity|nos?\.?)|no\.?\s*of\s*items?|item\s*count|aantal)\b"#, .caseInsensitive),
    rx(#"\b(points?|loyalty|reward|membership|member\s*since|valid\s*(till|until))\b"#, .caseInsensitive),
    rx(#"\b(date|time|dated|datum|tijd|dinank)\b"#, .caseInsensitive),
    rx(#"\b(qty|quantity|aantal)\b\s*(x|rate|price|amount|amt)\b"#, .caseInsensitive), // column header row
    rx(#"^\s*[-=*_.~]{3,}\s*$"#), // separator rule
]

/// Header-zone-only ignores.
private let HEADER_NOISE_RE = rx(#"\b(road|rd|street|st|marg|nagar|sector|shop\s*no|shop|floor|plot|opp|near|layout|colony|cross|avenue|lane|block|straat|weg|pin\s*code)\b"#, .caseInsensitive)
private let HEADER_ZONE_LINES = 5

private let BARE_DATE_ISO_RE = rx(#"\b\d{1,4}[/\-.]\d{1,2}[/\-.]\d{2,4}\b"#)
private let BARE_DATE_TEXTUAL1_RE = rx(#"\b\d{1,2}[\s\-][A-Za-z]{3,9}[\s\-,]+\d{2,4}\b"#)
private let BARE_DATE_TEXTUAL2_RE = rx(#"\b[A-Za-z]{3,9}[\s\-]\d{1,2}[\s\-,]+\d{2,4}\b"#)
private let NON_LETTER_RE = rx(#"[^A-Za-z]"#)

/// A line that is essentially just a date, with no label and nothing else.
private func isBareDate(_ text: String) -> Bool {
    if findDate(text, "9999-12-31") == nil { return false }
    var rest = text
    rest = BARE_DATE_ISO_RE.replacingAllMatches(in: rest, with: " ")
    rest = BARE_DATE_TEXTUAL1_RE.replacingAllMatches(in: rest, with: " ")
    rest = BARE_DATE_TEXTUAL2_RE.replacingAllMatches(in: rest, with: " ")
    rest = NON_LETTER_RE.replacingAllMatches(in: rest, with: "")
    return rest.count < 3
}

/// Running subtotals: recorded for cross-checking, never stored as a line.
private let SUBTOTAL_RE = rx(#"\b(sub\s*-?\s*total|subtotal|subtotaal|tussentotaal|net\s*amount|taxable\s*(value|amount)|gross\s*amount|item\s*total)\b"#, .caseInsensitive)

/// The bill total. Checked AFTER subtotal so "sub total" can't win.
private let TOTAL_RE = rx(#"\b(grand\s*total|net\s*payable|amount\s*payable|total\s*payable|bill\s*(amount|total)|invoice\s*total|total\s*amount|te\s*betalen|totaal|total)\b"#, .caseInsensitive)

private let KIND_PATTERNS: [(NSRegularExpression, String)] = [
    // Service charge before tax: "service charge" and "service tax" are
    // different things and only the second is a tax.
    (rx(#"\b(service\s*(charge|chg|fee)|svc\s*(charge|chg)|delivery\s*(charge|fee)|packaging\s*(charge|fee)|packing\s*(charge|fee)|convenience\s*fee|handling\s*(charge|fee)|servicekosten|bedieningsgeld)\b"#, .caseInsensitive), "service_charge"),
    (rx(#"\b(tip|gratuity|fooi)\b"#, .caseInsensitive), "tip"),
    (rx(#"\b(c?gst|sgst|igst|ugst|vat|btw|service\s*tax|sales\s*tax|cess|tax|belasting)\b"#, .caseInsensitive), "tax"),
    (rx(#"\b(discount|disc\b|savings?|coupon|promo|offer|less\b|off\b|redeem(ed)?|korting)\b"#, .caseInsensitive), "discount"),
]

private let ROUND_OFF_RE = rx(#"\bround(ed)?\s*(off|ing)?\b"#, .caseInsensitive)
private let CONTAINS_TOTAL_WORD_RE = rx(#"total"#, .caseInsensitive)

private func classify(_ text: String, _ isHeaderZone: Bool) -> String {
    for re in IGNORE_PATTERNS where re.matchesAnywhere(text) { return "ignore" }
    if isBareDate(text) { return "ignore" }
    if isHeaderZone && HEADER_NOISE_RE.matchesAnywhere(text) { return "ignore" }
    if SUBTOTAL_RE.matchesAnywhere(text) { return "subtotal" }
    // Round-off is a real adjustment to the total, so it must stay in the
    // maths, but it is not a "total" line even though some printers label
    // it as one.
    if ROUND_OFF_RE.matchesAnywhere(text) && !CONTAINS_TOTAL_WORD_RE.matchesAnywhere(text) { return "item" }
    if TOTAL_RE.matchesAnywhere(text) { return "total" }
    for (re, kind) in KIND_PATTERNS where re.matchesAnywhere(text) { return kind }
    return "item"
}

// ---------------------------------------------------------------------------
// Quantity / unit price extraction
// ---------------------------------------------------------------------------

private struct QtyInfo {
    let quantity: Int64?
    let unit: String?
    let unitPrice: Int64?
    let description: String
}

private let QTY_PREFIX_RE = rx(#"^(\d+(?:[.,]\d+)?)\s*(?:x|\*|@)\s*(.+)$"#, .caseInsensitive)
private let QTY_SUFFIX_RE = rx(#"^(.+?)\s*(?:x|\*)\s*(\d+(?:[.,]\d+)?)$"#, .caseInsensitive)
private let TRAILING_DASH_RE = rx(#"[-–:|]+$"#)
private let MONEYISH_ONLY_RE = rx(#"^[\d.,\s]+$"#)
private let TRAIL_INT_RE = rx(#"^(.*[A-Za-z])\s+(\d{1,3})$"#)
private let LEAD_INT_RE = rx(#"^(\d{1,2})\s+([A-Za-z][^\d]{2,})$"#)

private func toQty(_ s: String) -> Int64 {
    let normalized = s.replacingOccurrences(of: ",", with: ".")
    return Int64(jsMathRound((Double(normalized) ?? 0) * Double(RECEIPT_QTY_SCALE)))
}

/// Work out quantity and unit price for an item line.
///
/// The reliable signal is ARITHMETIC, not layout: if a line ends with three
/// numbers and the first two multiply to the third, they are unambiguously
/// qty x rate = amount.
private func extractQty(_ description: String, _ amount: Int64, _ minorDigits: Int) -> QtyInfo {
    let baseDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
    var scale: Int64 = 1
    for _ in 0..<minorDigits { scale *= 10 }
    let nums = findNumbers(description, minorDigits)
    let descNs = description as NSString

    // --- qty x rate = amount, verified by multiplication -------------------
    if nums.count >= 2 {
        let rate = nums[nums.count - 1]
        let qty = nums[nums.count - 2]
        let qtyMajor = Double(qty.value) / Double(scale)
        if qtyMajor > 0 && qtyMajor <= 1000 {
            let product = Int64(jsMathRound(qtyMajor * Double(rate.value)))
            // One minor unit of slack: printers round the extension, not the rate.
            if abs(product - amount) <= 1 {
                let prefix = descNs.substring(to: qty.start)
                var desc = TRAILING_DASH_RE.replacingAllMatches(in: prefix.trimmingCharacters(in: .whitespacesAndNewlines), with: "")
                desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
                return QtyInfo(
                    quantity: Int64(jsMathRound(qtyMajor * Double(RECEIPT_QTY_SCALE))),
                    unit: findUnit(description),
                    unitPrice: rate.value,
                    description: desc.isEmpty ? baseDescription : desc
                )
            }
        }
    }

    // --- explicit "2 x Latte" / "Latte x 2" --------------------------------
    if let m = QTY_PREFIX_RE.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)) {
        let quantity = toQty(m.group(1, in: description))
        let rest = m.group(2, in: description).trimmingCharacters(in: .whitespacesAndNewlines)
        // "2 x 60.00" is qty x rate, not a description.
        if let asMoney = parseMoney(rest, minorDigits), MONEYISH_ONLY_RE.matchesAnywhere(rest) {
            return QtyInfo(quantity: quantity, unit: findUnit(description), unitPrice: asMoney, description: baseDescription)
        }
        return QtyInfo(
            quantity: quantity,
            unit: findUnit(description),
            unitPrice: quantity > 0 ? Int64(jsMathRound((Double(amount) * Double(RECEIPT_QTY_SCALE)) / Double(quantity))) : nil,
            description: rest
        )
    }
    if let m = QTY_SUFFIX_RE.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)) {
        let quantity = toQty(m.group(2, in: description))
        return QtyInfo(
            quantity: quantity,
            unit: findUnit(description),
            unitPrice: quantity > 0 ? Int64(jsMathRound((Double(amount) * Double(RECEIPT_QTY_SCALE)) / Double(quantity))) : nil,
            description: m.group(1, in: description).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // --- "1.5 kg Basmati Rice" ---------------------------------------------
    if let unit = findUnit(description) {
        // NSRegularExpression.escapedPattern is defensive-only here: `unit`
        // always comes from the fixed UNIT_WORDS list (plain alphabetic
        // text, no regex metacharacters) -- strictly safer than the TS
        // source's raw interpolation, never behaviorally different from it.
        let escapedUnit = NSRegularExpression.escapedPattern(for: unit)
        let unitRe = rx("(\\d+(?:[.,]\\d+)?)\\s*\(escapedUnit)\\b", .caseInsensitive)
        if let um = unitRe.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)) {
            let quantity = toQty(um.group(1, in: description))
            // Replace only the FIRST (and here, only known) occurrence at
            // its matched range -- mirrors JS's single-string .replace(),
            // not a global replace of every identical unit phrase elsewhere
            // in the description.
            let replaced = descNs.replacingCharacters(in: um.range, with: " ")
            let desc = WHITESPACE_RE.replacingAllMatches(in: replaced, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return QtyInfo(
                quantity: quantity,
                unit: unit,
                unitPrice: quantity > 0 ? Int64(jsMathRound((Double(amount) * Double(RECEIPT_QTY_SCALE)) / Double(quantity))) : nil,
                description: desc.isEmpty ? baseDescription : desc
            )
        }
    }

    // --- trailing bare integer, e.g. "Paneer Tikka  1" ----------------------
    if let trail = TRAIL_INT_RE.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)) {
        let quantity = toQty(trail.group(2, in: description))
        if quantity > 0 {
            return QtyInfo(
                quantity: quantity,
                unit: findUnit(description),
                unitPrice: Int64(jsMathRound((Double(amount) * Double(RECEIPT_QTY_SCALE)) / Double(quantity))),
                description: trail.group(1, in: description).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    // --- leading small integer, e.g. "2 Masala Dosa" -----------------------
    if let lead = LEAD_INT_RE.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)) {
        let quantity = toQty(lead.group(1, in: description))
        return QtyInfo(
            quantity: quantity,
            unit: nil,
            unitPrice: quantity > 0 ? Int64(jsMathRound((Double(amount) * Double(RECEIPT_QTY_SCALE)) / Double(quantity))) : nil,
            description: lead.group(2, in: description).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    return QtyInfo(quantity: nil, unit: nil, unitPrice: nil, description: baseDescription)
}

// ---------------------------------------------------------------------------
// Merchant
// ---------------------------------------------------------------------------

private let LETTER_RE = rx(#"[A-Za-z]"#)
private let MERCHANT_STRIP_RE = rx(#"[*_|]+"#)

private func findMerchant(_ lines: [TextLine]) -> String? {
    // Merchants print their name big, at the top. Look only at the first
    // few lines and prefer the most name-like: mostly letters, few digits.
    let head = lines.prefix(6)
    var best: (text: String, score: Double)?
    for line in head {
        let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count < 3 || t.count > 60 { continue }
        if IGNORE_PATTERNS.contains(where: { $0.matchesAnywhere(t) }) { continue }
        let letters = LETTER_RE.allMatches(t).count
        let digits = DIGIT_RE.allMatches(t).count
        if letters < 3 || digits > letters { continue }
        let score = Double(letters) / Double(t.count) - Double(digits) / Double(t.count)
        if best == nil || score > best!.score { best = (t, score) }
    }
    guard let b = best else { return nil }
    return MERCHANT_STRIP_RE.replacingAllMatches(in: b.text, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

public struct ParseOptions: Sendable {
    /// Fallback when the receipt doesn't print a currency.
    public let currency: String
    public let minorDigits: Int
    /// ISO date; dates after this are rejected as misreads. Defaults to today.
    public let today: String?
    /// Prefix for the generated stable line ids.
    public let idPrefix: String
    public let engine: String?

    public init(currency: String, minorDigits: Int = 2, today: String? = nil, idPrefix: String = "l", engine: String? = nil) {
        self.currency = currency
        self.minorDigits = minorDigits
        self.today = today
        self.idPrefix = idPrefix
        self.engine = engine
    }
}

private let DIGIT_2_TAIL_RE = rx(#"[.,]\d{1,2}$"#)

public func parseReceipt(_ lines: [TextLine], _ opts: ParseOptions) -> ReceiptDraft {
    let minorDigits = opts.minorDigits
    let prefix = opts.idPrefix
    let fullText = lines.map { $0.text }.joined(separator: "\n")

    var out: [ReceiptLine] = []
    var total: Int64?
    var subtotal: Int64?
    var seq = 0

    for i in lines.indices {
        let line = lines[i]
        let text = line.text
        if text.isEmpty { continue }

        let kind = classify(text, i < HEADER_ZONE_LINES)
        if kind == "ignore" { continue }

        let nums = findNumbers(text, minorDigits)
        if nums.isEmpty { continue }

        // The rightmost number on a line is the amount. Percentages, rates
        // and quantities all sit to its left on every receipt layout seen.
        let last = nums[nums.count - 1]
        let amount = last.value

        // Identifier guard: printed prices carry decimals. A long run of
        // digits with no decimal separator is a PIN code, phone number or
        // invoice reference. Dropping it makes reconciliation fail loudly,
        // which is the outcome wanted over a silent corruption.
        if kind == "item" && !DIGIT_2_TAIL_RE.matchesAnywhere(last.raw) && DIGIT_RE.allMatches(last.raw).count >= 5 {
            continue
        }
        if kind == "total" {
            // Prefer the LAST total-ish line: printers put "Total" then "Grand Total".
            total = amount
            continue
        }
        if kind == "subtotal" {
            subtotal = amount
            continue
        }

        let textNs = text as NSString
        let description = tidyDescription(textNs.substring(to: last.start))
        // A bare number with no label is noise (page numbers, stray marks).
        if description.isEmpty && kind == "item" { continue }

        if kind == "item" {
            let q = extractQty(description, amount, minorDigits)
            out.append(ReceiptLine(
                id: "\(prefix)\(seq)", kind: "item",
                description: q.description.isEmpty ? description : q.description,
                quantity: q.quantity, unit: q.unit, unitPrice: q.unitPrice,
                amount: amount, confidence: line.confidence
            ))
            seq += 1
        } else {
            // Charges: discounts are stored negative regardless of how they print.
            out.append(ReceiptLine(
                id: "\(prefix)\(seq)", kind: kind,
                description: description.isEmpty ? kind.replacingOccurrences(of: "_", with: " ") : description,
                quantity: nil, unit: nil, unitPrice: nil,
                amount: kind == "discount" ? -abs(amount) : amount,
                confidence: line.confidence
            ))
            seq += 1
        }
    }

    let computed = out.reduce(Int64(0)) { $0 + $1.amount }
    // If no total was printed but a subtotal was, and the lines agree with
    // the subtotal, the arithmetic can be trusted and the total derived.
    if total == nil, let sub = subtotal {
        let itemsOnly = out.filter { $0.kind == "item" }.reduce(Int64(0)) { $0 + $1.amount }
        if itemsOnly == sub { total = computed }
    }

    let meanConfidence = lines.isEmpty ? 0 : Int(jsMathRound(lines.reduce(0.0) { $0 + Double($1.confidence) } / Double(lines.count)))

    return ReceiptDraft(
        merchant: findMerchant(lines),
        occurredAt: findDate(fullText, opts.today),
        currency: detectCurrency(fullText) ?? opts.currency,
        lines: out,
        total: total,
        confidence: scoreConfidence(meanConfidence, out.count, total, computed),
        engine: opts.engine ?? "tesseract",
        rawText: fullText
    )
}

/// Convenience wrapper for a PDF text layer or pasted text.
public func parseReceiptText(_ text: String, _ opts: ParseOptions) -> ReceiptDraft {
    let effectiveOpts = ParseOptions(currency: opts.currency, minorDigits: opts.minorDigits, today: opts.today, idPrefix: opts.idPrefix, engine: opts.engine ?? "pdf_text")
    return parseReceipt(linesFromText(text), effectiveOpts)
}

/// Blend raw OCR confidence with structural evidence. OCR confidence alone
/// is a poor predictor; whether the numbers ADD UP is a much stronger
/// signal, so it dominates the score.
private func scoreConfidence(_ ocrConfidence: Int, _ lineCount: Int, _ total: Int64?, _ computed: Int64) -> Int {
    if lineCount == 0 { return 0 }
    var score = Double(ocrConfidence) * 0.5
    if let total {
        score += 20
        if total == computed {
            score += 30
        } else {
            // Near-misses are more recoverable than wild ones.
            let drift = Double(abs(total - computed)) / max(1.0, Double(abs(total)))
            score += drift < 0.05 ? 12.0 : (drift < 0.2 ? 5.0 : 0.0)
        }
    }
    if lineCount >= 3 { score += 5 }
    return Int(max(0.0, min(100.0, jsMathRound(score))))
}
