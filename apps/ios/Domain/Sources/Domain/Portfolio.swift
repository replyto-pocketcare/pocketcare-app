import Foundation

/// Portfolio analytics for the Investments screen -- the maths behind the
/// allocation donut, the gain/loss-by-group bars, the "dividends earned this
/// financial year" card and the wealth projection. Mirrors Android's
/// domain/investments/Portfolio.kt function for function.
///
/// Ported from apps/web/app/investments/page.tsx (the `dividendFY` memo and
/// the two chart `data` props), apps/web/src/investments/model.ts (the
/// financial-year helpers) and apps/web/src/market/ProjectionPanel.tsx (the
/// compounding loop). On web all four live INSIDE React components, so they
/// cannot be recorded from a browser -- these vectors are the specification,
/// transcribed from the source, the same arrangement the dashboard grid and
/// category tree already use.
///
/// Everything here is in MINOR units. The panels feed charts, and a chart is
/// exactly where web's own division by a hundred leaked: the conversion to a
/// plottable Double happens once, in the view model, through
/// `majorScale(currency)`.

// MARK: - allocation & gain-by-group

/// One slice of the allocation donut: a group's share of portfolio value.
public struct AllocationSlice: Sendable {
    public let key: String
    public let label: String
    public let valueBase: Int64
    public let sharePct: Double
}

/// Allocation slices, largest first.
///
/// Zero- and negative-valued groups are dropped rather than drawn: web's
/// `AllocationDonut` filters on `value > 0` before it assigns colours, so a
/// fully-redeemed group must not consume a palette entry here either, or the
/// two platforms colour the same portfolio differently.
///
/// `sharePct` is computed over the SURVIVING total, matching web's own
/// tooltip (`value / total`, where `total` is the sum of the filtered slices).
public func allocationSlices(_ groups: [InvestmentGroup]) -> [AllocationSlice] {
    let kept = groups.filter { $0.value > 0 }
    let total = kept.reduce(Int64(0)) { $0 + $1.value }
    if total <= 0 { return [] }
    return kept
        .map { AllocationSlice(key: $0.key, label: $0.label, valueBase: $0.value, sharePct: (Double($0.value) / Double(total)) * 100.0) }
        .sorted { a, b in a.valueBase != b.valueBase ? a.valueBase > b.valueBase : a.label < b.label }
}

/// One bar of the gain/loss-by-group chart. Signed: a loss is negative.
public struct GainBar: Sendable {
    public let key: String
    public let label: String
    public let gainBase: Int64
}

/// Gain/loss per group, in the group order the tiles already use.
///
/// Unlike `allocationSlices` nothing is filtered -- a group that is down is
/// the whole point of the chart, and web passes every group straight through.
public func gainBars(_ groups: [InvestmentGroup]) -> [GainBar] {
    groups.map { GainBar(key: $0.key, label: $0.label, gainBase: $0.gain) }
}

// MARK: - financial year

/// The Indian financial year containing a date: April 1st to March 31st.
///
/// `startYear` is the calendar year the year OPENED in and `endYearShort` the
/// two-digit year it closes in, so a label reads "FY 2026-27". The formatting
/// itself is deliberately NOT done here: web builds the string in model.ts and
/// hardcodes the English "FY " prefix, which is exactly the kind of literal
/// this port is not allowed to carry. The UI joins these two numbers through
/// `investments:fyLabel`.
public struct FinancialYear: Sendable, Equatable {
    public let startYear: Int
    public let endYearShort: String
}

/// Dates are passed and compared as `yyyy-MM-dd` STRINGS, not as Date.
///
/// Every date column in the schema already stores that shape, the comparison
/// web performs is a calendar-day one, and `yyyy-MM-dd` sorts
/// lexicographically in calendar order -- so a string compare is not a
/// shortcut, it is the exact question being asked. It also keeps this file
/// free of `Calendar`/`TimeZone` on one platform and `java.time` on the other,
/// which is where the two ports would otherwise disagree about what "today"
/// means east of Greenwich.
private func yearOf(_ iso: String) -> Int? { Int(iso.prefix(4)) }

private func monthOf(_ iso: String) -> Int? {
    guard iso.count >= 7 else { return nil }
    let start = iso.index(iso.startIndex, offsetBy: 5)
    let end = iso.index(iso.startIndex, offsetBy: 7)
    return Int(iso[start..<end])
}

/// Start (Apr 1) of the financial year containing `todayIso`, as `yyyy-MM-dd`.
public func fyStart(_ todayIso: String) -> String {
    let year = yearOf(todayIso) ?? 0
    let month = monthOf(todayIso) ?? 1
    // Months are 1-based here and 0-based in JS: web's `getMonth() >= 3` is
    // April onwards, which is `month >= 4`.
    let startYear = month >= 4 ? year : year - 1
    return String(format: "%04d-04-01", startYear)
}

/// The financial year containing `todayIso`, as its two label parts.
public func financialYear(_ todayIso: String) -> FinancialYear {
    let start = yearOf(fyStart(todayIso)) ?? 0
    return FinancialYear(startYear: start, endYearShort: String(format: "%02d", (start + 1) % 100))
}

/// Whether an ISO date falls inside the current financial year, on or before
/// today. Anything that is not a `yyyy-MM-dd` prefix is excluded rather than
/// thrown on, matching web's `Number.isNaN(d.getTime())` guard.
public func inCurrentFyToDate(_ iso: String, _ todayIso: String) -> Bool {
    let day = String(iso.prefix(10))
    guard day.count >= 10, yearOf(day) != nil, monthOf(day) != nil else { return false }
    return day >= fyStart(todayIso) && day <= String(todayIso.prefix(10))
}

/// Dividends actually received so far this financial year, in base minor units.
///
/// Upcoming (scheduled, not yet ex-dated) events are excluded: the card says
/// "earned", and counting a dividend the market has not paid yet would inflate
/// the only realised-income figure on the screen.
public func dividendsThisFy(_ events: [DivEvent], _ todayIso: String) -> Int64 {
    events.filter { !$0.upcoming && inCurrentFyToDate($0.date, todayIso) }.reduce(Int64(0)) { $0 + $1.base }
}

// MARK: - projection

/// One yearly sample of the projection curve.
public struct ProjectionPoint: Sendable {
    public let yearsOut: Int
    public let valueBase: Int64
    public let contributedBase: Int64
}

public struct Projection: Sendable {
    public let points: [ProjectionPoint]
    public let endValueBase: Int64
    public let contributedBase: Int64
    /// End value minus everything paid in -- the part that is return, not saving.
    public let growthBase: Int64
}

/// The effective dividend yield used for reinvestment: last twelve months of
/// income over current value, falling back to the next twelve months when
/// nothing has been paid yet. Zero when there is nothing to divide by.
public func dividendYieldRate(_ annualDividendBase: Int64, _ currentValueBase: Int64) -> Double {
    currentValueBase > 0 ? Double(annualDividendBase) / Double(currentValueBase) : 0
}

/// Compound the portfolio forward month by month, matching
/// ProjectionPanel.tsx's loop exactly.
///
/// The order inside the month is load-bearing and is web's: grow, then add the
/// contribution, then (optionally) credit a twelfth of the dividend yield on
/// the post-contribution balance. Reordering any two of those three changes
/// the answer, so it is transcribed rather than tidied.
///
/// `growthPctPerYear` is a nominal annual rate converted to a monthly one by
/// the twelfth root, NOT by dividing by twelve -- web compounds, and dividing
/// would over-state a 15% assumption by about a percentage point over 15 years.
public func projectPortfolio(
    currentValueBase: Int64,
    growthPctPerYear: Double,
    monthlyContributionBase: Int64,
    years: Int,
    reinvestDividends: Bool,
    dividendYieldRate: Double
) -> Projection {
    let monthlyGrowth = pow(1.0 + growthPctPerYear / 100.0, 1.0 / 12.0) - 1.0
    var value = Double(currentValueBase)
    var paidIn = Double(currentValueBase)
    var points = [ProjectionPoint(yearsOut: 0, valueBase: Int64(value.rounded()), contributedBase: Int64(paidIn.rounded()))]
    let months = years > 0 ? years * 12 : 0
    if months > 0 {
        for m in 1...months {
            value = value * (1.0 + monthlyGrowth) + Double(monthlyContributionBase)
            if reinvestDividends { value += (value * dividendYieldRate) / 12.0 }
            paidIn += Double(monthlyContributionBase)
            if m % 12 == 0 {
                points.append(ProjectionPoint(yearsOut: m / 12, valueBase: Int64(value.rounded()), contributedBase: Int64(paidIn.rounded())))
            }
        }
    }
    let end = Int64(value.rounded())
    let contributed = Int64(paidIn.rounded())
    return Projection(points: points, endValueBase: end, contributedBase: contributed, growthBase: end - contributed)
}

// MARK: - SIP

/// The day-of-month a SIP is debited, clamped to 1-28.
///
/// The column is documented as 1-28 for the reason PARITY_AUDIT records under
/// `anchor_day`: a monthly schedule anchored on the 29th, 30th or 31st walks
/// backwards through short months and never returns. Web clamps at the input;
/// so does this, and it is in Domain so both platforms clamp identically
/// rather than each screen re-deriving the rule.
public func clampSipDay(_ day: Int) -> Int { min(28, max(1, day)) }
