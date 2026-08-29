package com.sanvya.app.domain.investments

import com.sanvya.app.domain.insights.DivEvent
import kotlin.math.pow
import kotlin.math.roundToLong

/**
 * Portfolio analytics for the Investments screen -- the maths behind the
 * allocation donut, the gain/loss-by-group bars, the "dividends earned this
 * financial year" card and the wealth projection.
 *
 * Ported from apps/web/app/investments/page.tsx (the `dividendFY` memo and
 * the two chart `data` props), apps/web/src/investments/model.ts (the
 * financial-year helpers) and apps/web/src/market/ProjectionPanel.tsx (the
 * compounding loop). On web all four live INSIDE React components, so they
 * cannot be recorded from a browser -- these vectors are the specification,
 * transcribed from the source, the same arrangement the dashboard grid and
 * category tree already use.
 *
 * Everything here is in MINOR units. The panels feed charts, and a chart is
 * exactly where web's own ÷100 leaked: the conversion to a plottable Double
 * happens once, in the view model, through `majorScale(currency)`.
 */

// --- allocation & gain-by-group ---------------------------------------------

/** One slice of the allocation donut: a group's share of portfolio value. */
data class AllocationSlice(val key: String, val label: String, val valueBase: Long, val sharePct: Double)

/**
 * Allocation slices, largest first.
 *
 * Zero- and negative-valued groups are dropped rather than drawn: web's
 * `AllocationDonut` filters on `value > 0` before it assigns colours, so a
 * fully-redeemed group must not consume a palette entry here either, or the
 * two platforms colour the same portfolio differently.
 *
 * `sharePct` is computed over the SURVIVING total, matching web's own
 * tooltip (`value / total`, where `total` is the sum of the filtered slices).
 */
fun allocationSlices(groups: List<Group>): List<AllocationSlice> {
    val kept = groups.filter { it.value > 0L }
    val total = kept.sumOf { it.value }
    if (total <= 0L) return emptyList()
    return kept
        .map { AllocationSlice(it.key, it.label, it.value, (it.value.toDouble() / total.toDouble()) * 100.0) }
        .sortedWith(compareByDescending<AllocationSlice> { it.valueBase }.thenBy { it.label })
}

/** One bar of the gain/loss-by-group chart. Signed: a loss is negative. */
data class GainBar(val key: String, val label: String, val gainBase: Long)

/**
 * Gain/loss per group, in the group order the tiles already use.
 *
 * Unlike [allocationSlices] nothing is filtered -- a group that is down is
 * the whole point of the chart, and web passes every group straight through.
 */
fun gainBars(groups: List<Group>): List<GainBar> =
    groups.map { GainBar(it.key, it.label, it.gain) }

// --- financial year ---------------------------------------------------------

/**
 * The Indian financial year containing a date: April 1st to March 31st.
 *
 * [startYear] is the calendar year the year OPENED in and [endYearShort] the
 * two-digit year it closes in, so a label reads "FY 2026-27". The formatting
 * itself is deliberately NOT done here: web builds the string in model.ts and
 * hardcodes the English "FY " prefix, which is exactly the kind of literal
 * this port is not allowed to carry. The UI joins these two numbers through
 * `investments:fyLabel`.
 */
data class FinancialYear(val startYear: Int, val endYearShort: String)

/**
 * Dates are passed and compared as `yyyy-MM-dd` STRINGS, not as LocalDate or
 * Date.
 *
 * Every date column in the schema already stores that shape, the comparison
 * web performs is a calendar-day one, and `yyyy-MM-dd` sorts lexicographically
 * in calendar order -- so a string compare is not a shortcut, it is the exact
 * question being asked. It also keeps this file free of `java.time` on one
 * platform and `Calendar`/`TimeZone` on the other, which is where the two
 * ports would otherwise disagree about what "today" means east of Greenwich.
 */
private fun yearOf(iso: String): Int? = iso.take(4).toIntOrNull()
private fun monthOf(iso: String): Int? = if (iso.length >= 7) iso.substring(5, 7).toIntOrNull() else null

/** Start (Apr 1) of the financial year containing [todayIso], as `yyyy-MM-dd`. */
fun fyStart(todayIso: String): String {
    val year = yearOf(todayIso) ?: 0
    val month = monthOf(todayIso) ?: 1
    // Months are 1-based here and 0-based in JS: web's `getMonth() >= 3` is
    // April onwards, which is `month >= 4`.
    val startYear = if (month >= 4) year else year - 1
    return "${startYear.toString().padStart(4, '0')}-04-01"
}

/** The financial year containing [todayIso], as its two label parts. */
fun financialYear(todayIso: String): FinancialYear {
    val start = yearOf(fyStart(todayIso)) ?: 0
    return FinancialYear(start, ((start + 1) % 100).toString().padStart(2, '0'))
}

/**
 * Whether an ISO date falls inside the current financial year, on or before
 * today. Anything that is not a `yyyy-MM-dd` prefix is excluded rather than
 * thrown on, matching web's `Number.isNaN(d.getTime())` guard.
 */
fun inCurrentFyToDate(iso: String, todayIso: String): Boolean {
    val day = iso.take(10)
    if (day.length < 10 || yearOf(day) == null || monthOf(day) == null) return false
    return day >= fyStart(todayIso) && day <= todayIso.take(10)
}

/**
 * Dividends actually received so far this financial year, in base minor units.
 *
 * Upcoming (scheduled, not yet ex-dated) events are excluded: the card says
 * "earned", and counting a dividend the market has not paid yet would inflate
 * the only realised-income figure on the screen.
 */
fun dividendsThisFy(events: List<DivEvent>, todayIso: String): Long =
    events.filter { !it.upcoming && inCurrentFyToDate(it.date, todayIso) }.sumOf { it.base }

// --- projection -------------------------------------------------------------

/** One yearly sample of the projection curve. */
data class ProjectionPoint(val yearsOut: Int, val valueBase: Long, val contributedBase: Long)

data class Projection(
    val points: List<ProjectionPoint>,
    val endValueBase: Long,
    val contributedBase: Long,
    /** End value minus everything paid in -- the part that is return, not saving. */
    val growthBase: Long,
)

/**
 * The effective dividend yield used for reinvestment: last twelve months of
 * income over current value, falling back to the next twelve months when
 * nothing has been paid yet. Zero when there is nothing to divide by.
 */
fun dividendYieldRate(annualDividendBase: Long, currentValueBase: Long): Double =
    if (currentValueBase > 0L) annualDividendBase.toDouble() / currentValueBase.toDouble() else 0.0

/**
 * Compound the portfolio forward month by month, matching
 * ProjectionPanel.tsx's loop exactly.
 *
 * The order inside the month is load-bearing and is web's: grow, then add the
 * contribution, then (optionally) credit a twelfth of the dividend yield on
 * the post-contribution balance. Reordering any two of those three changes
 * the answer, so it is transcribed rather than tidied.
 *
 * [growthPctPerYear] is a nominal annual rate converted to a monthly one by
 * the twelfth root, NOT by dividing by twelve -- web compounds, and dividing
 * would over-state a 15% assumption by about a percentage point over 15 years.
 */
fun projectPortfolio(
    currentValueBase: Long,
    growthPctPerYear: Double,
    monthlyContributionBase: Long,
    years: Int,
    reinvestDividends: Boolean,
    dividendYieldRate: Double,
): Projection {
    val monthlyGrowth = (1.0 + growthPctPerYear / 100.0).pow(1.0 / 12.0) - 1.0
    var value = currentValueBase.toDouble()
    var paidIn = currentValueBase.toDouble()
    val points = mutableListOf(ProjectionPoint(0, value.roundToLong(), paidIn.roundToLong()))
    val months = if (years > 0) years * 12 else 0
    for (m in 1..months) {
        value = value * (1.0 + monthlyGrowth) + monthlyContributionBase.toDouble()
        if (reinvestDividends) value += (value * dividendYieldRate) / 12.0
        paidIn += monthlyContributionBase.toDouble()
        if (m % 12 == 0) points.add(ProjectionPoint(m / 12, value.roundToLong(), paidIn.roundToLong()))
    }
    val end = value.roundToLong()
    val contributed = paidIn.roundToLong()
    return Projection(points, end, contributed, end - contributed)
}

// --- SIP --------------------------------------------------------------------

/**
 * The day-of-month a SIP is debited, clamped to 1-28.
 *
 * The column is documented as 1-28 for the reason PARITY_AUDIT records under
 * `anchor_day`: a monthly schedule anchored on the 29th, 30th or 31st walks
 * backwards through short months and never returns. Web clamps at the input;
 * so does this, and it is in Domain so both platforms clamp identically
 * rather than each screen re-deriving the rule.
 */
fun clampSipDay(day: Int): Int = day.coerceIn(1, 28)
