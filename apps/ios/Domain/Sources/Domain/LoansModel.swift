import Foundation

/// Loans/EMI domain model (pure, UI-agnostic) -- Swift port of
/// `packages/core/finance/src/index.ts`'s `emiFromPrincipal`/
/// `amortizationSchedule`/`emiDueDate`/`effectivePaidEmis`, mirroring
/// Android's domain/loans/LoansModel.kt field-for-field (2026-08-06,
/// task #27). All money values are integer minor units; every
/// intermediate is rounded half-away-from-zero (`Math.round` in the TS
/// source), matching Swift's default `.rounded()` (`.toNearestOrAwayFromZero`)
/// for the always-non-negative values these functions handle.

/// Standard reducing-balance EMI for a fixed-rate loan (minor-unit integer).
///   EMI = P*r*(1+r)^n / ((1+r)^n - 1),  r = monthly rate, n = tenure in months.
/// A 0% (or missing) rate gives the flat P/n. Returns 0 for a non-positive tenure.
public func emiFromPrincipal(_ principal: Int64, _ annualRatePct: Double, _ tenureMonths: Int) -> Int64 {
    let p = max(0, principal)
    let n = max(0, tenureMonths)
    if p <= 0 || n <= 0 { return 0 }
    let r = annualRatePct / 100.0 / 12.0
    if r <= 0 { return Int64((Double(p) / Double(n)).rounded()) }
    let pow_ = pow(1 + r, Double(n))
    return Int64((Double(p) * r * pow_ / (pow_ - 1)).rounded())
}

public struct AmortRow: Sendable {
    /// 1-based EMI number.
    public let month: Int
    /// EMI actually paid this month (equals `emi`, except a smaller final payment).
    public let emi: Int64
    /// Interest portion of this EMI.
    public let interest: Int64
    /// Principal portion of this EMI.
    public let principal: Int64
    /// Outstanding principal after this EMI.
    public let balance: Int64
}

/// Reducing-balance amortization schedule. Each month, interest = balance
/// x monthly rate, and the rest of the EMI reduces principal. A 0% rate
/// gives a flat principal-only schedule. Stops at `maxMonths` (the tenure)
/// or when the balance hits zero; returns `[]` if the EMI can't even cover
/// the first month's interest (i.e. the loan would never amortize).
public func amortizationSchedule(_ principal: Int64, _ annualRatePct: Double, _ emi: Int64, _ maxMonths: Int) -> [AmortRow] {
    var rows: [AmortRow] = []
    let r = annualRatePct / 100.0 / 12.0
    var balance = max(0, principal)
    let emiRounded = emi
    let cap = min(maxMonths <= 0 ? 1200 : maxMonths, 1200)

    var m = 1
    while m <= cap && balance > 0 {
        let interest = Int64((Double(balance) * r).rounded())
        var principalPaid = emiRounded - interest
        if principalPaid <= 0 { break } // EMI doesn't cover interest -> never amortizes
        var pay = emiRounded
        if principalPaid >= balance {
            principalPaid = balance // final (partial) payment
            pay = balance + interest
        }
        balance -= principalPaid
        rows.append(AmortRow(month: m, emi: pay, interest: interest, principal: principalPaid, balance: balance))
        m += 1
    }
    return rows
}

private struct Ymd { let y: Int; let m0: Int; let d: Int }

/// Parse a YYYY-MM-DD (or ISO) string into y/m(0-based)/d, or nil.
private func ymd(_ iso: String?) -> Ymd? {
    guard let iso, !iso.isEmpty else { return nil }
    let s = String(iso.prefix(10))
    let parts = s.split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let mRaw = Int(parts[1]), let d = Int(parts[2]) else { return nil }
    let m = mRaw - 1
    guard m >= 0 && m <= 11 && d >= 1 && d <= 31 else { return nil }
    return Ymd(y: y, m0: m, d: d)
}

// `Calendar` is a Sendable value type, so a global `let` (not `var`) is
// safe under Swift 6 strict concurrency -- unlike the cached Foundation
// `Formatter` subclasses (`DateFormatter`/`ISO8601DateFormatter`) this
// codebase has twice hit real compiler errors for (see AUDIT_HISTORY.md's
// 2026-08-06 TransactionsViewModel.swift/DashboardView.swift entry),
// `Calendar` itself is not one of those non-Sendable reference types.
private let utcCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

/// Days in a given month (1-based month).
private func daysInMonth(_ y: Int, _ m1based: Int) -> Int {
    var comps = DateComponents()
    comps.year = y
    comps.month = m1based
    comps.day = 1
    let date = utcCalendar.date(from: comps)!
    return utcCalendar.range(of: .day, in: .month, for: date)?.count ?? 30
}

/// Build a YYYY-MM-DD for (y, m 0-based, day) clamping day to the month
/// length -- matches the TS source's `isoOf`'s month-overflow
/// normalization exactly (m can be < 0 or > 11 on input).
private func isoOf(_ y: Int, _ m0based: Int, _ day: Int) -> String {
    var comps = DateComponents()
    comps.year = y
    comps.month = m0based + 1 // Calendar folds out-of-range months
    comps.day = 1
    let base = utcCalendar.date(from: comps)!
    let baseComps = utcCalendar.dateComponents([.year, .month], from: base)
    let ny = baseComps.year!, nm = baseComps.month!
    let clamped = min(day, daysInMonth(ny, nm))
    return String(format: "%04d-%02d-%02d", ny, nm, clamped)
}

/// Due date (YYYY-MM-DD) of EMI number `emiNo` (1-based).
///
/// `startIso` is when the loan started. `dueDay` (1-31) is the day of the
/// month each EMI falls on; if nil, the start date's own day-of-month is
/// used. The FIRST EMI is the first occurrence of `dueDay` strictly on/after
/// the start date, and each subsequent EMI is one calendar month later
/// (day clamped to the month, e.g. a 31 due-day lands on Feb 28/29).
public func emiDueDate(_ startIso: String?, _ dueDay: Int?, _ emiNo: Int) -> String? {
    guard let start = ymd(startIso) else { return nil }
    let day = (dueDay != nil && dueDay! >= 1 && dueDay! <= 31) ? dueDay! : start.d
    let firstMonthOffset = day < start.d ? 1 : 0
    let n = max(1, emiNo)
    return isoOf(start.y, start.m0 + firstMonthOffset + (n - 1), day)
}

/// True if `dueIso` is on or before `asOfIso` (both YYYY-MM-DD, lexical compare).
public func isDuePassed(_ dueIso: String?, _ asOfIso: String) -> Bool {
    guard let dueIso, !dueIso.isEmpty else { return false }
    return dueIso <= String(asOfIso.prefix(10))
}

/// The set of EMI numbers that count as paid, given manually-marked EMIs
/// and an optional "auto-mark past-due" policy. Derived (not persisted)
/// so toggling auto-mark off instantly reverts the auto ones; manual
/// marks always win.
public func effectivePaidEmis(
    _ manual: [Int], totalEmis: Int, autoMark: Bool = false,
    startIso: String? = nil, dueDay: Int? = nil, asOfIso: String = isoToday()
) -> Set<Int> {
    var out = Set<Int>(manual)
    let total = max(0, totalEmis)
    if autoMark && total > 0 {
        for n in 1...total {
            let due = emiDueDate(startIso, dueDay, n)
            if isDuePassed(due, asOfIso) { out.insert(n) }
        }
    }
    return out
}

/// Today's date as YYYY-MM-DD (UTC), matching the TS default's
/// `new Date().toISOString().slice(0, 10)`.
public func isoToday() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: Date())
}
