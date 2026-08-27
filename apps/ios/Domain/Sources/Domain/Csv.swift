import Foundation

/// Minimal, dependency-free CSV (RFC-4180-ish): quotes, escaped quotes, CRLF.
/// Ported from apps/web/src/data/csv.ts, character for character.
///
/// No CSV library on either platform, deliberately. Web hand-wrote this because
/// a dependency was not worth it; adopting a different parser on each phone
/// would give three implementations that disagree about the interesting cases —
/// an escaped quote inside a quoted cell, a bare CR, a trailing newline — which
/// are exactly the cases a real bank export contains.
///
/// `downloadText` is NOT ported: saving a file is a platform concern, and there
/// is nothing shared about a browser anchor click, an Android SAF intent and a
/// `UIActivityViewController`.
///
/// Mirrors apps/android/domain/.../csv/Csv.kt.

/// Parse CSV text into rows of string cells. Auto-detects `,` vs `;`.
public func parseCsv(_ text: String, delimiter: String? = nil) -> [[String]] {
    let src = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text // strip BOM
    // `.unicodeScalars.first!` is already a `Unicode.Scalar` — wrapping it in
    // `Unicode.Scalar(...)` would pick the failable numeric initialiser and not
    // compile. Both callers pass "," or ";", so the force-unwrap cannot fire.
    let delim = (delimiter ?? detectDelimiter(src)).unicodeScalars.first!
    var rows: [[String]] = []
    var row: [String] = []
    var cell = ""
    var inQuotes = false

    // UNICODE SCALARS, not Characters. Swift's `Character` is a grapheme
    // cluster, and CRLF is ONE grapheme — so iterating `Array(src)` never sees
    // a `\n` in a Windows file at all, and every row runs into the next.
    // CI run 33037489343 is where that landed, against a vector generated from
    // web's own parser.
    let chars = Array(src.unicodeScalars)
    var i = 0
    while i < chars.count {
        let ch = chars[i]
        if inQuotes {
            if ch == "\"" {
                if i + 1 < chars.count && chars[i + 1] == "\"" {
                    cell.append("\"")
                    i += 1
                } else {
                    inQuotes = false
                }
            } else {
                cell.unicodeScalars.append(ch)
            }
        } else if ch == "\"" {
            inQuotes = true
        } else if ch == delim {
            row.append(cell)
            cell = ""
        } else if ch == "\n" {
            row.append(cell)
            rows.append(row)
            row = []
            cell = ""
        } else if ch == "\r" {
            // A bare CR is dropped; the LF branch above ends the row. Web's
            // comment says "handled by the \n branch", which is only true for
            // CRLF — a lone CR line ending produces one very long row on all
            // three platforms. Preserved, because a file that old would import
            // identically wrong everywhere rather than differently.
        } else {
            cell.unicodeScalars.append(ch)
        }
        i += 1
    }
    if !cell.isEmpty || !row.isEmpty {
        row.append(cell)
        rows.append(row)
    }
    return rows.filter { r in r.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}

private func detectDelimiter(_ text: String) -> String {
    let firstLine = text.prefix { $0 != "\n" }
    let commas = firstLine.filter { $0 == "," }.count
    let semis = firstLine.filter { $0 == ";" }.count
    return semis > commas ? ";" : ","
}

/// Parse into header-keyed records (headers lowercased + trimmed).
///
/// `.whitespacesAndNewlines`, not `.whitespaces`: Kotlin's `String.trim()`
/// strips `\n` and `\r` too, and a quoted CSV cell can legally contain a
/// newline — so the narrower set would make the two platforms disagree about a
/// real file rather than a contrived one.
///
/// The key ORDER is the file's column order — a plain dictionary would lose it,
/// and a vector compares serialised JSON.
public struct CsvRecord: Sendable {
    public let keys: [String]
    private let values: [String: String]

    public init(keys: [String], values: [String: String]) {
        self.keys = keys
        self.values = values
    }

    public subscript(key: String) -> String? { values[key] }
}

public func parseRecords(_ text: String, delimiter: String? = nil) -> [CsvRecord] {
    let rows = parseCsv(text, delimiter: delimiter)
    guard let headerRow = rows.first else { return [] }
    let headers = headerRow.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    return rows.dropFirst().map { r in
        var values: [String: String] = [:]
        for (index, h) in headers.enumerated() {
            values[h] = (index < r.count ? r[index] : "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return CsvRecord(keys: headers, values: values)
    }
}

/// Serialize rows (first row = header) to CSV text.
public func toCsv(_ rows: [[String?]]) -> String {
    rows.map { r in r.map(escapeCell).joined(separator: ",") }.joined(separator: "\r\n")
}

private func escapeCell(_ v: String?) -> String {
    let s = v ?? ""
    let needsQuotes = s.contains { $0 == "\"" || $0 == "," || $0 == "\r" || $0 == "\n" }
    return needsQuotes ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
}

/// A minor-unit amount as the plain major-unit number a CSV cell holds:
/// `49900` INR → `"499.00"`, `500` JPY → `"500"`.
///
/// Web writes `(amount / 100).toFixed(2)` and its importer reads that straight
/// back, so a ¥500 charge exports as "5.00" and re-imports as ¥5 — a round trip
/// that loses money for every currency that is not two-decimal. Using the
/// currency's own minor-unit count in both directions makes the round trip
/// lossless, and for INR, USD and EUR produces byte-identical output to web's.
///
/// Deliberately NOT `formatMoney`: this is a machine-readable cell. A grouped,
/// symbol-prefixed, locale-formatted number is what the importer's `num()` has
/// to fight its way back out of.
public func majorText(_ minor: Int64, _ currency: String) -> String {
    let decimals = minorUnits(currency)
    let major = toMajor(money(minor, currency))
    return String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), major)
}
