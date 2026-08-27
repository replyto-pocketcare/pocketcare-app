import Foundation

/**
 Pure statement analytics — no I/O, no formatting.

 Ported from `apps/web/src/statements/analysis.ts`. Amounts are signed minor
 units (− debit / + credit) and everything here is deterministic, which is what
 makes it vector-pinnable rather than "looks about right on my statement".

 Mirrors Android's StatementAnalysis.kt.
 */

public struct StatementSummary: Equatable, Sendable {
    public let count: Int
    /// Total money in (minor, positive).
    public let credits: Int64
    /// Total money out (minor, positive).
    public let debits: Int64
    /// credits − debits.
    public let net: Int64
    public let from: String?
    public let to: String?
}

public func summarize(_ txns: [StatementTxn]) -> StatementSummary {
    var credits: Int64 = 0
    var debits: Int64 = 0
    var from: String?
    var to: String?
    for t in txns {
        if t.amount >= 0 { credits += t.amount } else { debits += -t.amount }
        if !t.date.isEmpty {
            if from == nil || t.date < from! { from = t.date }
            if to == nil || t.date > to! { to = t.date }
        }
    }
    return StatementSummary(count: txns.count, credits: credits, debits: debits, net: credits - debits, from: from, to: to)
}

public struct CategoryTotal: Equatable, Sendable {
    public let name: String
    public let total: Int64
    public let count: Int
}

/// Spend (debits) grouped by category label, largest first.
public func byCategory(_ txns: [StatementTxn]) -> [CategoryTotal] {
    var order: [String] = []
    var totals: [String: (total: Int64, count: Int)] = [:]
    for t in txns {
        if t.amount >= 0 { continue } // only spends
        let trimmed = t.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = trimmed.isEmpty ? uncategorisedLabel : trimmed
        if totals[key] == nil { order.append(key) }
        let e = totals[key] ?? (0, 0)
        totals[key] = (e.total + -t.amount, e.count + 1)
    }
    // Built through an explicit `order` array, not a dictionary's iteration:
    // Swift dictionaries have no defined order at all, and the tie-break
    // between two equal totals has to be first-seen on both platforms.
    let rows = order.map { CategoryTotal(name: $0, total: totals[$0]!.total, count: totals[$0]!.count) }
    return stableSorted(rows) { $0.total > $1.total }
}

public struct MonthTotal: Equatable, Sendable {
    public let ym: String
    public let debit: Int64
    public let credit: Int64
}

/// Debits and credits bucketed by calendar month (YYYY-MM), chronological.
public func byMonth(_ txns: [StatementTxn]) -> [MonthTotal] {
    var order: [String] = []
    var totals: [String: (debit: Int64, credit: Int64)] = [:]
    for t in txns {
        if t.date.isEmpty { continue }
        let ym = String(t.date.prefix(7))
        if totals[ym] == nil { order.append(ym) }
        var e = totals[ym] ?? (0, 0)
        if t.amount >= 0 { e.credit += t.amount } else { e.debit += -t.amount }
        totals[ym] = e
    }
    let rows = order.map { MonthTotal(ym: $0, debit: totals[$0]!.debit, credit: totals[$0]!.credit) }
    return stableSorted(rows) { $0.ym < $1.ym }
}

public struct DayTotal: Equatable, Sendable {
    public let date: String
    public let debit: Int64
}

/// Daily spend series over the statement window, chronological.
public func byDay(_ txns: [StatementTxn]) -> [DayTotal] {
    var order: [String] = []
    var totals: [String: Int64] = [:]
    for t in txns where t.amount < 0 && !t.date.isEmpty {
        if totals[t.date] == nil { order.append(t.date) }
        totals[t.date] = (totals[t.date] ?? 0) + -t.amount
    }
    let rows = order.map { DayTotal(date: $0, debit: totals[$0]!) }
    return stableSorted(rows) { $0.date < $1.date }
}

public struct StatementOutlier: Equatable, Sendable {
    public let txn: StatementTxn
    public let amount: Int64
    public let reason: String
}

/**
 Flag unusually large spends using the IQR fence (> Q3 + 1.5·IQR) over the debit
 magnitudes, falling back to "> 3× median" for very small samples.

 The fallback is not a shortcut: quartiles over three points are noise, and a
 three-line statement with one big spend still deserves the flag.
 */
public func outliers(_ txns: [StatementTxn]) -> [StatementOutlier] {
    let debits = txns.filter { $0.amount < 0 }
    let mags = debits.map { -$0.amount }.sorted()
    if mags.count < 4 {
        if mags.isEmpty { return [] }
        let median = mags[mags.count / 2]
        let thr = median * 3
        // Web's `-t.amount > 0` is redundant next to `amount < 0` above, but it
        // is kept so the two implementations read the same.
        return debits.filter { -$0.amount > thr && -$0.amount > 0 }
            .map { StatementOutlier(txn: $0, amount: -$0.amount, reason: outlierReasonSmallSample) }
    }
    func q(_ p: Double) -> Double {
        let idx = Double(mags.count - 1) * p
        let lo = Int(idx.rounded(.down))
        let hi = Int(idx.rounded(.up))
        return Double(mags[lo]) + Double(mags[hi] - mags[lo]) * (idx - Double(lo))
    }
    let q1 = q(0.25)
    let q3 = q(0.75)
    let fence = q3 + 1.5 * (q3 - q1)
    let flagged = debits.filter { Double(-$0.amount) > fence }
        .map { StatementOutlier(txn: $0, amount: -$0.amount, reason: outlierReasonIQR) }
    return stableSorted(flagged) { $0.amount > $1.amount }
}

/**
 Normalise a merchant/narration for grouping: drop refs, digits, banking noise.

 The ORDER of the replacements is load-bearing. Long digit runs go first,
 because a card tail glued to a merchant name ("SWIGGY1234") would otherwise
 survive the word-boundary pass and split one merchant into many.
 */
public func normalizeMerchant(_ desc: String) -> String {
    var s = desc.lowercased()
    s = regexReplace(s, "[0-9]{4,}", " ")
    s = regexReplace(s, "\\b(upi|imps|neft|rtgs|ach|nach|pos|atw|vps|mmt|inb|ref|txn|trf|payment|paytm|gpay|phonepe)\\b", " ")
    s = regexReplace(s, "[^a-z ]+", " ")
    s = regexReplace(s, "\\s+", " ")
    s = s.trimmingCharacters(in: .whitespaces)
    return s.split(separator: " ", omittingEmptySubsequences: false).prefix(3).joined(separator: " ")
}

public struct RecurringCandidate: Equatable, Sendable {
    /// Representative description — the most recent one.
    public let label: String
    /// Normalised merchant.
    public let key: String
    /// Typical debit magnitude (minor).
    public let amount: Int64
    public let count: Int
    /// "weekly" | "monthly" | "yearly" | "irregular".
    public let cadence: String
    public let sample: [StatementTxn]
}

/**
 Detect likely recurring debits: same merchant, similar amount (±12%), seen at
 least twice with a regular gap. Powers "add as a recurring payment".
 */
public func recurringCandidates(_ txns: [StatementTxn]) -> [RecurringCandidate] {
    var order: [String] = []
    var groups: [String: [StatementTxn]] = [:]
    for t in txns {
        if t.amount >= 0 { continue }
        let key = normalizeMerchant(t.description)
        if key.isEmpty { continue }
        if groups[key] == nil { order.append(key) }
        groups[key, default: []].append(t)
    }
    var out: [RecurringCandidate] = []
    for key in order {
        let list = groups[key] ?? []
        if list.count < 2 { continue }
        let sorted = stableSorted(list) { $0.date < $1.date }
        let mags = sorted.map { -$0.amount }
        let median = mags.sorted()[mags.count / 2]
        // Amounts must cluster: each within ±12% of the median.
        if !mags.allSatisfy({ Double(abs($0 - median)) <= Double(median) * 0.12 }) { continue }
        var gaps: [Double] = []
        for i in 1..<sorted.count {
            if let d0 = isoDaysOrNil(sorted[i - 1].date), let d1 = isoDaysOrNil(sorted[i].date) {
                gaps.append(Double(d1 - d0))
            }
        }
        let avgGap = gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
        let cadence: String
        switch avgGap {
        case 5...10: cadence = "weekly"
        case 25...35: cadence = "monthly"
        case 350...380: cadence = "yearly"
        default: cadence = "irregular"
        }
        out.append(RecurringCandidate(
            label: sorted[sorted.count - 1].description,
            key: key,
            amount: median,
            count: sorted.count,
            cadence: cadence,
            sample: sorted
        ))
    }
    // Prefer regular cadences, then more occurrences — two comparators in that
    // order, exactly as web's `||`-chained sort does.
    return stableSorted(out) { a, b in
        let ai = a.cadence == "irregular" ? 1 : 0
        let bi = b.cadence == "irregular" ? 1 : 0
        if ai != bi { return ai < bi }
        return a.count > b.count
    }
}

/**
 Days since the epoch for an ISO `YYYY-MM-DD`, or nil when it will not parse.

 Delegates to Finance.swift's `epochDay` (Hinnant's days_from_civil) rather than
 a `DateFormatter`, so the answer is identical to Kotlin's and neither can drift
 with a platform's calendar handling. Web uses `Date.parse(d + "T00:00:00")`,
 which is LOCAL time — but only ever as a difference between two such values, so
 the offset cancels and the gap in days is the same everywhere. The one case
 that would NOT cancel is a DST boundary between the two dates; web's own
 arithmetic has that rounding wobble and the cadence buckets are wide enough
 (5–10, 25–35, 350–380) that it cannot change an answer.
 */
func isoDaysOrNil(_ iso: String) -> Int? {
    guard iso.count >= 10 else { return nil }
    let chars = Array(iso)
    guard let y = Int(String(chars[0..<4])),
          let m = Int(String(chars[5..<7])),
          let d = Int(String(chars[8..<10])),
          (1...12).contains(m), (1...31).contains(d) else { return nil }
    // epochDay takes a ZERO-indexed month.
    return epochDay(y, m - 1, d)
}

/// `sorted(by:)` is NOT guaranteed stable in Swift; `Array.prototype.sort` is
/// stable in every engine web targets, and Kotlin's sorts are stable too. Where
/// a tie can occur — two categories with the same total, two outliers with the
/// same amount — an unstable sort would put the two phones in different orders
/// for the same statement. Decorating with the original index restores it.
func stableSorted<T>(_ items: [T], by areInIncreasingOrder: (T, T) -> Bool) -> [T] {
    items.enumerated()
        .sorted { a, b in
            if areInIncreasingOrder(a.element, b.element) { return true }
            if areInIncreasingOrder(b.element, a.element) { return false }
            return a.offset < b.offset
        }
        .map(\.element)
}

func regexReplace(_ s: String, _ pattern: String, _ replacement: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
    return regex.stringByReplacingMatches(
        in: s, range: NSRange(s.startIndex..., in: s), withTemplate: replacement
    )
}

let uncategorisedLabel = "Uncategorised"
let outlierReasonSmallSample = "Much larger than your typical spend (~3× the median)"
let outlierReasonIQR = "Unusually large — above the normal range for this statement"
