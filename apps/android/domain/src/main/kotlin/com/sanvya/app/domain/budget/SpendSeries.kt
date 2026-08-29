package com.sanvya.app.domain.budget

import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.max

/**
 * One sampled point of a budget's cumulative-spend curve.
 *
 * The DAY, not a label. Web's chart builds `"12 Aug"` from the browser's
 * locale inside the component; formatting a date is the view's job on a
 * platform that has a locale, and returning the label here would ship one
 * language into two otherwise localised apps -- the same call Trend.kt's
 * `TrendBucket` already made.
 *
 * `cumulativeMinor` is MINOR units. Web's own chart divides by a hardcoded
 * 100 before handing the number to recharts, which draws a JPY budget at a
 * hundredth of its real height; the conversion belongs at the drawing edge,
 * with `majorScale(currency)`, not in the arithmetic.
 */
data class SpendPoint(val dayIso: String, val cumulativeMinor: Long)

/**
 * The running total of spend across a budget's active window, sampled the way
 * web's `BudgetSpendChart` samples it.
 *
 * A port of the series builder inlined in apps/web/app/budgets/page.tsx, with
 * `today` passed in rather than read from the clock -- which is what makes it
 * testable, and is why there are vectors for it
 * (tools/golden-vectors/vectors/budget-spend-series.json).
 *
 * Web's shape, preserved exactly:
 * - The window runs from `startIso` to `endIso` inclusive, but is CLAMPED to
 *   today: a monthly budget on the 8th draws eight points, not thirty-one.
 *   A curve that runs flat to the end of the month reads as "you stopped
 *   spending", which is the opposite of what it means.
 * - `step` is 7 for a window longer than 92 days, 1 otherwise, so a yearly
 *   budget draws ~52 points instead of 365.
 * - The LAST day of the span is always sampled even when it is not on a step
 *   boundary, so the curve ends where the spend actually ended.
 * - `spanDays` has a floor of 1 (web's `Math.max(1, …)`), which is what makes
 *   a budget whose window starts in the future terminate immediately: the one
 *   iteration breaks on `day > today` and the series comes back empty.
 *
 * Callers hide the chart entirely below two points -- web returns `null` from
 * the component in that case. Kept as a caller decision rather than folded in
 * here so the vectors can pin the one-point series rather than an empty one.
 *
 * @param dailyTotals `YYYY-MM-DD` to minor units, ALREADY scoped to the budget
 *   by the query that produced it. Days with no spend may be absent.
 */
fun cumulativeSpendSeries(
    dailyTotals: Map<String, Long>,
    startIso: String,
    endIso: String,
    todayIso: String,
): List<SpendPoint> {
    // An unparseable date is a caller bug, not something to crash a card over,
    // and the Swift port returns nil from its own parse rather than throwing --
    // so the difference has to be spelled out here or the two platforms
    // disagree on the same input. A golden vector pins the pair.
    val start = parseDayOrNull(startIso) ?: return emptyList()
    val end = parseDayOrNull(endIso) ?: return emptyList()
    val today = parseDayOrNull(todayIso) ?: return emptyList()

    val lastDay = if (end.isBefore(today)) end else today
    val spanDays = max(1L, ChronoUnit.DAYS.between(start, lastDay) + 1).toInt()
    val step = if (spanDays > 92) 7 else 1

    val out = mutableListOf<SpendPoint>()
    var cumulative = 0L
    for (i in 0 until spanDays) {
        val day = start.plusDays(i.toLong())
        if (day.isAfter(today)) break
        val key = day.toString()
        cumulative += dailyTotals[key] ?: 0L
        if (i % step == 0 || i == spanDays - 1) out += SpendPoint(key, cumulative)
    }
    return out
}

private fun parseDayOrNull(iso: String): LocalDate? =
    runCatching { LocalDate.parse(iso.take(10)) }.getOrNull()
