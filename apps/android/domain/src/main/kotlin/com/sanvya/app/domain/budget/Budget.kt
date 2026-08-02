package com.sanvya.app.domain.budget

import com.sanvya.app.domain.finance.daysInMonth
import com.sanvya.app.domain.money.Money
import com.sanvya.app.domain.money.subtract
import java.time.LocalDate
import kotlin.math.min

// Ported from packages/core/budget/src/index.ts (P1.3a). Correctness is
// judged against tools/golden-vectors/vectors/budget.json -- see
// docs/plans/native-mobile-apps.md section 5 and CLAUDE.md golden rule 8
// ("web is the spec"). All date logic is UTC calendar-day arithmetic;
// dates are represented as java.time.LocalDate (no time-of-day, no
// timezone -- matches the TS source's own `Date.UTC`-only usage, which
// never touches a real timezone or wall-clock time either). Weeks start
// Monday (ISO), matching the TS source's comment.

/** Half-open date window [start, endExclusive). */
data class DateWindow(val start: LocalDate, val endExclusive: LocalDate)

/**
 * The budget period window that `date` falls into (UTC, Monday-based weeks).
 * `date` is a LocalDate (already truncated to a calendar day by the caller /
 * adapter, mirroring the TS source's own `utcMidnight` truncation of its
 * `Date` input).
 */
fun periodBounds(period: String, date: LocalDate): DateWindow {
    return when (period) {
        "daily" -> DateWindow(date, date.plusDays(1))
        "weekly" -> {
            // java.time.DayOfWeek.value is 1=Monday..7=Sunday (ISO). The TS
            // source works in JS's 0=Sunday..6=Saturday and computes
            // backToMonday = (dow + 6) % 7. Converting ISO's value to JS's
            // convention (dow = value % 7, since ISO Sunday=7 -> 7%7=0)
            // keeps the arithmetic identical to the TS source rather than
            // re-deriving a different-but-equivalent formula for ISO
            // weekdays, which would be a second place this logic could
            // silently diverge.
            val dowJs = date.dayOfWeek.value % 7
            val backToMonday = (dowJs + 6) % 7
            val start = date.minusDays(backToMonday.toLong())
            DateWindow(start, start.plusDays(7))
        }
        "monthly" -> {
            val start = LocalDate.of(date.year, date.monthValue, 1)
            DateWindow(start, start.plusMonths(1))
        }
        "yearly" -> {
            val start = LocalDate.of(date.year, 1, 1)
            DateWindow(start, LocalDate.of(date.year + 1, 1, 1))
        }
        else -> error("unknown period: $period")
    }
}

data class BudgetProgress(
    val pct: Double,
    val remaining: Money,
    val atOrOverThreshold: Boolean,
    val overLimit: Boolean,
)

/**
 * Progress of `spent` against a budget `limit`, flagging threshold/limit
 * breaches. pct is Double.POSITIVE_INFINITY when limit is 0 (mirrors JS
 * Infinity, serialized as JSON null -- see Vectors.kt's jsonNumber()).
 */
fun budgetProgress(limit: Money, spent: Money, thresholdPct: Double): BudgetProgress {
    require(limit.currency == spent.currency) { "budgetProgress: limit and spent must share a currency" }
    val pct = if (limit.amount == 0L) Double.POSITIVE_INFINITY else (spent.amount.toDouble() / limit.amount) * 100
    return BudgetProgress(
        pct = pct,
        remaining = subtract(limit, spent),
        atOrOverThreshold = pct >= thresholdPct,
        overLimit = spent.amount > limit.amount,
    )
}

/**
 * True when spend crosses the threshold on THIS update (was below, now
 * at/above) -- the edge to fire a single notification on. Idempotent: no
 * repeat alerts while already over.
 */
fun crossedThreshold(previousSpent: Money, newSpent: Money, limit: Money, thresholdPct: Double): Boolean {
    val thresholdAmount = (limit.amount * thresholdPct) / 100
    return previousSpent.amount < thresholdAmount && newSpent.amount >= thresholdAmount
}

// ---------------- Credit-card billing cycle ----------------

private fun clampDay(year: Int, monthIndex: Int, day: Int): LocalDate {
    // monthIndex is 0-based and may be out of [0,11] (mirrors the TS
    // source's Date.UTC month-overflow normalization).
    val totalMonths = year * 12 + monthIndex
    val ny = Math.floorDiv(totalMonths, 12)
    val nm0 = Math.floorMod(totalMonths, 12)
    val lastDay = daysInMonth(ny, nm0)
    return LocalDate.of(ny, nm0 + 1, min(day, lastDay))
}

private fun mostRecentDayOnOrBefore(asOf: LocalDate, day: Int): LocalDate {
    val cand = clampDay(asOf.year, asOf.monthValue - 1, day)
    if (!cand.isAfter(asOf)) return cand
    return clampDay(asOf.year, asOf.monthValue - 1 - 1, day)
}

private fun nextDayStrictlyAfter(from: LocalDate, day: Int): LocalDate {
    val cand = clampDay(from.year, from.monthValue - 1, day)
    if (cand.isAfter(from)) return cand
    return clampDay(from.year, from.monthValue - 1 + 1, day)
}

data class BillingCycle(val cycleStart: LocalDate, val statementDate: LocalDate, val dueDate: LocalDate)

/**
 * The currently-open billing cycle for a card. Charges made now belong to
 * this cycle; it closes on statementDate and is due on dueDate. Handles
 * months shorter than the chosen day (e.g. a 31st statement day in Feb).
 */
fun billingCycle(statementDay: Int, dueDay: Int, asOf: LocalDate): BillingCycle {
    val previousStatement = mostRecentDayOnOrBefore(asOf, statementDay)
    val cycleStart = previousStatement.plusDays(1)
    val statementDate = nextDayStrictlyAfter(previousStatement, statementDay)
    val dueDate = nextDayStrictlyAfter(statementDate, dueDay)
    return BillingCycle(cycleStart, statementDate, dueDate)
}
