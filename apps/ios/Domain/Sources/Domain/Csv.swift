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
    let delim = Character(delimiter ?? detectDelimiter(src))
    var rows: [[String]] = []
    var row: [String] = []
    var cell = ""
    var inQuotes = false

    let chars = Array(src)
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
                cell.append(ch)
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
            cell.append(ch)
        }
        i += 1
    }
    if !cell.isEmpty || !row.isEmpty {
        row.append(cell)
        rows.append(row)
    }
    return rows.filter { r in r.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
}

private func detectDelimiter(_ text: String) -> String {
    let firstLine = text.prefix { $0 != "\n" }
    let commas = firstLine.filter { $0 == "," }.count
    let semis = firstLine.filter { $0 == ";" }.count
    return semis > commas ? ";" : ","
}

/// Parse into header-keyed records (headers lowercased + trimmed).
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
    let headers = headerRow.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    return rows.dropFirst().map { r in
        var values: [String: String] = [:]
        for (index, h) in headers.enumerated() {
            values[h] = (index < r.count ? r[index] : "").trimmingCharacters(in: .whitespaces)
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

/// JavaScript's `Number.parseFloat`, which reads a LEADING numeric prefix and
/// ignores the rest. Swift's `Double(_:)` requires the whole string, so
/// `"1.2.3"` is 1.2 in the browser and nil here — and a real bank export does
/// contain cells like that.
func jsParseFloat(_ s: String) -> Double? {
    let pattern = "^[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          let range = Range(match.range, in: s) else { return nil }
    return Double(s[range])
}
