package com.sanvya.app.domain.dashboard

import java.time.LocalDate

/** How far back the Expense-trends tile looks. Web's `TrendPeriod`. */
enum class TrendPeriod(val key: String) {
    THREE_DAYS("3d"),
    ONE_WEEK("1w"),
    ONE_MONTH("1m"),
    ONE_YEAR("1y");

    companion object {
        fun from(key: String?): TrendPeriod = entries.firstOrNull { it.key == key } ?: ONE_MONTH
    }
}

/**
 * One bucket: the date it starts on, and what was spent in it.
 *
 * The START DATE, not a label. Web's `buildTrend` returns `"12 Aug"` built from
 * a hardcoded English month array; formatting a date is the view's job on a
 * platform that has a locale, and returning the label here would have shipped
 * English into two otherwise localised apps.
 */
data class TrendBucket(val startIso: String, val totalMinor: Long)

/**
 * Buckets daily expense totals into period-appropriate buckets.
 *
 * A port of web's `buildTrend`, with `today` passed in rather than read from the
 * clock — which is what makes it testable, and is why there are vectors for it.
 *
 * The bucket shapes are web's, exactly:
 * - 3d / 1w: one bucket per day, oldest first.
 * - 1m: FOUR buckets of seven days each, and web's windows **overlap by a day**
 *   (`start = today - (w*7 + 6)`, `end = today - w*7`, inclusive both ends). A
 *   day that is a boundary is counted in two buckets. That is web's arithmetic
 *   and it is preserved deliberately: correcting it here alone would make the
 *   same month read differently in the browser and on the phone.
 * - 1y: twelve calendar months, oldest first.
 *
 * @param dailyTotals `YYYY-MM-DD` to minor units, as the query returns them.
 */
fun buildTrend(
    dailyTotals: Map<String, Long>,
    period: TrendPeriod,
    todayIso: String,
): List<TrendBucket> {
    // An unparseable `today` is a caller bug, not something to crash a tile
    // over: Swift's `buildTrend` guards its date parse and returns empty, and a
    // golden vector pins the pair. `LocalDate.parse` throws where Swift returns
    // nil, so the difference has to be spelled out here or the two platforms
    // disagree on the same input -- which is exactly what the vector caught.
    val today = runCatching { LocalDate.parse(todayIso) }.getOrNull() ?: return emptyList()
    return when (period) {
        TrendPeriod.THREE_DAYS, TrendPeriod.ONE_WEEK -> {
            val n = if (period == TrendPeriod.THREE_DAYS) 3 else 7
            (n - 1 downTo 0).map { i ->
                val day = today.minusDays(i.toLong())
                TrendBucket(day.toString(), dailyTotals[day.toString()] ?: 0L)
            }
        }
        TrendPeriod.ONE_MONTH -> (3 downTo 0).map { w ->
            val start = today.minusDays((w * 7 + 6).toLong())
            val end = today.minusDays((w * 7).toLong())
            // String comparison, not LocalDate: the keys are zero-padded ISO
            // dates, so lexical order IS chronological order and there is
            // nothing to parse per row.
            val startKey = start.toString()
            val endKey = end.toString()
            val sum = dailyTotals.entries.sumOf { (key, value) ->
                if (key >= startKey && key <= endKey) value else 0L
            }
            TrendBucket(start.toString(), sum)
        }
        TrendPeriod.ONE_YEAR -> (11 downTo 0).map { m ->
            val first = today.withDayOfMonth(1).minusMonths(m.toLong())
            val prefix = "%04d-%02d".format(first.year, first.monthValue)
            val sum = dailyTotals.entries.sumOf { (key, value) ->
                if (key.startsWith(prefix)) value else 0L
            }
            TrendBucket(first.toString(), sum)
        }
    }
}

/** One month of the cashflow series. */
data class CashflowMonth(
    /** `YYYY-MM`. */
    val month: String,
    val incomeMinor: Long,
    val expenseMinor: Long,
) {
    val netMinor: Long get() = incomeMinor - expenseMinor
}

/**
 * Folds `(yearMonth, type, total)` rows into one entry per month.
 *
 * Web's `useCashflow`, including the trailing-eight window. Rows arrive sorted
 * by month from the query, and the fold preserves that order rather than
 * re-sorting, so a month with only income and a month with only expense stay
 * where the query put them.
 */
fun monthlyCashflow(rows: List<Triple<String, String, Long>>, months: Int = 8): List<CashflowMonth> {
    val byMonth = LinkedHashMap<String, CashflowMonth>()
    for ((yearMonth, type, total) in rows) {
        val current = byMonth[yearMonth] ?: CashflowMonth(yearMonth, 0, 0)
        byMonth[yearMonth] = when (type) {
            "income" -> current.copy(incomeMinor = total)
            else -> current.copy(expenseMinor = total)
        }
    }
    return byMonth.values.toList().takeLast(months)
}
