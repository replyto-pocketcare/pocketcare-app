import Foundation

/**
 PDF statement parsing — the pure half.

 Ported from `apps/web/src/statements/parsePdf.ts`. Web's module does two
 things: it drives pdf.js to get positioned text, and then it parses. Only the
 SECOND half is here, because the first has no shared shape — pdf.js in a
 browser, PDFBox on Android, PDFKit on iOS — and mixing them would put the
 platform-specific part somewhere it cannot be vector-tested.

 Two parsers, in order of preference:

 1. `parseStatementPdfRows` is COLUMN-AWARE. It keeps each text fragment's
    x-position and assigns every money cell to the nearest numeric column, so
    Withdrawal / Deposit / Balance keep their meaning — which is how Indian
    bank PDFs actually lay them out. Guessing the sign from a flattened line
    gets refunds and salary credits backwards.
 2. `parseStatementPdfText` is the line heuristic, for when no header is found.
    It says so in a warning, because it is genuinely less reliable and the user
    has a better option (the CSV export).

 Mirrors Android's StatementPdf.kt.
 */

/// One positioned text fragment.
public struct PdfCell: Equatable, Sendable {
    public let x: Double
    public let str: String
    public init(x: Double, str: String) {
        self.x = x
        self.str = str
    }
}

/// One visual line: cells ordered left → right.
public typealias PdfRow = [PdfCell]

/**
 One positioned glyph, as a platform's PDF library hands it over.

 `y` is TOP-DOWN (larger = further down the page). PDFBox's `getYDirAdj()`
 already is; PDFKit's page space is bottom-up, so its extractor flips it. Web
 doesn't need this type at all — pdf.js emits ready-made text runs — which is
 exactly why `groupPdfGlyphs` exists here instead of in each app.
 */
public struct PdfGlyph: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let text: String
    public init(x: Double, y: Double, width: Double, text: String) {
        self.x = x
        self.y = y
        self.width = width
        self.text = text
    }
}

/**
 Baselines within this many points are the same visual line.

 Web's own bucket, from `parsePdf.ts`: superscripts, a slightly-raised currency
 symbol and ordinary rounding all move a baseline by a point or so, and none of
 them start a new row.
 */
public let pdfRowBucketPt = 2.0

/**
 A horizontal gap wider than this fraction of a glyph starts a new cell.

 Erring towards MORE cells is deliberate. An over-split narration is rejoined
 with a space and reads the same; an under-split one glues a money cell to
 letters, `pdfIsMoney` then rejects it, and the whole transaction row is silently
 dropped.
 */
public let pdfCellGapRatio = 0.35

/// Floor for that gap test, so a zero-width glyph can't split on every step.
public let pdfCellGapMinPt = 0.5


/**
 Group positioned glyphs into rows of cells — the shared half of extraction.

 This is the piece web does not have: pdf.js hands back text RUNS already, while
 PDFBox and PDFKit hand back glyphs. Doing the grouping in each app would mean
 the two phones disagreed about where a cell ends, and therefore about a
 narration's spacing and occasionally about a whole row. So each platform's
 extractor contributes nothing but ordered, positioned glyphs and this decides
 the rest, identically, under vector test.
 */
public func groupPdfGlyphs(_ glyphs: [PdfGlyph]) -> [PdfRow] {
    // Insertion-ordered buckets: a plain Dictionary would hand the rows back in
    // a per-run random order, and the y sort below only breaks ties by luck.
    var order: [Double] = []
    var byRow: [Double: [PdfGlyph]] = [:]
    for g in glyphs where !g.text.isEmpty {
        let key = jsRound(g.y / pdfRowBucketPt) * pdfRowBucketPt
        if byRow[key] == nil {
            byRow[key] = []
            order.append(key)
        }
        byRow[key]?.append(g)
    }

    return stableSorted(order) { $0 < $1 } // top-down
        .map { key in rowFromGlyphs(stableSorted(byRow[key] ?? []) { $0.x < $1.x }) }
        .filter { !$0.isEmpty }
}

private func rowFromGlyphs(_ sorted: [PdfGlyph]) -> PdfRow {
    var cells: [PdfCell] = []
    var text = ""
    var cellX = 0.0
    var prevEnd = 0.0
    var prevWidth = 0.0

    func flush() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { cells.append(PdfCell(x: cellX, str: t)) }
        text = ""
    }

    for g in sorted {
        if text.isEmpty {
            cellX = g.x
        } else {
            let threshold = pdfCellGapRatio * max(g.width, prevWidth)
            if g.x - prevEnd > max(threshold, pdfCellGapMinPt) {
                flush()
                cellX = g.x
            }
        }
        text += g.text
        prevEnd = g.x + g.width
        prevWidth = g.width
    }
    flush()
    return cells
}

// MARK: - regex helpers

private func pdfRegex(_ pattern: String, _ caseInsensitive: Bool) -> NSRegularExpression? {
    try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
}

private func pdfMatches(_ pattern: String, _ s: String, caseInsensitive: Bool = true) -> Bool {
    guard let rx = pdfRegex(pattern, caseInsensitive) else { return false }
    return rx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
}

/// Groups of every match, missing groups as "". Mirrors `[...s.matchAll(rx)]`.
private func pdfFindAll(_ pattern: String, _ s: String, caseInsensitive: Bool = true) -> [[String]] {
    guard let rx = pdfRegex(pattern, caseInsensitive) else { return [] }
    return rx.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
        (0..<m.numberOfRanges).map { i in
            guard let r = Range(m.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
    }
}

private func pdfReplaceAll(_ s: String, _ pattern: String, _ replacement: String, caseInsensitive: Bool = true) -> String {
    guard let rx = pdfRegex(pattern, caseInsensitive) else { return s }
    return rx.stringByReplacingMatches(
        in: s, range: NSRange(s.startIndex..., in: s), withTemplate: replacement
    )
}

/// First match's groups plus everything after the whole match — JS's
/// `m` and `line.slice(m[0].length)` in one step.
private func pdfFirstMatch(_ pattern: String, _ s: String, caseInsensitive: Bool = false) -> (groups: [String], rest: String)? {
    guard let rx = pdfRegex(pattern, caseInsensitive),
          let m = rx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          let whole = Range(m.range(at: 0), in: s) else { return nil }
    let groups = (0..<m.numberOfRanges).map { i -> String in
        guard let r = Range(m.range(at: i), in: s) else { return "" }
        return String(s[r])
    }
    return (groups, String(s[whole.upperBound...]))
}

// MARK: - header detection

private let hdrDate = "\\bdate\\b"
private let hdrDesc = "narration|description|particular|remarks|details|transaction remarks"
private let hdrDebit = "debit|withdrawal|withdrawl"
private let hdrCredit = "credit|deposit"
private let hdrAmount = "^\\s*amount\\b"
private let hdrBalance = "balance"
private let hdrDrCr = "^(dr/?cr|type|indicator)$"

/// Roles in web's own declaration order — the first match wins, so it matters.
private let pdfRoles: [(role: String, pattern: String)] = [
    ("date", hdrDate),
    ("desc", hdrDesc),
    ("debit", hdrDebit),
    ("credit", hdrCredit),
    ("amount", hdrAmount),
    ("balance", hdrBalance),
    ("drcr", hdrDrCr),
]

/**
 A deliberately different number reader from `statementNum`.

 Web keeps two, and the difference is real: this one strips commas
 unconditionally (`[^0-9.\-]`), so it has none of the European-decimal
 behaviour the CSV one reproduces. A PDF's money cells are already
 `1,234.56`-shaped by the time the extractor hands them over.
 */
private func pdfNum(_ s: String) -> Double {
    let cleaned = pdfReplaceAll(s, "[^0-9.\\-]", "", caseInsensitive: false)
    // `Number.parseFloat`, not `Number`: a leading numeric prefix wins and the
    // rest is dropped, so "12.34.56" is 12.34 on every platform rather than 0
    // on one of them.
    guard let n = jsParseFloat(cleaned), n.isFinite else { return 0 }
    return n
}

/**
 A cell that looks like money: digits with exactly two decimals, and no word in
 it once Dr/Cr is discounted. The letter test is what keeps "Balance as on
 01.04.2026" out of the amount columns.
 */
private func pdfIsMoney(_ s: String) -> Bool {
    pdfMatches("\\d[\\d,]*\\.\\d{2}\\b", s, caseInsensitive: false)
        && !pdfMatches("[a-z]{3,}", pdfReplaceAll(s, "dr|cr", ""))
}

private struct PdfHeaderCol {
    let role: String
    let x: Double
}

/// Find the header row and each detected column's x-position.
private func detectPdfHeader(_ rows: [PdfRow]) -> (headerIdx: Int, cols: [PdfHeaderCol]) {
    var bestIdx = -1
    var bestCols: [PdfHeaderCol] = []
    for (i, row) in rows.prefix(40).enumerated() {
        var seen = Set<String>()
        var cols: [PdfHeaderCol] = []
        for cell in row {
            for (role, pattern) in pdfRoles {
                if !seen.contains(role) && pdfMatches(pattern, cell.str) {
                    seen.insert(role)
                    cols.append(PdfHeaderCol(role: role, x: cell.x))
                    break
                }
            }
        }
        if cols.count > bestCols.count {
            bestCols = cols
            bestIdx = i
        }
    }
    // stableSorted: Swift's sort is not guaranteed stable, JS's and Kotlin's
    // are, and two header cells can share an x.
    return (bestIdx, stableSorted(bestCols) { $0.x < $1.x })
}

/// Nearest column by x among a candidate set of roles.
private func nearestPdfRole(_ cols: [PdfHeaderCol], _ roles: Set<String>, _ x: Double) -> String? {
    var best: String?
    var bestD = Double.infinity
    for c in cols {
        guard roles.contains(c.role) else { continue }
        let d = abs(c.x - x)
        if d < bestD {
            bestD = d
            best = c.role
        }
    }
    return best
}

let statementWarnPdfColumns =
    "PDF parsed with column detection — review a few rows to be sure the debits/credits look right."
let statementWarnPdfLines =
    "Couldn't detect statement columns — parsed line-by-line (less reliable). Review amounts, or try the CSV/Excel export."
let statementWarnPdfNothing =
    "Couldn't read any transactions — this may be a scanned image (needs OCR) or an unusual layout. Try the CSV/Excel export instead."

/**
 Column-aware parse. Returns nil when no usable header was found, so the caller
 can fall back to `parseStatementPdfText`.
 */
public func parseStatementPdfRows(_ rows: [PdfRow], currency: String, kind: String) -> ParsedStatement? {
    let (headerIdx, cols) = detectPdfHeader(rows)
    let roles = Set(cols.map(\.role))
    let hasNumeric = roles.contains("debit") || roles.contains("credit") || roles.contains("amount")
    if headerIdx < 0 || cols.count < 2 || !hasNumeric { return nil }

    let numericRoles = Set(["debit", "credit", "amount", "balance"].filter { roles.contains($0) })
    guard let firstNumX = cols.filter({ numericRoles.contains($0.role) }).map(\.x).min() else { return nil }
    let drcrX = cols.first { $0.role == "drcr" }?.x

    var txns: [StatementTxn] = []
    for row in rows.dropFirst(headerIdx + 1) {
        // A transaction row has a date somewhere near the start.
        guard let dateIdx = row.firstIndex(where: { parseStatementDate($0.str) != nil }),
              let date = parseStatementDate(row[dateIdx].str) else { continue }

        var debit = 0.0
        var credit = 0.0
        var amount = 0.0
        var balance = 0.0
        var drcr = ""
        var descParts: [String] = []

        for (ci, cell) in row.enumerated() {
            // Index, not value: web compares object identity, so a second cell
            // holding the same text is still a candidate.
            if ci == dateIdx { continue }
            if pdfIsMoney(cell.str) {
                let v = pdfNum(cell.str)
                switch nearestPdfRole(cols, numericRoles, cell.x) {
                case "debit": debit = v
                case "credit": credit = v
                case "balance": balance = v
                case "amount": amount = v
                default: break
                }
                if pdfMatches("\\bcr\\b", cell.str) { drcr = "cr" }
                else if pdfMatches("\\bdr\\b", cell.str) { drcr = "dr" }
            } else if let drcrX, abs(cell.x - drcrX) < 12,
                      pdfMatches("^(dr|cr)$", cell.str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                drcr = cell.str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            } else if cell.x < firstNumX - 4 {
                // Left of the numeric columns = narration.
                descParts.append(cell.str)
            }
        }

        var signed = 0.0
        if roles.contains("debit") || roles.contains("credit") {
            signed = credit - debit
        } else if amount != 0 {
            // Neither marker: a bare amount column on a bank statement is a
            // debit far more often than not, and web assumes the same.
            signed = drcr == "cr" ? abs(amount) : (drcr == "dr" ? -abs(amount) : -amount)
        }
        if signed == 0 { continue }

        let desc = regexReplace(descParts.joined(separator: " "), "\\s+", " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        txns.append(
            StatementTxn(
                date: date,
                description: desc.isEmpty ? statementDefaultDescription : desc,
                // fromMajor, not `* 100` -- web bug #8's fifth site.
                amount: fromMajor(signed, currency).amount,
                balance: roles.contains("balance") && balance != 0 ? fromMajor(balance, currency).amount : nil
            )
        )
    }
    if txns.isEmpty { return nil }

    let dates = txns.map(\.date).sorted()
    return ParsedStatement(
        kind: kind,
        label: kind == "card" ? statementLabelCard : statementLabelBank,
        currency: currency,
        period: StatementPeriod(from: dates.first, to: dates.last),
        openingBalance: txns.first { $0.balance != nil }?.balance,
        closingBalance: txns.last { $0.balance != nil }?.balance,
        txns: txns,
        warnings: [statementWarnPdfColumns]
    )
}

private let pdfMoneyPattern = "(?:₹|inr|rs\\.?)?\\s?(-?\\d[\\d,]*\\.\\d{2})(?:\\s?(dr|cr))?"
private let pdfLeadingDatePattern =
    "^\\s*(\\d{1,2}[/\\-.]\\d{1,2}[/\\-.]\\d{2,4}|\\d{4}-\\d{2}-\\d{2}|\\d{1,2}[-\\s][A-Za-z]{3}[A-Za-z]*[-\\s']\\d{2,4})"
private let pdfCreditWords = "salary|refund|reversal|received|credit|cashback|interest|neft cr|imps cr"

/// Fallback: parse flattened text lines when column detection fails.
public func parseStatementPdfText(_ text: String, currency: String, kind: String) -> ParsedStatement {
    var txns: [StatementTxn] = []
    var warnings = [statementWarnPdfLines]

    for line in text.components(separatedBy: "\n") {
        guard let dm = pdfFirstMatch(pdfLeadingDatePattern, line),
              let date = parseStatementDate(dm.groups[1]) else { continue }
        let monies = pdfFindAll(pdfMoneyPattern, line)
        if monies.isEmpty { continue }

        let nums: [(val: Double, drcr: String)] = monies.map { g in
            (Double(g[1].replacingOccurrences(of: ",", with: "")) ?? 0, g[2].lowercased())
        }
        // Two or more numbers on the line means the LAST is the running balance
        // and the one before it is the amount. One number is just the amount.
        let balance: Double? = nums.count >= 2 ? nums[nums.count - 1].val : nil
        let amtTok = nums.count >= 2 ? nums[nums.count - 2] : nums[0]
        let rest = regexReplace(pdfReplaceAll(dm.rest, pdfMoneyPattern, ""), "\\s+", " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let credit = amtTok.drcr == "cr" || pdfMatches(pdfCreditWords, rest)
        let signed = credit ? abs(amtTok.val) : -abs(amtTok.val)

        txns.append(
            StatementTxn(
                date: date,
                description: rest.isEmpty ? statementDefaultDescription : rest,
                amount: fromMajor(signed, currency).amount,
                balance: balance.map { fromMajor($0, currency).amount }
            )
        )
    }

    if txns.isEmpty { warnings.append(statementWarnPdfNothing) }
    let dates = txns.map(\.date).sorted()
    return ParsedStatement(
        kind: kind,
        label: kind == "card" ? statementLabelCard : statementLabelBank,
        currency: currency,
        period: StatementPeriod(from: dates.first, to: dates.last),
        openingBalance: txns.first { $0.balance != nil }?.balance,
        closingBalance: txns.last { $0.balance != nil }?.balance,
        txns: txns,
        warnings: warnings
    )
}

/// Flatten positioned rows to text lines — the fallback's input, and useful for debugging.
public func pdfRowsToText(_ rows: [PdfRow]) -> String {
    rows
        .map { r in
            regexReplace(r.map(\.str).joined(separator: " "), "\\s+", " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
}

/**
 Parse extracted rows: column-aware first, line heuristic as fallback.

 Takes ROWS, not a file. Getting the rows is the platform's job — see each
 app's `PdfTextExtractor`.
 */
public func parsePdfStatement(_ rows: [PdfRow], currency: String, kind: String) -> ParsedStatement {
    if let cols = parseStatementPdfRows(rows, currency: currency, kind: kind), !cols.txns.isEmpty {
        return cols
    }
    return parseStatementPdfText(pdfRowsToText(rows), currency: currency, kind: kind)
}

/**
 The whole pipeline, and the only entry point an app needs: positioned glyphs
 in, a parsed statement out.

 Everything between here and the platform's PDF library is shared and vector-
 tested, so an extractor is done as soon as it can produce ordered `PdfGlyph`s.
 */
public func parsePdfStatementFromGlyphs(_ glyphs: [PdfGlyph], currency: String, kind: String) -> ParsedStatement {
    parsePdfStatement(groupPdfGlyphs(glyphs), currency: currency, kind: kind)
}
