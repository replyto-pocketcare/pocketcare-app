import Foundation

/// Normalises whatever a CSV put in the date column into an ISO-8601 instant.
/// Ported from `toIso` in apps/web/src/data/importCsv.ts.
///
/// **Two deliberate divergences, both because web's version is device-dependent
/// or unportable:**
///
/// 1. **Everything is read as UTC.** Web builds `new Date(yr, mm-1, dd, hh, mi)`
///    — LOCAL time — and then calls `.toISOString()`. The same CSV therefore
///    imports different `occurred_at` values in Mumbai and in London, and a
///    DD/MM/YYYY row dated the 1st lands on the previous day for anyone east of
///    UTC. A date column with no timezone in it is a civil date; reading it as
///    UTC is the only answer that gives every device the same ledger.
/// 2. **A closed set of formats.** Web's `new Date(s)` accepts anything the
///    JavaScript engine will parse, including "Aug 1, 2026" and RFC-2822. There
///    is no equivalent on either phone and no specification to port. ISO-8601
///    and the day-first numeric forms are what real exports contain; anything
///    else falls back to `nowIso`, exactly as an unparseable string does on web.
///
/// `nowIso` is a parameter, not a clock read — nothing in Domain reads a clock.
///
/// Mirrors apps/android/domain/.../csv/ImportDate.kt.
private let isoPattern = "^(\\d{4})-(\\d{1,2})-(\\d{1,2})(?:[ T](\\d{1,2}):(\\d{2})(?::(\\d{2}))?)?"

/// Day first: `31/12/2026`, `31-12-26`, `31.12.2026`, optionally `HH:mm`.
private let dayFirstPattern = "^(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{2,4})(?:[ T](\\d{1,2}):(\\d{2}))?"

public func importDate(_ raw: String, nowIso: String) -> String {
    if raw.isEmpty { return nowIso }

    if let g = captures(isoPattern, raw) {
        let year = Int(g[1]) ?? 0
        let month = Int(g[2]) ?? 0
        let day = Int(g[3]) ?? 0
        let hour = Int(g[4]) ?? 0
        let minute = Int(g[5]) ?? 0
        let second = Int(g[6]) ?? 0
        return isoInstant(year, month, day, hour, minute, second) ?? nowIso
    }

    if let g = captures(dayFirstPattern, raw) {
        let day = Int(g[1]) ?? 0
        let month = Int(g[2]) ?? 0
        // Web's rule, kept: a two-digit year is 20xx. It is wrong for anything
        // before 2000, and no personal-finance export contains one.
        let year = g[3].count == 2 ? 2000 + (Int(g[3]) ?? 0) : (Int(g[3]) ?? 0)
        let hour = Int(g[4]) ?? 0
        let minute = Int(g[5]) ?? 0
        return isoInstant(year, month, day, hour, minute, 0) ?? nowIso
    }

    return nowIso
}

/// Capture groups as strings, absent groups as "".
private func captures(_ pattern: String, _ s: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    return (0..<match.numberOfRanges).map { i in
        guard let r = Range(match.range(at: i), in: s) else { return "" }
        return String(s[r])
    }
}

/// `nil` for a date that does not exist, e.g. 31 February.
private func isoInstant(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> String? {
    guard (1...12).contains(mo), d >= 1, h <= 23, mi <= 59, s <= 59 else { return nil }
    guard d <= daysInMonth(y, mo - 1) else { return nil }
    return String(
        format: "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
        locale: Locale(identifier: "en_US_POSIX"),
        y, mo, d, h, mi, s
    )
}

/// Best-effort account type from its name — users can change it afterwards.
/// Ported from `guessAccountType` in importCsv.ts, regex for regex.
public func guessAccountType(_ name: String) -> String {
    let n = name.lowercased()
    func has(_ pattern: String) -> Bool {
        n.range(of: pattern, options: .regularExpression) != nil
    }
    if has("stock|equit|\\bshares?\\b") { return "stocks" }
    if has("mutual|\\bmf\\b|\\bsip\\b") { return "mutual_funds" }
    if has("credit|\\bcard\\b") { return "credit_card" }
    if has("cash|wallet") { return "cash" }
    if has("current|checking") { return "current" }
    return "savings"
}
