import Foundation

// Ported from packages/core/budget/src/index.ts (P1.3b). Mirrors
// apps/android/domain/.../budget/Budget.kt (P1.3a) field-for-field, but
// deliberately does NOT use Foundation's Calendar/Date for the date
// arithmetic itself. Search surfaced real reports of Calendar's
// `date(byAdding:)` silently reverting to the *device's local* time zone
// unless every Calendar/DateComponents value involved is airtight about
// an explicit UTC TimeZone -- the same class of "don't trust the
// platform's automatic behavior" risk as Money.swift's NumberFormatter
// decision. Ymd below is pure (year, month, day) integer arithmetic
// instead, mirroring the Kotlin port's use of java.time.LocalDate as a
// deterministic proleptic-Gregorian oracle, hand-rolled here since Swift
// has no equivalent timezone-free calendar-date type in its standard
// library. Sakamoto's day-of-week algorithm and the Gregorian leap-year
// rule below are both independently verified published algorithms, not
// derived from scratch -- see the git commit message for sources checked.

/// A UTC calendar day (proleptic Gregorian), month 1-based. Distinct from
/// Finance.swift's private, 0-based FinanceYmd -- the two files don't
/// share a date type since their needs differ (this one needs real +N-day
/// arithmetic and day-of-week; Finance.swift only ever builds/compares
/// YYYY-MM-DD strings).
public struct Ymd: Equatable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: Ymd, rhs: Ymd) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"), year, month, day)
    }
}

private func isLeapYearYmd(_ y: Int) -> Bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

/// Days in month `m` (1-based) of year `y`. Standard Gregorian rule -- the
/// same rule java.time (Kotlin port) and JS's Date.UTC both implement, so
/// there's no cross-platform divergence risk.
private func daysInMonthYmd(_ y: Int, _ m: Int) -> Int {
    switch m {
    case 1, 3, 5, 7, 8, 10, 12: return 31
    case 4, 6, 9, 11: return 30
    case 2: return isLeapYearYmd(y) ? 29 : 28
    default: return 30
    }
}

/// Day of week, 0=Sunday..6=Saturday -- matches JS's Date.getUTCDay()
/// convention exactly, so periodBounds needs no convention conversion
/// (unlike the Kotlin port, which has to convert from java.time's
/// ISO 1=Monday..7=Sunday). Sakamoto's algorithm, verified against
/// multiple independently published references before use.
private func dayOfWeek(_ ymd: Ymd) -> Int {
    let t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
    var y = ymd.year
    if ymd.month < 3 { y -= 1 }
    let raw = (y + y / 4 - y / 100 + y / 400 + t[ymd.month - 1] + ymd.day) % 7
    return raw < 0 ? raw + 7 : raw
}

/// Adds (or subtracts, for negative delta) whole days with month/year
/// carrying. Every caller here only ever passes a small delta (-6...7), so
/// a simple carry loop is both correct and fast -- no need for a general
/// epoch-day <-> calendar-date conversion algorithm, which would be a much
/// larger surface to get subtly wrong.
private func addDaysYmd(_ ymd: Ymd, _ delta: Int) -> Ymd {
    var y = ymd.year
    var m = ymd.month
    var d = ymd.day
    if delta > 0 {
        var remaining = delta
        while remaining > 0 {
            let daysLeftInMonth = daysInMonthYmd(y, m) - d
            if remaining <= daysLeftInMonth {
                d += remaining
                remaining = 0
            } else {
                remaining -= (daysLeftInMonth + 1)
                d = 1
                m += 1
                if m > 12 { m = 1; y += 1 }
            }
        }
    } else if delta < 0 {
        var remaining = -delta
        while remaining > 0 {
            if remaining < d {
                d -= remaining
                remaining = 0
            } else {
                remaining -= d
                m -= 1
                if m < 1 { m = 12; y -= 1 }
                d = daysInMonthYmd(y, m)
            }
        }
    }
    return Ymd(year: y, month: m, day: d)
}

/// Half-open date window [start, endExclusive).
public struct DateWindow: Equatable {
    public let start: Ymd
    public let endExclusive: Ymd
}

/// The budget period window that `date` falls into (UTC, Monday-based weeks).
public func periodBounds(_ period: String, _ date: Ymd) -> DateWindow {
    switch period {
    case "daily":
        return DateWindow(start: date, endExclusive: addDaysYmd(date, 1))
    case "weekly":
        let dow = dayOfWeek(date) // 0=Sunday..6=Saturday, matches JS directly
        let backToMonday = (dow + 6) % 7
        let start = addDaysYmd(date, -backToMonday)
        return DateWindow(start: start, endExclusive: addDaysYmd(start, 7))
    case "monthly":
        let start = Ymd(year: date.year, month: date.month, day: 1)
        let endMonth = date.month == 12 ? 1 : date.month + 1
        let endYear = date.month == 12 ? date.year + 1 : date.year
        return DateWindow(start: start, endExclusive: Ymd(year: endYear, month: endMonth, day: 1))
    case "yearly":
        return DateWindow(start: Ymd(year: date.year, month: 1, day: 1), endExclusive: Ymd(year: date.year + 1, month: 1, day: 1))
    default:
        fatalError("unknown period: \(period)")
    }
}

public struct BudgetProgress: Equatable {
    public let pct: Double
    public let remaining: Money
    public let atOrOverThreshold: Bool
    public let overLimit: Bool
}

/// Progress of `spent` against a budget `limit`, flagging threshold/limit
/// breaches. pct is Double.infinity when limit is 0 (mirrors JS Infinity,
/// serialized as JSON null by the vector adapter).
public func budgetProgress(_ limit: Money, _ spent: Money, _ thresholdPct: Double) throws -> BudgetProgress {
    guard limit.currency == spent.currency else {
        throw MoneyError(description: "budgetProgress: limit and spent must share a currency")
    }
    let pct = limit.amount == 0 ? Double.infinity : (Double(spent.amount) / Double(limit.amount)) * 100
    return BudgetProgress(
        pct: pct,
        remaining: try subtract(limit, spent),
        atOrOverThreshold: pct >= thresholdPct,
        overLimit: spent.amount > limit.amount
    )
}

/// True when spend crosses the threshold on THIS update (was below, now
/// at/above) -- the edge to fire a single notification on. Idempotent: no
/// repeat alerts while already over.
public func crossedThreshold(_ previousSpent: Money, _ newSpent: Money, _ limit: Money, _ thresholdPct: Double) -> Bool {
    let thresholdAmount = Double(limit.amount) * thresholdPct / 100
    return Double(previousSpent.amount) < thresholdAmount && Double(newSpent.amount) >= thresholdAmount
}

// ---------------- Credit-card billing cycle ----------------

private func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    let r = a % b
    return (r != 0 && (r < 0) != (b < 0)) ? q - 1 : q
}

private func floorMod(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return (r != 0 && (r < 0) != (b < 0)) ? r + b : r
}

private func clampDayYmd(_ year: Int, _ monthIndex: Int, _ day: Int) -> Ymd {
    // monthIndex is 0-based and may be out of [0,11] (mirrors the TS
    // source's Date.UTC month-overflow normalization).
    let totalMonths = year * 12 + monthIndex
    let ny = floorDiv(totalMonths, 12)
    let nm0 = floorMod(totalMonths, 12)
    let lastDay = daysInMonthYmd(ny, nm0 + 1)
    return Ymd(year: ny, month: nm0 + 1, day: min(day, lastDay))
}

private func mostRecentDayOnOrBefore(_ asOf: Ymd, _ day: Int) -> Ymd {
    let cand = clampDayYmd(asOf.year, asOf.month - 1, day)
    if cand <= asOf { return cand }
    return clampDayYmd(asOf.year, asOf.month - 1 - 1, day)
}

private func nextDayStrictlyAfter(_ from: Ymd, _ day: Int) -> Ymd {
    let cand = clampDayYmd(from.year, from.month - 1, day)
    if cand > from { return cand }
    return clampDayYmd(from.year, from.month - 1 + 1, day)
}

public struct BillingCycle: Equatable {
    public let cycleStart: Ymd
    public let statementDate: Ymd
    public let dueDate: Ymd
}

/// The currently-open billing cycle for a card. Charges made now belong to
/// this cycle; it closes on statementDate and is due on dueDate. Handles
/// months shorter than the chosen day (e.g. a 31st statement day in Feb).
public func billingCycle(_ statementDay: Int, _ dueDay: Int, _ asOf: Ymd) -> BillingCycle {
    let previousStatement = mostRecentDayOnOrBefore(asOf, statementDay)
    let cycleStart = addDaysYmd(previousStatement, 1)
    let statementDate = nextDayStrictlyAfter(previousStatement, statementDay)
    let dueDate = nextDayStrictlyAfter(statementDate, dueDay)
    return BillingCycle(cycleStart: cycleStart, statementDate: statementDate, dueDate: dueDate)
}
