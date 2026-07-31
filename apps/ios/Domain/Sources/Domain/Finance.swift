import Foundation

// Ported from packages/core/finance/src/index.ts (P1.3b). Mirrors
// apps/android/domain/.../finance/Finance.kt (P1.3a) field-for-field.
// Correctness is judged against tools/golden-vectors/vectors/finance.json,
// not a fresh reading of the TS -- see docs/plans/native-mobile-apps.md
// section 5 and CLAUDE.md golden rule 8 ("web is the spec").
//
// Rounding: the TS source uses JS's Math.round throughout, which ties
// round TOWARD +INFINITY (Math.round(2.5) == 3, Math.round(-2.5) == -2) --
// a DIFFERENT rule from Money.swift's round-half-AWAY-from-zero (where
// -2.5 would round to -3). Swift's Double.rounded(.toNearestOrAwayFromZero)
// is therefore the WRONG rounding rule here. Verified via search (MDN's
// own Math.round example, "ties toward +Infinity") rather than assumed;
// `jsMathRound` below is the standard floor(x + 0.5) equivalent, confirmed
// against the same source to match Math.round for every case that matters
// here (the two functions only disagree at -0/-0.5<=x<0, where both
// represent the value 0 anyway once converted to an integer).

private func jsMathRound(_ x: Double) -> Double {
    (x + 0.5).rounded(.down)
}

/// Stands in for the TS source's plain `new Error(message)` call sites in
/// this domain (futureValue's "periods must be >= 0",
/// projectCashflow's "years must be >= 0") -- same role as Money.swift's
/// MoneyError. Neither validation path is exercised by finance.json (0
/// throws vectors in this domain), but `throws`/FinanceError is used here
/// rather than `precondition`/`fatalError` for consistency with the rest
/// of the Domain package: a validation failure should be a catchable
/// error a caller can handle, not an uncatchable crash.
public struct FinanceError: Error, CustomStringConvertible {
    public let description: String
}

/// How many times each budgeting/commitment period occurs per year.
private let periodsPerYear: [String: Int] = [
    "daily": 365,
    "weekly": 52,
    "monthly": 12,
    "yearly": 1,
]

/// Future value of a starting principal plus a recurring contribution made
/// every period, compounded at periodicRate. Returns a rounded minor-unit Int64.
public func futureValue(_ principal: Int64, _ contribution: Int64, _ periodicRate: Double, _ periods: Int) throws -> Int64 {
    guard periods >= 0 else { throw FinanceError(description: "periods must be >= 0") }
    let fv: Double
    if periodicRate == 0 {
        fv = Double(principal) + Double(contribution) * Double(periods)
    } else {
        let growth = pow(1 + periodicRate, Double(periods))
        fv = Double(principal) * growth + Double(contribution) * ((growth - 1) / periodicRate)
    }
    return Int64(jsMathRound(fv))
}

/// Convert an annual percentage rate (e.g. 8 for 8%) to a per-period decimal.
public func periodicRateFromAnnual(_ annualPct: Double, _ period: String) -> Double {
    annualPct / 100 / Double(periodsPerYear[period]!)
}

/// Number of whole periods until `current` grows to `target`. Returns
/// Double.infinity if the goal can never be reached (mirrors the TS
/// source's JS Infinity, which JSON.stringify writes as `null`).
public func periodsToGoal(_ current: Int64, _ target: Int64, _ contribution: Int64, _ periodicRate: Double) -> Double {
    if current >= target { return 0 }
    if periodicRate == 0 {
        if contribution <= 0 { return .infinity }
        return (Double(target - current) / Double(contribution)).rounded(.up)
    }
    let numerator = Double(target) * periodicRate + Double(contribution)
    let denominator = Double(current) * periodicRate + Double(contribution)
    if denominator <= 0 || numerator <= 0 { return .infinity }
    let n = log(numerator / denominator) / log(1 + periodicRate)
    if !n.isFinite || n < 0 { return .infinity }
    return n.rounded(.up)
}

/// Normalize any period amount to its monthly equivalent (rounded minor units).
public func monthlyEquivalent(_ amount: Int64, _ period: String) -> Int64 {
    let perYear = periodsPerYear[period]!
    return Int64(jsMathRound(Double(amount) * Double(perYear) / 12))
}

public struct RecurringLike {
    public let amount: Int64
    public let frequency: String
    public init(amount: Int64, frequency: String) {
        self.amount = amount
        self.frequency = frequency
    }
}

/// Total monthly cost of a set of recurring commitments (EMIs, subs, expenses).
public func recurringMonthlyTotal(_ items: [RecurringLike]) -> Int64 {
    items.reduce(Int64(0)) { $0 + monthlyEquivalent($1.amount, $1.frequency) }
}

/// What percentage of monthly income the given monthly amount represents.
/// Double.infinity when monthlyIncome <= 0 (mirrors JS Infinity).
public func percentOfIncome(_ monthlyAmount: Int64, _ monthlyIncome: Int64) -> Double {
    if monthlyIncome <= 0 { return .infinity }
    return (Double(monthlyAmount) / Double(monthlyIncome)) * 100
}

public struct SubscriptionImpact: Equatable {
    public let totalPaid: Int64
    public let opportunityCost: Int64
}

/// Project the impact of a subscription over `years`, assuming the money
/// could otherwise be invested at annualReturnPct. Contributions modelled monthly.
public func subscriptionImpact(_ amount: Int64, _ frequency: String, _ years: Double, _ annualReturnPct: Double) throws -> SubscriptionImpact {
    let monthly = monthlyEquivalent(amount, frequency)
    let months = Int(jsMathRound(years * 12))
    let totalPaid = monthly * Int64(months)
    let r = annualReturnPct / 100 / 12
    // Int64(0), not the bare literal 0 -- see Money.swift's sum() comment;
    // futureValue has two Int64/Double-adjacent parameters so this is worth
    // staying explicit about even though only one overload of futureValue
    // exists here (unlike money()'s two overloads).
    let invested = try futureValue(Int64(0), monthly, r, months)
    return SubscriptionImpact(totalPaid: totalPaid, opportunityCost: invested)
}

public struct CashflowInputs {
    public let monthlyIncome: Int64
    public let monthlyPayments: Int64
    public let monthlySavings: Int64
    public let currentSavings: Int64
    public let annualReturnPct: Double
    public let annualInflationPct: Double
    public let incomeGrowthPct: Double

    public init(monthlyIncome: Int64, monthlyPayments: Int64, monthlySavings: Int64, currentSavings: Int64, annualReturnPct: Double, annualInflationPct: Double, incomeGrowthPct: Double = 0) {
        self.monthlyIncome = monthlyIncome
        self.monthlyPayments = monthlyPayments
        self.monthlySavings = monthlySavings
        self.currentSavings = currentSavings
        self.annualReturnPct = annualReturnPct
        self.annualInflationPct = annualInflationPct
        self.incomeGrowthPct = incomeGrowthPct
    }
}

public struct YearProjection: Equatable {
    public let year: Int
    public let income: Int64
    public let payments: Int64
    public let savingsContributed: Int64
    public let netCashflow: Int64
    public let savingsBalance: Int64
    public let realSavingsBalance: Int64
}

/// Project year-by-year cashflow and savings growth over `years`. Income
/// and payments step up once per year; savings compound monthly at the
/// annual return and receive the monthly contribution.
public func projectCashflow(_ inp: CashflowInputs, _ years: Int) throws -> [YearProjection] {
    guard years >= 0 else { throw FinanceError(description: "years must be >= 0") }
    let monthlyReturn = inp.annualReturnPct / 100 / 12
    let inflation = inp.annualInflationPct / 100
    let incomeGrowth = inp.incomeGrowthPct / 100

    var savings = Double(inp.currentSavings)
    var out: [YearProjection] = []

    if years >= 1 {
        for y in 1...years {
            let growthFactor = pow(1 + incomeGrowth, Double(y - 1))
            let inflationFactor = pow(1 + inflation, Double(y - 1))
            let income = Int64(jsMathRound(Double(inp.monthlyIncome) * growthFactor))
            let payments = Int64(jsMathRound(Double(inp.monthlyPayments) * inflationFactor))
            let contribution = Int64(jsMathRound(Double(inp.monthlySavings) * inflationFactor))

            var yearIncome: Int64 = 0
            var yearPayments: Int64 = 0
            var yearContrib: Int64 = 0
            for _ in 0..<12 {
                yearIncome += income
                yearPayments += payments
                yearContrib += contribution
                savings = savings * (1 + monthlyReturn) + Double(contribution)
            }
            let realDeflator = pow(1 + inflation, Double(y))
            out.append(
                YearProjection(
                    year: y,
                    income: yearIncome,
                    payments: yearPayments,
                    savingsContributed: yearContrib,
                    netCashflow: yearIncome - yearPayments - yearContrib,
                    savingsBalance: Int64(jsMathRound(savings)),
                    realSavingsBalance: Int64(jsMathRound(savings / realDeflator))
                )
            )
        }
    }
    return out
}

/// Convert an amount from any period to its yearly equivalent (rounded minor units).
public func yearlyEquivalent(_ amount: Int64, _ period: String) -> Int64 {
    Int64(jsMathRound(Double(amount) * Double(periodsPerYear[period]!)))
}

public struct AmortRow: Equatable {
    public let month: Int
    public let emi: Int64
    public let interest: Int64
    public let principal: Int64
    public let balance: Int64
}

/// Standard reducing-balance EMI for a fixed-rate loan (minor-unit Int64).
/// A 0% (or missing) rate gives the flat P/n. Returns 0 for a non-positive tenure.
public func emiFromPrincipal(_ principal: Int64, _ annualRatePct: Double, _ tenureMonths: Int) -> Int64 {
    let p = max(Int64(0), principal)
    let n = max(0, tenureMonths)
    if p <= 0 || n <= 0 { return 0 }
    let r = annualRatePct / 100 / 12
    if r <= 0 { return Int64(jsMathRound(Double(p) / Double(n))) }
    let powv = pow(1 + r, Double(n))
    return Int64(jsMathRound(Double(p) * r * powv / (powv - 1)))
}

/// Reducing-balance amortization schedule. Stops at maxMonths (capped
/// 1200, matching the TS source) or when the balance hits zero; returns an
/// empty array if the EMI can't even cover the first month's interest.
public func amortizationSchedule(_ principal: Int64, _ annualRatePct: Double, _ emi: Int64, _ maxMonths: Int) -> [AmortRow] {
    var rows: [AmortRow] = []
    let r = annualRatePct / 100 / 12
    var balance = max(Int64(0), principal)
    let emiRounded = emi
    let cap = min(maxMonths > 0 ? maxMonths : 1200, 1200)

    var m = 1
    while m <= cap && balance > 0 {
        let interest = Int64(jsMathRound(Double(balance) * r))
        var principalPaid = emiRounded - interest
        if principalPaid <= 0 { break }
        var pay = emiRounded
        if principalPaid >= balance {
            principalPaid = balance
            pay = balance + interest
        }
        balance -= principalPaid
        rows.append(AmortRow(month: m, emi: pay, interest: interest, principal: principalPaid, balance: balance))
        m += 1
    }
    return rows
}

/// Convert a monthly minor-unit amount to a given timeframe bucket total.
public func timeframeTotal(_ monthlyAmount: Int64, _ timeframe: String) -> Int64 {
    let mult: Int64 = timeframe == "monthly" ? 1 : (timeframe == "quarterly" ? 3 : 12)
    return monthlyAmount * mult
}

// --- Loan EMI scheduling -----------------------------------------------------
// Pure calendar-date math for "which EMI is due when", transliterated
// directly from the TS source's own (y, month0, day) arithmetic. `month`
// here is 0-based, matching the TS source directly (unlike Budget.swift's
// own Ymd type, which is a separate, unrelated type using a 1-based
// month -- these two files intentionally don't share a date type, since
// their needs differ: this one only ever builds/compares/prints
// YYYY-MM-DD strings, Budget.swift's needs real day-level +N arithmetic).

private struct FinanceYmd {
    let y: Int
    let m: Int // 0-based
    let d: Int
}

private func parseYmd(_ iso: String?) -> FinanceYmd? {
    guard let iso else { return nil }
    let s = String(iso.prefix(10))
    let parts = s.split(separator: "-")
    guard parts.count == 3, s.count == 10,
          let y = Int(parts[0]), let mm = Int(parts[1]), let d = Int(parts[2]) else { return nil }
    let m = mm - 1
    if m < 0 || m > 11 || d < 1 || d > 31 { return nil }
    return FinanceYmd(y: y, m: m, d: d)
}

private func isLeapYear(_ y: Int) -> Bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

/// Days in month `m0` (0-based) of year `y`. Standard Gregorian rule --
/// same rule java.time (Kotlin port) and JS's Date.UTC both implement.
func daysInMonth(_ y: Int, _ m0: Int) -> Int {
    switch m0 {
    case 0, 2, 4, 6, 7, 9, 11: return 31
    case 3, 5, 8, 10: return 30
    case 1: return isLeapYear(y) ? 29 : 28
    default: return 30
    }
}

private func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    let r = a % b
    return (r != 0 && (r < 0) != (b < 0)) ? q - 1 : q
}

private func floorMod(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return (r != 0 && (r < 0) != (b < 0)) ? r + b : r
}

/// Build YYYY-MM-DD for (y, m0, day), normalizing month overflow and
/// clamping day to the month length -- mirrors the TS source's isoOf().
private func isoOf(_ y: Int, _ m0: Int, _ day: Int) -> String {
    let totalMonths = y * 12 + m0
    let ny = floorDiv(totalMonths, 12)
    let nm0 = floorMod(totalMonths, 12)
    let clamped = min(day, daysInMonth(ny, nm0))
    // POSIX locale explicitly, mirroring Finance.kt's Locale.ROOT -- %d is
    // digit-only so this shouldn't matter in practice, but this is a
    // byte-for-byte-compared vector string, so it's not worth trusting the
    // device's current locale for it.
    return String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"), ny, nm0 + 1, clamped)
}

/// Due date (YYYY-MM-DD) of EMI number `emiNo` (1-based). The FIRST EMI is
/// the first occurrence of `dueDay` strictly on/after the start date; each
/// subsequent EMI is one calendar month later (day clamped to the month).
public func emiDueDate(_ startIso: String?, _ dueDay: Int?, _ emiNo: Int) -> String? {
    guard let start = parseYmd(startIso) else { return nil }
    let day = (dueDay != nil && dueDay! >= 1 && dueDay! <= 31) ? dueDay! : start.d
    var firstMonthOffset = 0
    if day < start.d { firstMonthOffset = 1 }
    let n = max(1, emiNo)
    return isoOf(start.y, start.m + firstMonthOffset + (n - 1), day)
}

/// True if `dueIso` is on or before `asOfIso` (both YYYY-MM-DD, lexicographic == chronological).
public func isDuePassed(_ dueIso: String?, _ asOfIso: String) -> Bool {
    guard let dueIso else { return false }
    return dueIso <= String(asOfIso.prefix(10))
}

/// The set of EMI numbers that count as paid: manually-marked EMIs, plus
/// (when autoMark is on) every EMI whose due date has passed. Derived, not persisted.
public func effectivePaidEmis(
    manual: [Int],
    totalEmis: Int,
    autoMark: Bool = false,
    startIso: String? = nil,
    dueDay: Int? = nil,
    asOfIso: String
) -> Set<Int> {
    var out = Set<Int>(manual)
    let total = max(0, totalEmis)
    if autoMark && total > 0 {
        let asOf = String(asOfIso.prefix(10))
        for n in 1...total {
            let due = emiDueDate(startIso, dueDay, n)
            if isDuePassed(due, asOf) { out.insert(n) }
        }
    }
    return out
}
