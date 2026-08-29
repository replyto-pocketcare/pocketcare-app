import Foundation

/**
 One sampled point of a budget's cumulative-spend curve.

 The DAY, not a label. Web's chart builds `"12 Aug"` from the browser's locale
 inside the component; formatting a date is the view's job on a platform that
 has a locale, and returning the label here would ship one language into two
 otherwise localised apps — the same call `Trend.swift`'s `TrendBucket` already
 made.

 `cumulativeMinor` is MINOR units. Web's own chart divides by a hardcoded 100
 before handing the number to recharts, which draws a JPY budget at a hundredth
 of its real height; the conversion belongs at the drawing edge, with
 `majorScale(currency)`, not in the arithmetic.

 Mirrors `apps/android/.../domain/budget/SpendSeries.kt`.
 */
public struct SpendPoint: Sendable, Equatable {
    public let dayIso: String
    public let cumulativeMinor: Int64

    public init(dayIso: String, cumulativeMinor: Int64) {
        self.dayIso = dayIso
        self.cumulativeMinor = cumulativeMinor
    }
}

/**
 The running total of spend across a budget's active window, sampled the way
 web's `BudgetSpendChart` samples it.

 A port of the series builder inlined in apps/web/app/budgets/page.tsx, with
 `today` passed in rather than read from the clock — which is what makes it
 testable, and is why there are vectors for it
 (tools/golden-vectors/vectors/budget-spend-series.json).

 Web's shape, preserved exactly:
 - The window runs from `startIso` to `endIso` inclusive, but is CLAMPED to
   today: a monthly budget on the 8th draws eight points, not thirty-one. A
   curve that runs flat to the end of the month reads as "you stopped
   spending", which is the opposite of what it means.
 - `step` is 7 for a window longer than 92 days, 1 otherwise, so a yearly
   budget draws ~52 points instead of 365.
 - The LAST day of the span is always sampled even when it is not on a step
   boundary, so the curve ends where the spend actually ended.
 - `spanDays` has a floor of 1 (web's `Math.max(1, …)`), which is what makes a
   budget whose window starts in the future terminate immediately: the one
   iteration breaks on `day > today` and the series comes back empty.

 Callers hide the chart entirely below two points — web returns `null` from the
 component in that case. Kept as a caller decision rather than folded in here so
 the vectors can pin the one-point series rather than an empty one.

 Day arithmetic goes through `isoDaysOrNil`/`isoFromEpochDays` (Hinnant's
 civil-date algorithms, already in this module) rather than `Calendar`, for the
 same reason `Budget.swift` hand-rolls `Ymd`: a `Calendar` silently reverts to
 the device's time zone unless every value involved is airtight about UTC, and
 this function has to agree with `java.time.LocalDate` on the other platform.

 - Parameter dailyTotals: `YYYY-MM-DD` to minor units, ALREADY scoped to the
   budget by the query that produced it. Days with no spend may be absent.
 */
public func cumulativeSpendSeries(
    _ dailyTotals: [String: Int64],
    startIso: String,
    endIso: String,
    todayIso: String
) -> [SpendPoint] {
    // An unparseable date is a caller bug, not something to crash a card over,
    // and the Kotlin port guards its own parse the same way — a golden vector
    // pins the pair.
    guard let start = isoDaysOrNil(startIso),
          let end = isoDaysOrNil(endIso),
          let today = isoDaysOrNil(todayIso) else { return [] }

    let lastDay = end < today ? end : today
    let spanDays = max(1, lastDay - start + 1)
    let step = spanDays > 92 ? 7 : 1

    var out: [SpendPoint] = []
    var cumulative: Int64 = 0
    for i in 0..<spanDays {
        let day = start + i
        if day > today { break }
        let key = isoFromEpochDays(day)
        cumulative += dailyTotals[key] ?? 0
        if i % step == 0 || i == spanDays - 1 {
            out.append(SpendPoint(dayIso: key, cumulativeMinor: cumulative))
        }
    }
    return out
}
