package care.pocket.domain.finance

import java.time.LocalDate
import kotlin.math.ceil
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToLong

// Ported from packages/core/finance/src/index.ts (P1.3a). Correctness is
// judged against tools/golden-vectors/vectors/finance.json, not against a
// fresh reading of the TS -- see docs/plans/native-mobile-apps.md section 5
// and CLAUDE.md golden rule 8 ("web is the spec"). Pure financial math, no
// I/O: amounts are minor-unit Longs in and rounded minor-unit Longs out
// (Math.round in JS -- ties round toward +Infinity, NOT away from zero like
// Money.kt's rounding; kotlin.math.roundToLong matches that exactly, so no
// custom rounding helper is needed here the way Money.kt needed one).

/** How many times each budgeting/commitment period occurs per year. */
val PERIODS_PER_YEAR: Map<String, Int> = mapOf(
    "daily" to 365,
    "weekly" to 52,
    "monthly" to 12,
    "yearly" to 1,
)

/**
 * Future value of a starting principal plus a recurring contribution made
 * every period, compounded at periodicRate. Returns a rounded minor-unit Long.
 */
fun futureValue(principal: Long, contribution: Long, periodicRate: Double, periods: Int): Long {
    require(periods >= 0) { "periods must be >= 0" }
    val fv: Double = if (periodicRate == 0.0) {
        principal + contribution.toDouble() * periods
    } else {
        val growth = (1 + periodicRate).pow(periods)
        principal * growth + contribution * ((growth - 1) / periodicRate)
    }
    return fv.roundToLong()
}

/** Convert an annual percentage rate (e.g. 8 for 8%) to a per-period decimal. */
fun periodicRateFromAnnual(annualPct: Double, period: String): Double =
    annualPct / 100 / (PERIODS_PER_YEAR.getValue(period))

/**
 * Number of whole periods until `current` grows to `target`. Returns
 * Double.POSITIVE_INFINITY if the goal can never be reached (mirrors the TS
 * source returning JS's Infinity, which JSON.stringify writes as `null`).
 */
fun periodsToGoal(current: Long, target: Long, contribution: Long, periodicRate: Double): Double {
    if (current >= target) return 0.0
    if (periodicRate == 0.0) {
        if (contribution <= 0) return Double.POSITIVE_INFINITY
        return ceil((target - current).toDouble() / contribution)
    }
    val numerator = target * periodicRate + contribution
    val denominator = current * periodicRate + contribution
    if (denominator <= 0 || numerator <= 0) return Double.POSITIVE_INFINITY
    val n = ln(numerator / denominator) / ln(1 + periodicRate)
    if (!n.isFinite() || n < 0) return Double.POSITIVE_INFINITY
    return ceil(n)
}

/** Normalize any period amount to its monthly equivalent (rounded minor units). */
fun monthlyEquivalent(amount: Long, period: String): Long {
    val perYear = PERIODS_PER_YEAR.getValue(period)
    return (amount.toDouble() * perYear / 12).roundToLong()
}

data class RecurringLike(val amount: Long, val frequency: String)

/** Total monthly cost of a set of recurring commitments (EMIs, subs, expenses). */
fun recurringMonthlyTotal(items: List<RecurringLike>): Long =
    items.fold(0L) { acc, it -> acc + monthlyEquivalent(it.amount, it.frequency) }

/**
 * What percentage of monthly income the given monthly amount represents.
 * Double.POSITIVE_INFINITY when monthlyIncome <= 0 (mirrors JS Infinity).
 */
fun percentOfIncome(monthlyAmount: Long, monthlyIncome: Long): Double {
    if (monthlyIncome <= 0) return Double.POSITIVE_INFINITY
    return (monthlyAmount.toDouble() / monthlyIncome) * 100
}

data class SubscriptionImpact(val totalPaid: Long, val opportunityCost: Long)

/**
 * Project the impact of a subscription over `years`, assuming the money
 * could otherwise be invested at annualReturnPct. Contributions modelled
 * monthly.
 */
fun subscriptionImpact(amount: Long, frequency: String, years: Double, annualReturnPct: Double): SubscriptionImpact {
    val monthly = monthlyEquivalent(amount, frequency)
    val months = (years * 12).roundToLong().toInt()
    val totalPaid = monthly * months
    val r = annualReturnPct / 100 / 12
    // 0L, not 0 -- Kotlin does not implicitly widen an Int literal to the
    // Long parameter here (unlike Java); verified via search rather than
    // assumed, since this exact class of mistake was a real Swift build
    // error earlier in this session (see Money.swift's sum()).
    val invested = futureValue(0L, monthly, r, months)
    return SubscriptionImpact(totalPaid, invested)
}

data class CashflowInputs(
    val monthlyIncome: Long,
    val monthlyPayments: Long,
    val monthlySavings: Long,
    val currentSavings: Long,
    val annualReturnPct: Double,
    val annualInflationPct: Double,
    val incomeGrowthPct: Double = 0.0,
)

data class YearProjection(
    val year: Int,
    val income: Long,
    val payments: Long,
    val savingsContributed: Long,
    val netCashflow: Long,
    val savingsBalance: Long,
    val realSavingsBalance: Long,
)

/**
 * Project year-by-year cashflow and savings growth over `years`. Income and
 * payments step up once per year; savings compound monthly at the annual
 * return and receive the monthly contribution.
 */
fun projectCashflow(inp: CashflowInputs, years: Int): List<YearProjection> {
    require(years >= 0) { "years must be >= 0" }
    val monthlyReturn = inp.annualReturnPct / 100 / 12
    val inflation = inp.annualInflationPct / 100
    val incomeGrowth = inp.incomeGrowthPct / 100

    var savings = inp.currentSavings.toDouble()
    val out = mutableListOf<YearProjection>()

    for (y in 1..years) {
        val growthFactor = (1 + incomeGrowth).pow(y - 1)
        val inflationFactor = (1 + inflation).pow(y - 1)
        val income = (inp.monthlyIncome * growthFactor).roundToLong()
        val payments = (inp.monthlyPayments * inflationFactor).roundToLong()
        val contribution = (inp.monthlySavings * inflationFactor).roundToLong()

        var yearIncome = 0L
        var yearPayments = 0L
        var yearContrib = 0L
        for (m in 0 until 12) {
            yearIncome += income
            yearPayments += payments
            yearContrib += contribution
            savings = savings * (1 + monthlyReturn) + contribution
        }
        val realDeflator = (1 + inflation).pow(y)
        out.add(
            YearProjection(
                year = y,
                income = yearIncome,
                payments = yearPayments,
                savingsContributed = yearContrib,
                netCashflow = yearIncome - yearPayments - yearContrib,
                savingsBalance = savings.roundToLong(),
                realSavingsBalance = (savings / realDeflator).roundToLong(),
            )
        )
    }
    return out
}

/** Convert an amount from any period to its yearly equivalent (rounded minor units). */
fun yearlyEquivalent(amount: Long, period: String): Long =
    (amount.toDouble() * PERIODS_PER_YEAR.getValue(period)).roundToLong()

data class AmortRow(val month: Int, val emi: Long, val interest: Long, val principal: Long, val balance: Long)

/**
 * Standard reducing-balance EMI for a fixed-rate loan (minor-unit Long).
 * A 0% (or missing) rate gives the flat P/n. Returns 0 for a non-positive tenure.
 */
fun emiFromPrincipal(principal: Long, annualRatePct: Double, tenureMonths: Int): Long {
    val p = max(0L, principal)
    val n = max(0, tenureMonths)
    if (p <= 0 || n <= 0) return 0L
    val r = annualRatePct / 100 / 12
    if (r <= 0) return (p.toDouble() / n).roundToLong()
    val pow = (1 + r).pow(n)
    return (p * r * pow / (pow - 1)).roundToLong()
}

/**
 * Reducing-balance amortization schedule. Stops at maxMonths (capped 1200,
 * matching the TS source) or when the balance hits zero; returns an empty
 * list if the EMI can't even cover the first month's interest.
 */
fun amortizationSchedule(principal: Long, annualRatePct: Double, emi: Long, maxMonths: Int): List<AmortRow> {
    val rows = mutableListOf<AmortRow>()
    val r = annualRatePct / 100 / 12
    var balance = max(0L, principal)
    val emiRounded = emi
    val cap = min(if (maxMonths > 0) maxMonths else 1200, 1200)

    var m = 1
    while (m <= cap && balance > 0) {
        val interest = (balance * r).roundToLong()
        var principalPaid = emiRounded - interest
        if (principalPaid <= 0) break
        var pay = emiRounded
        if (principalPaid >= balance) {
            principalPaid = balance
            pay = balance + interest
        }
        balance -= principalPaid
        rows.add(AmortRow(m, pay, interest, principalPaid, balance))
        m++
    }
    return rows
}

/** Convert a monthly minor-unit amount to a given timeframe bucket total. */
fun timeframeTotal(monthlyAmount: Long, timeframe: String): Long {
    val mult = when (timeframe) {
        "monthly" -> 1
        "quarterly" -> 3
        else -> 12
    }
    return monthlyAmount * mult
}

// --- Loan EMI scheduling ----------------------------------------------------
// Pure calendar-date math for "which EMI is due when". Transliterated
// directly from the TS source's own (y, month0, day) arithmetic rather than
// leaning on java.time's higher-level plusMonths()/Calendar semantics --
// java.time.LocalDate is used only as a days-in-month oracle, never for
// "add N months" style operations, so behavior can't silently diverge from
// the TS source's hand-rolled clamping. See Budget.kt for the sibling
// billingCycle/periodBounds functions built the same way.

private data class Ymd(val y: Int, val m: Int, val d: Int) // m is 0-based, like the TS source

private fun parseYmd(iso: String?): Ymd? {
    if (iso == null) return null
    val s = iso.take(10)
    val match = Regex("^(\\d{4})-(\\d{2})-(\\d{2})$").find(s) ?: return null
    val y = match.groupValues[1].toInt()
    val m = match.groupValues[2].toInt() - 1
    val d = match.groupValues[3].toInt()
    if (m < 0 || m > 11 || d < 1 || d > 31) return null
    return Ymd(y, m, d)
}

/** Days in month `m0` (0-based) of year `y`, normalizing month overflow like Date.UTC. */
internal fun daysInMonth(y: Int, m0: Int): Int {
    val totalMonths = y * 12 + m0
    val ny = Math.floorDiv(totalMonths, 12)
    val nm0 = Math.floorMod(totalMonths, 12)
    return LocalDate.of(ny, nm0 + 1, 1).lengthOfMonth()
}

/** Build YYYY-MM-DD for (y, m0, day), normalizing month overflow and clamping day to the month length. */
private fun isoOf(y: Int, m0: Int, day: Int): String {
    val totalMonths = y * 12 + m0
    val ny = Math.floorDiv(totalMonths, 12)
    val nm0 = Math.floorMod(totalMonths, 12)
    val clamped = min(day, daysInMonth(ny, nm0))
    // Locale.ROOT explicitly -- %d is digit-only so most locales wouldn't
    // matter, but this avoids ever trusting the JVM default locale for a
    // value that becomes a byte-for-byte-compared vector string.
    return String.format(java.util.Locale.ROOT, "%04d-%02d-%02d", ny, nm0 + 1, clamped)
}

/**
 * Due date (YYYY-MM-DD) of EMI number `emiNo` (1-based). The FIRST EMI is
 * the first occurrence of `dueDay` strictly on/after the start date; each
 * subsequent EMI is one calendar month later (day clamped to the month).
 */
fun emiDueDate(startIso: String?, dueDay: Int?, emiNo: Int): String? {
    val start = parseYmd(startIso) ?: return null
    val day = if (dueDay != null && dueDay in 1..31) dueDay else start.d
    var firstMonthOffset = 0
    if (day < start.d) firstMonthOffset = 1
    val n = max(1, emiNo)
    return isoOf(start.y, start.m + firstMonthOffset + (n - 1), day)
}

/** True if `dueIso` is on or before `asOfIso` (both YYYY-MM-DD, lexicographic == chronological). */
fun isDuePassed(dueIso: String?, asOfIso: String): Boolean {
    if (dueIso == null) return false
    return dueIso <= asOfIso.take(10)
}

/**
 * The set of EMI numbers that count as paid: manually-marked EMIs, plus
 * (when autoMark is on) every EMI whose due date has passed. Derived, not
 * persisted.
 */
fun effectivePaidEmis(
    manual: Iterable<Int>,
    totalEmis: Int,
    autoMark: Boolean = false,
    startIso: String? = null,
    dueDay: Int? = null,
    asOfIso: String,
): Set<Int> {
    val out = mutableSetOf<Int>()
    out.addAll(manual)
    val total = max(0, totalEmis)
    if (autoMark && total > 0) {
        val asOf = asOfIso.take(10)
        for (n in 1..total) {
            val due = emiDueDate(startIso, dueDay, n)
            if (isDuePassed(due, asOf)) out.add(n)
        }
    }
    return out
}
