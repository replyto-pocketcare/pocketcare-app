import Foundation

/// How far back the Expense-trends tile looks. Web's `TrendPeriod`.
public enum TrendPeriod: String, CaseIterable, Sendable {
    case threeDays = "3d"
    case oneWeek = "1w"
    case oneMonth = "1m"
    case oneYear = "1y"

    public static func from(_ key: String?) -> TrendPeriod {
        guard let key, let value = TrendPeriod(rawValue: key) else { return .oneMonth }
        return value
    }
}

/**
 One bucket: the date it starts on, and what was spent in it.

 The START DATE, not a label. Web's `buildTrend` returns `"12 Aug"` built from a
 hardcoded English month array; formatting a date is the view's job on a platform
 that has a locale, and returning the label here would have shipped English into
 two otherwise localised apps.
 */
public struct TrendBucket: Sendable, Equatable {
    public let startIso: String
    public let totalMinor: Int64

    public init(startIso: String, totalMinor: Int64) {
        self.startIso = startIso
        self.totalMinor = totalMinor
    }
}

/**
 Buckets daily expense totals into period-appropriate buckets.

 A port of web's `buildTrend`, with `today` passed in rather than read from the
 clock — which is what makes it testable, and is why there are vectors for it.

 The bucket shapes are web's, exactly:
 - 3d / 1w: one bucket per day, oldest first.
 - 1m: FOUR buckets of seven days each, and web's windows **overlap by a day**
   (`start = today - (w*7 + 6)`, `end = today - w*7`, inclusive both ends). A day
   that is a boundary is counted in two buckets. That is web's arithmetic and it
   is preserved deliberately: correcting it here alone would make the same month
   read differently in the browser and on the phone.
 - 1y: twelve calendar months, oldest first.

 - Parameter dailyTotals: `YYYY-MM-DD` to minor units, as the query returns them.
 */
public func buildTrend(
    _ dailyTotals: [String: Int64],
    period: TrendPeriod,
    todayIso: String
) -> [TrendBucket] {
    // UTC, and its own Calendar rather than one of Domain's existing Ymd
    // helpers: `parseYmd` here returns a 0-based-month FinanceYmd and the only
    // `addDays` is private inside Recurring.swift. Borrowing either would have
    // meant widening something for one caller.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let today = trendDate(todayIso, calendar) else { return [] }

    func iso(_ date: Date) -> String { trendIso(date, calendar) }
    func shift(_ date: Date, days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    switch period {
    case .threeDays, .oneWeek:
        let n = period == .threeDays ? 3 : 7
        return (0..<n).reversed().map { i in
            let day = shift(today, days: -i)
            return TrendBucket(startIso: iso(day), totalMinor: dailyTotals[iso(day)] ?? 0)
        }
    case .oneMonth:
        return (0..<4).reversed().map { w in
            let start = shift(today, days: -(w * 7 + 6))
            let end = shift(today, days: -(w * 7))
            let startKey = iso(start)
            let endKey = iso(end)
            // String comparison, not Date: the keys are zero-padded ISO dates,
            // so lexical order IS chronological order and there is nothing to
            // parse per row.
            let sum = dailyTotals.reduce(Int64(0)) { acc, entry in
                (entry.key >= startKey && entry.key <= endKey) ? acc + entry.value : acc
            }
            return TrendBucket(startIso: startKey, totalMinor: sum)
        }
    case .oneYear:
        var firstOfThisMonth = calendar.dateComponents([.year, .month], from: today)
        firstOfThisMonth.day = 1
        let anchor = calendar.date(from: firstOfThisMonth) ?? today
        return (0..<12).reversed().map { m in
            let first = calendar.date(byAdding: .month, value: -m, to: anchor) ?? anchor
            let prefix = String(iso(first).prefix(7))
            let sum = dailyTotals.reduce(Int64(0)) { acc, entry in
                entry.key.hasPrefix(prefix) ? acc + entry.value : acc
            }
            return TrendBucket(startIso: iso(first), totalMinor: sum)
        }
    }
}

private func trendDate(_ iso: String, _ calendar: Calendar) -> Date? {
    let parts = String(iso.prefix(10)).split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
    var components = DateComponents()
    components.year = y; components.month = m; components.day = d
    return calendar.date(from: components)
}

private func trendIso(_ date: Date, _ calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// One month of the cashflow series.
public struct CashflowMonth: Sendable, Equatable {
    /// `YYYY-MM`.
    public let month: String
    public let incomeMinor: Int64
    public let expenseMinor: Int64

    public var netMinor: Int64 { incomeMinor - expenseMinor }

    public init(month: String, incomeMinor: Int64, expenseMinor: Int64) {
        self.month = month
        self.incomeMinor = incomeMinor
        self.expenseMinor = expenseMinor
    }
}

/**
 Folds `(yearMonth, type, total)` rows into one entry per month.

 Web's `useCashflow`, including the trailing-eight window. Rows arrive sorted by
 month from the query, and the fold preserves that order rather than re-sorting,
 so a month with only income and a month with only expense stay where the query
 put them.
 */
public func monthlyCashflow(_ rows: [(String, String, Int64)], months: Int = 8) -> [CashflowMonth] {
    var order: [String] = []
    var byMonth: [String: CashflowMonth] = [:]
    for (yearMonth, type, total) in rows {
        if byMonth[yearMonth] == nil {
            order.append(yearMonth)
            byMonth[yearMonth] = CashflowMonth(month: yearMonth, incomeMinor: 0, expenseMinor: 0)
        }
        let current = byMonth[yearMonth]!
        byMonth[yearMonth] = type == "income"
            ? CashflowMonth(month: yearMonth, incomeMinor: total, expenseMinor: current.expenseMinor)
            : CashflowMonth(month: yearMonth, incomeMinor: current.incomeMinor, expenseMinor: total)
    }
    let all = order.compactMap { byMonth[$0] }
    return all.count > months ? Array(all.suffix(months)) : all
}
