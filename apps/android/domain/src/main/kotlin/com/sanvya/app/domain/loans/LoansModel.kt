package com.sanvya.app.domain.loans

import java.time.LocalDate
import java.time.YearMonth

/**
 * Loans/EMI domain model (pure, UI-agnostic) -- Kotlin port of
 * `packages/core/finance/src/index.ts`'s `emiFromPrincipal`/
 * `amortizationSchedule`/`emiDueDate`/`effectivePaidEmis`, read in full
 * 2026-08-06 for task #27. All money values are integer minor units;
 * every intermediate is rounded half-away-from-zero (`Math.round` in the
 * TS source), matching `kotlin.math.roundToLong()`'s own half-up
 * behavior for the always-non-negative values these functions handle.
 */

/**
 * Standard reducing-balance EMI for a fixed-rate loan (minor-unit integer).
 *   EMI = P*r*(1+r)^n / ((1+r)^n - 1),  r = monthly rate, n = tenure in months.
 * A 0% (or missing) rate gives the flat P/n. Returns 0 for a non-positive tenure.
 */
fun emiFromPrincipal(principal: Long, annualRatePct: Double, tenureMonths: Int): Long {
    val p = maxOf(0L, Math.round(principal.toDouble()))
    val n = maxOf(0, tenureMonths)
    if (p <= 0 || n <= 0) return 0L
    val r = annualRatePct / 100.0 / 12.0
    if (r <= 0) return Math.round(p.toDouble() / n)
    val pow = Math.pow(1 + r, n.toDouble())
    return Math.round((p * r * pow) / (pow - 1))
}

data class AmortRow(
    /** 1-based EMI number. */
    val month: Int,
    /** EMI actually paid this month (equals `emi`, except a smaller final payment). */
    val emi: Long,
    /** Interest portion of this EMI. */
    val interest: Long,
    /** Principal portion of this EMI. */
    val principal: Long,
    /** Outstanding principal after this EMI. */
    val balance: Long,
)

/**
 * Reducing-balance amortization schedule. Each month, interest = balance x
 * monthly rate, and the rest of the EMI reduces principal. A 0% rate gives
 * a flat principal-only schedule. Stops at [maxMonths] (the tenure) or
 * when the balance hits zero; returns an empty list if the EMI can't even
 * cover the first month's interest (i.e. the loan would never amortize).
 */
fun amortizationSchedule(principal: Long, annualRatePct: Double, emi: Long, maxMonths: Int): List<AmortRow> {
    val rows = mutableListOf<AmortRow>()
    val r = annualRatePct / 100.0 / 12.0
    var balance = maxOf(0L, Math.round(principal.toDouble()))
    val emiRounded = Math.round(emi.toDouble())
    val cap = minOf(maxOf(0, maxMonths).let { if (it == 0) 1200 else it }, 1200)

    var m = 1
    while (m <= cap && balance > 0) {
        val interest = Math.round(balance * r)
        var principalPaid = emiRounded - interest
        if (principalPaid <= 0) break // EMI doesn't cover interest -> never amortizes
        var pay = emiRounded
        if (principalPaid >= balance) {
            principalPaid = balance // final (partial) payment
            pay = balance + interest
        }
        balance -= principalPaid
        rows.add(AmortRow(month = m, emi = pay, interest = interest, principal = principalPaid, balance = balance))
        m++
    }
    return rows
}

/** Days in a given month (1-based month). */
private fun daysInMonth(y: Int, m1based: Int): Int = YearMonth.of(y, m1based).lengthOfMonth()

/** Build a YYYY-MM-DD for (y, m 0-based, day) clamping day to the month length --
 * matches the TS source's `isoOf`'s month-overflow normalization exactly
 * (m can be < 0 or > 11 on input; LocalDate.of(y, 1, 1).plusMonths(m) folds it). */
private fun isoOf(y: Int, m0based: Int, day: Int): String {
    val base = LocalDate.of(y, 1, 1).plusMonths(m0based.toLong())
    val clamped = minOf(day, daysInMonth(base.year, base.monthValue))
    return LocalDate.of(base.year, base.monthValue, clamped).toString()
}

private data class Ymd(val y: Int, val m0: Int, val d: Int)

/** Parse a YYYY-MM-DD (or ISO) string into y/m(0-based)/d, or null. */
private fun ymd(iso: String?): Ymd? {
    if (iso.isNullOrBlank()) return null
    val s = iso.take(10)
    val match = Regex("""^(\d{4})-(\d{2})-(\d{2})$""").find(s) ?: return null
    val (ys, ms, ds) = match.destructured
    val y = ys.toInt(); val m = ms.toInt() - 1; val d = ds.toInt()
    if (m < 0 || m > 11 || d < 1 || d > 31) return null
    return Ymd(y, m, d)
}

/**
 * Due date (YYYY-MM-DD) of EMI number [emiNo] (1-based).
 *
 * [startIso] is when the loan started. [dueDay] (1-31) is the day of the
 * month each EMI falls on; if null, the start date's own day-of-month is
 * used. The FIRST EMI is the first occurrence of [dueDay] strictly on/after
 * the start date, and each subsequent EMI is one calendar month later (day
 * clamped to the month, e.g. a 31 due-day lands on Feb 28/29).
 */
fun emiDueDate(startIso: String?, dueDay: Int?, emiNo: Int): String? {
    val start = ymd(startIso) ?: return null
    val day = if (dueDay != null && dueDay in 1..31) dueDay else start.d
    val firstMonthOffset = if (day < start.d) 1 else 0
    val n = maxOf(1, emiNo)
    return isoOf(start.y, start.m0 + firstMonthOffset + (n - 1), day)
}

/** True if [dueIso] is on or before [asOfIso] (both YYYY-MM-DD, lexical compare). */
fun isDuePassed(dueIso: String?, asOfIso: String): Boolean {
    if (dueIso.isNullOrBlank()) return false
    return dueIso <= asOfIso.take(10)
}

/**
 * The set of EMI numbers that count as paid, given manually-marked EMIs
 * and an optional "auto-mark past-due" policy. Derived (not persisted) so
 * toggling auto-mark off instantly reverts the auto ones; manual marks
 * always win.
 */
fun effectivePaidEmis(
    manual: Iterable<Int>,
    totalEmis: Int,
    autoMark: Boolean = false,
    startIso: String? = null,
    dueDay: Int? = null,
    asOfIso: String = LocalDate.now().toString(),
): Set<Int> {
    val out = mutableSetOf<Int>()
    for (m in manual) out.add(m)
    val total = maxOf(0, totalEmis)
    if (autoMark && total > 0) {
        for (n in 1..total) {
            val due = emiDueDate(startIso, dueDay, n)
            if (isDuePassed(due, asOfIso)) out.add(n)
        }
    }
    return out
}
