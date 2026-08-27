import Foundation

/**
 Generic bank/card statement CSV parser.

 Ported from `apps/web/src/statements/parseCsv.ts`. Rather than hard-coding
 every Indian bank it auto-detects the header row and maps columns by keyword
 (date / narration / debit / credit / amount / balance), which covers the common
 shape used by HDFC, ICICI, SBI, Axis, Kotak and the rest. The mapping comes
 back with the result so the UI can show it and let the user correct a wrong
 guess.

 Mirrors Android's StatementCsv.kt.
 */

/**
 Minimal CSV → rows, with quotes and embedded commas/newlines.

 Deliberately NOT `Csv.swift`'s `parseCsv`. That one is the app's own
 export/import format: it detects only comma vs semicolon, reads the delimiter
 off the first line whether or not that line is blank, and has no reason to know
 about tabs. A bank's "CSV" is frequently tab-separated and frequently opens
 with several blank or title rows. Web keeps two parsers for exactly these
 reasons; so do the ports.
 */
func parseStatementRows(_ text: String) -> [[String]] {
    var body = text
    if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
    body = body.replacingOccurrences(of: "\r\n", with: "\n")

    let firstLine = body.split(separator: "\n", omittingEmptySubsequences: false)
        .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map(String.init) ?? ""
    let delim: Character = {
        if firstLine.contains("\t") { return "\t" }
        let semis = firstLine.filter { $0 == ";" }.count
        let commas = firstLine.filter { $0 == "," }.count
        return semis > commas ? ";" : ","
    }()

    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    // Iterating unicodeScalars, not Characters: CRLF is ONE grapheme cluster,
    // so a Character walk over a Windows export silently swallows the row
    // break. That exact bug cost a CI round-trip on the CSV importer.
    let scalars = Array(body.unicodeScalars)
    let delimScalar = delim.unicodeScalars.first!
    var i = 0
    while i < scalars.count {
        let ch = scalars[i]
        if inQuotes {
            if ch == "\"" {
                if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                    field.unicodeScalars.append("\"")
                    i += 1
                } else {
                    inQuotes = false
                }
            } else {
                field.unicodeScalars.append(ch)
            }
        } else if ch == "\"" {
            inQuotes = true
        } else if ch == delimScalar {
            row.append(field)
            field = ""
        } else if ch == "\n" {
            row.append(field)
            rows.append(row)
            row = []
            field = ""
        } else {
            field.unicodeScalars.append(ch)
        }
        i += 1
    }
    if !field.isEmpty || !row.isEmpty {
        row.append(field)
        rows.append(row)
    }
    return rows
}

private let rxDate = "(^|\\b)(date|txn date|value date|transaction date|posting date|tran date)\\b"
private let rxDesc = "(narration|description|particular|remarks|details|transaction remarks|merchant|transaction detail)"
private let rxDebit = "(debit|withdrawal|withdrawl|paid out|dr amount|amount\\s*\\(dr\\)|withdrawal amt)"
private let rxCredit = "(credit|deposit|paid in|cr amount|amount\\s*\\(cr\\)|deposit amt)"
private let rxAmount = "^(amount|txn amount|transaction amount|amount\\s*\\(inr\\))$"
private let rxBalance = "(balance|closing balance|running balance|available balance)"
private let rxDrCr = "^(dr/?cr|type|transaction type|debit/credit|indicator)$"

private func matches(_ pattern: String, _ s: String, caseInsensitive: Bool = true) -> Bool {
    let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
    return regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
}

/**
 Tolerant number: strips symbols and thousands separators, keeps sign and
 decimal point.

 **This reproduces a web bug on purpose.** `"1.234,56"` — one thousand two
 hundred and thirty-four — comes back as `1.23456`, because the thousands-comma
 strip only fires when three digits follow, the decimal comma therefore
 survives, and the final blanket comma-strip deletes it. It is the SAME defect
 as `data/adapters.ts`'s `num()` (PARITY_AUDIT web bug #4), in a second parser.

 It is reproduced rather than fixed for the reason recorded against #4: a silent
 divergence on an amount — the browser importing €1.23 and the phone €1,234.56
 from the same file — is worse than a shared bug, and the vector pinning it here
 fails loudly the day web is fixed.
 */
func statementNum(_ v: String?) -> Double {
    guard let v, !v.isEmpty else { return 0 }
    var cleaned = regexReplace(v, "[^0-9.,\\-]", "")
    cleaned = regexReplace(cleaned, ",(?=\\d{3}(\\D|$))", "")
    let norm: String
    if cleaned.contains(",") && !cleaned.contains(".") {
        // JS's String#replace with a STRING pattern replaces only the FIRST
        // occurrence. `replacingOccurrences` replaces them all, which would
        // turn "1,2,3" into a different number than the browser gets.
        if let range = cleaned.range(of: ",") {
            norm = cleaned.replacingCharacters(in: range, with: ".")
        } else {
            norm = cleaned
        }
    } else {
        norm = cleaned.replacingOccurrences(of: ",", with: "")
    }
    guard let n = jsParseFloat(norm), n.isFinite else { return 0 }
    return n
}

private let statementMonths: [String: Int] = [
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
]

private func isoDate(_ y: Int, _ mo: Int, _ d: Int) -> String {
    String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"), y, mo, d)
}

private func capture(_ pattern: String, _ s: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    return (0..<m.numberOfRanges).map { idx in
        guard let r = Range(m.range(at: idx), in: s) else { return "" }
        return String(s[r])
    }
}

/**
 Parse the many date formats a bank prints → ISO `YYYY-MM-DD`, or nil.

 **Day-first**, deliberately: `03/04/2026` is the 3rd of April on every Indian
 statement this parser exists for. There is no way to tell it from March 4th
 without knowing the issuer, and guessing month-first would silently move a
 third of every statement's rows.
 */
public func parseStatementDate(_ s: String?) -> String? {
    guard let s, !s.isEmpty else { return nil }
    let v = s.trimmingCharacters(in: .whitespacesAndNewlines)

    if let g = capture("^(\\d{4})-(\\d{2})-(\\d{2})", v) {
        return "\(g[1])-\(g[2])-\(g[3])"
    }
    if let g = capture("^(\\d{1,2})[/\\-.](\\d{1,2})[/\\-.](\\d{2,4})", v),
       let d = Int(g[1]), let mo = Int(g[2]) {
        let y = g[3].count == 2 ? 2000 + (Int(g[3]) ?? 0) : (Int(g[3]) ?? 0)
        if (1...12).contains(mo) && (1...31).contains(d) { return isoDate(y, mo, d) }
    }
    if let g = capture("^(\\d{1,2})[-\\s]([A-Za-z]{3})[A-Za-z]*[-\\s'](\\d{2,4})", v),
       let d = Int(g[1]) {
        let mo = statementMonths[g[2].lowercased()]
        let y = g[3].count == 2 ? 2000 + (Int(g[3]) ?? 0) : (Int(g[3]) ?? 0)
        if let mo, (1...31).contains(d) { return isoDate(y, mo, d) }
    }
    return nil
}

private struct Detected {
    let headerRow: Int
    let mapping: ColumnMapping
    let drcrCol: Int?
}

/**
 Find the header row — the one in the first 25 with the most keyword hits — and
 map its columns.

 The 25-row scan is not arbitrary: bank exports routinely open with a title, an
 address block, an account summary and a blank line or six before the table
 starts.
 */
private func detectMapping(_ rows: [[String]]) -> Detected {
    var best = -1
    var bestScore = 0
    var bestMap: ColumnMapping?
    var bestDrcr: Int?

    for (i, row) in rows.prefix(25).enumerated() {
        var date: String?, desc: String?, debit: String?, credit: String?, amount: String?, balance: String?
        var drcr: Int?
        var score = 0
        for (ci, cell) in row.enumerated() {
            let c = cell.trimmingCharacters(in: .whitespaces)
            let idx = String(ci)
            // else-if throughout, matching web: one cell claims at most one
            // role, and "Debit Amount" must not also register as an amount
            // column.
            if date == nil, matches(rxDate, c) { date = idx; score += 1 }
            else if desc == nil, matches(rxDesc, c) { desc = idx; score += 1 }
            else if debit == nil, matches(rxDebit, c) { debit = idx; score += 1 }
            else if credit == nil, matches(rxCredit, c) { credit = idx; score += 1 }
            else if balance == nil, matches(rxBalance, c) { balance = idx; score += 1 }
            else if amount == nil, matches(rxAmount, c) { amount = idx; score += 1 }
            else if drcr == nil, matches(rxDrCr, c) { drcr = ci }
        }
        if score > bestScore {
            bestScore = score
            best = i
            bestMap = ColumnMapping(date: date, description: desc, debit: debit, credit: credit, amount: amount, balance: balance)
            bestDrcr = drcr
        }
    }
    return Detected(headerRow: best, mapping: bestMap ?? ColumnMapping(), drcrCol: bestDrcr)
}

let statementWarnNoTable =
    "Couldn't find a transaction table — check the file has a header row with Date, Description and amount columns."
let statementWarnNoAmountColumn = "No amount column detected — pick one in the mapping."
let statementWarnNoRows = "No dated transactions found under the detected header."
let statementDefaultDescription = "Transaction"
let statementLabelGeneric = "Statement"
let statementLabelBank = "Bank statement"
let statementLabelCard = "Card statement"

public func parseStatementCsv(_ text: String, currency: String, kind: String) -> ParsedStatement {
    let rows = parseStatementRows(text).filter { r in
        r.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    var warnings: [String] = []
    let detected = detectMapping(rows)
    let mapping = detected.mapping
    guard detected.headerRow >= 0, let dateIdx = mapping.date, let di = Int(dateIdx) else {
        return ParsedStatement(
            kind: kind, label: statementLabelGeneric, currency: currency,
            period: StatementPeriod(), txns: [],
            warnings: [statementWarnNoTable], mapping: mapping
        )
    }
    let desci = mapping.description.flatMap { Int($0) } ?? -1
    let dbi = mapping.debit.flatMap { Int($0) } ?? -1
    let cri = mapping.credit.flatMap { Int($0) } ?? -1
    let ami = mapping.amount.flatMap { Int($0) } ?? -1
    let bali = mapping.balance.flatMap { Int($0) } ?? -1
    if dbi < 0 && cri < 0 && ami < 0 { warnings.append(statementWarnNoAmountColumn) }

    func cell(_ row: [String], _ i: Int) -> String? {
        i >= 0 && i < row.count ? row[i] : nil
    }

    var txns: [StatementTxn] = []
    for row in rows.dropFirst(detected.headerRow + 1) {
        // Skips preamble, totals and blank rows -- anything with no readable date.
        guard let date = parseStatementDate(cell(row, di)) else { continue }
        var amount = 0.0
        if dbi >= 0 || cri >= 0 {
            let debit = dbi >= 0 ? statementNum(cell(row, dbi)) : 0
            let credit = cri >= 0 ? statementNum(cell(row, cri)) : 0
            amount = credit - debit
        } else if ami >= 0 {
            var a = statementNum(cell(row, ami))
            if let drcrCol = detected.drcrCol {
                let t = (cell(row, drcrCol) ?? "").lowercased()
                if matches("dr|debit|w", t, caseInsensitive: false) { a = -abs(a) }
                else if matches("cr|credit|d(?!r)", t, caseInsensitive: false) { a = abs(a) }
            } else if matches("dr\\b", cell(row, ami) ?? "") {
                a = -abs(a)
            }
            amount = a
        }
        if amount == 0 { continue }
        let rawDesc = (desci >= 0 ? (cell(row, desci) ?? "") : "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let balanceCell = bali >= 0 ? cell(row, bali) : nil
        let balance: Int64? = {
            guard let balanceCell, !balanceCell.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return fromMajor(statementNum(balanceCell), currency).amount
        }()
        txns.append(StatementTxn(
            date: date,
            description: rawDesc.isEmpty ? statementDefaultDescription : rawDesc,
            // fromMajor, NOT `* 100`. Web hardcodes the divisor here and in the
            // balance above -- the third and fourth sites of the same constant
            // (PARITY_AUDIT web bug #8) -- which lands a ¥500 row as ¥5.
            // fromMajor uses the currency's own minor-unit count and is
            // byte-identical for INR, USD and EUR.
            amount: fromMajor(amount, currency).amount,
            balance: balance
        ))
    }

    let dates = txns.map(\.date).filter { !$0.isEmpty }.sorted()
    if txns.isEmpty { warnings.append(statementWarnNoRows) }
    return ParsedStatement(
        kind: kind,
        label: kind == "card" ? statementLabelCard : statementLabelBank,
        currency: currency,
        period: StatementPeriod(from: dates.first, to: dates.last),
        openingBalance: txns.first(where: { $0.balance != nil })?.balance,
        closingBalance: txns.last(where: { $0.balance != nil })?.balance,
        txns: txns,
        warnings: warnings,
        mapping: mapping
    )
}
