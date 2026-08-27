package com.sanvya.app.domain.statements

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

/**
 * Pure statement analytics — no I/O, no formatting.
 *
 * Ported from `apps/web/src/statements/analysis.ts`. Amounts are signed minor
 * units (− debit / + credit) and everything here is deterministic, which is
 * what makes it vector-pinnable rather than "looks about right on my
 * statement".
 */

data class StatementSummary(
    val count: Int,
    /** Total money in (minor, positive). */
    val credits: Long,
    /** Total money out (minor, positive). */
    val debits: Long,
    /** credits − debits. */
    val net: Long,
    val from: String?,
    val to: String?,
)

fun summarize(txns: List<StatementTxn>): StatementSummary {
    var credits = 0L
    var debits = 0L
    var from: String? = null
    var to: String? = null
    for (t in txns) {
        if (t.amount >= 0) credits += t.amount else debits += -t.amount
        if (t.date.isNotEmpty()) {
            if (from == null || t.date < from!!) from = t.date
            if (to == null || t.date > to!!) to = t.date
        }
    }
    return StatementSummary(txns.size, credits, debits, credits - debits, from, to)
}

data class CategoryTotal(val name: String, val total: Long, val count: Int)

/** Spend (debits) grouped by category label, largest first. */
fun byCategory(txns: List<StatementTxn>): List<CategoryTotal> {
    val m = LinkedHashMap<String, CategoryTotal>()
    for (t in txns) {
        if (t.amount >= 0) continue // only spends
        val key = t.category?.trim()?.takeIf { it.isNotEmpty() } ?: UNCATEGORISED
        val e = m[key]
        m[key] = CategoryTotal(key, (e?.total ?: 0L) + -t.amount, (e?.count ?: 0) + 1)
    }
    // sortedByDescending is STABLE in Kotlin and Array.prototype.sort is stable
    // in every engine web targets, so ties keep first-seen order on both.
    return m.values.sortedByDescending { it.total }
}

data class MonthTotal(val ym: String, val debit: Long, val credit: Long)

/** Debits and credits bucketed by calendar month (YYYY-MM), chronological. */
fun byMonth(txns: List<StatementTxn>): List<MonthTotal> {
    val m = LinkedHashMap<String, MonthTotal>()
    for (t in txns) {
        if (t.date.isEmpty()) continue
        val ym = t.date.take(7)
        val e = m[ym] ?: MonthTotal(ym, 0L, 0L)
        m[ym] = if (t.amount >= 0) e.copy(credit = e.credit + t.amount) else e.copy(debit = e.debit + -t.amount)
    }
    return m.values.sortedBy { it.ym }
}

data class DayTotal(val date: String, val debit: Long)

/** Daily spend series over the statement window, chronological. */
fun byDay(txns: List<StatementTxn>): List<DayTotal> {
    val m = LinkedHashMap<String, Long>()
    for (t in txns) {
        if (t.amount < 0 && t.date.isNotEmpty()) m[t.date] = (m[t.date] ?: 0L) + -t.amount
    }
    return m.entries.map { DayTotal(it.key, it.value) }.sortedBy { it.date }
}

data class StatementOutlier(val txn: StatementTxn, val amount: Long, val reason: String)

/**
 * Flag unusually large spends using the IQR fence (> Q3 + 1.5·IQR) over the
 * debit magnitudes, falling back to "> 3× median" for very small samples.
 *
 * The fallback is not a shortcut: quartiles over three points are noise, and a
 * three-line statement with one big spend still deserves the flag.
 */
fun outliers(txns: List<StatementTxn>): List<StatementOutlier> {
    val debits = txns.filter { it.amount < 0 }
    val mags = debits.map { -it.amount }.sorted()
    if (mags.size < 4) {
        if (mags.isEmpty()) return emptyList()
        val median = mags[mags.size / 2]
        val thr = median * 3
        // Web's `-t.amount > 0` is redundant next to `amount < 0` above, but it
        // is kept so the two implementations read the same.
        return debits.filter { -it.amount > thr && -it.amount > 0 }
            .map { StatementOutlier(it, -it.amount, REASON_SMALL_SAMPLE) }
    }
    fun q(p: Double): Double {
        val idx = (mags.size - 1) * p
        val lo = floor(idx).toInt()
        val hi = ceil(idx).toInt()
        return mags[lo] + (mags[hi] - mags[lo]) * (idx - lo)
    }
    val q1 = q(0.25)
    val q3 = q(0.75)
    val fence = q3 + 1.5 * (q3 - q1)
    return debits.filter { -it.amount > fence }
        .map { StatementOutlier(it, -it.amount, REASON_IQR) }
        .sortedByDescending { it.amount }
}

/**
 * Normalise a merchant/narration for grouping: drop refs, digits, banking noise.
 *
 * The ORDER of the replacements is load-bearing. Long digit runs go first,
 * because a card tail glued to a merchant name ("SWIGGY1234") would otherwise
 * survive the word-boundary pass and split one merchant into many.
 */
fun normalizeMerchant(desc: String): String = desc
    .lowercase()
    .replace(Regex("[0-9]{4,}"), " ")
    .replace(
        Regex("\\b(upi|imps|neft|rtgs|ach|nach|pos|atw|vps|mmt|inb|ref|txn|trf|payment|paytm|gpay|phonepe)\\b"),
        " ",
    )
    .replace(Regex("[^a-z ]+"), " ")
    .replace(Regex("\\s+"), " ")
    .trim()
    .split(" ").take(3).joinToString(" ")

data class RecurringCandidate(
    /** Representative description — the most recent one. */
    val label: String,
    /** Normalised merchant. */
    val key: String,
    /** Typical debit magnitude (minor). */
    val amount: Long,
    val count: Int,
    /** "weekly" | "monthly" | "yearly" | "irregular". */
    val cadence: String,
    val sample: List<StatementTxn>,
)

/**
 * Detect likely recurring debits: same merchant, similar amount (±12%), seen
 * at least twice with a regular gap. Powers "add as a recurring payment".
 */
fun recurringCandidates(txns: List<StatementTxn>): List<RecurringCandidate> {
    val groups = LinkedHashMap<String, MutableList<StatementTxn>>()
    for (t in txns) {
        if (t.amount >= 0) continue
        val key = normalizeMerchant(t.description)
        if (key.isEmpty()) continue
        groups.getOrPut(key) { mutableListOf() }.add(t)
    }
    val out = mutableListOf<RecurringCandidate>()
    for ((key, list) in groups) {
        if (list.size < 2) continue
        val sorted = list.sortedBy { it.date }
        val mags = sorted.map { -it.amount }
        val median = mags.sorted()[mags.size / 2]
        // Amounts must cluster: each within ±12% of the median.
        if (!mags.all { abs(it - median) <= median * 0.12 }) continue
        val gaps = mutableListOf<Double>()
        for (i in 1 until sorted.size) {
            val d0 = isoDaysOrNull(sorted[i - 1].date)
            val d1 = isoDaysOrNull(sorted[i].date)
            if (d0 != null && d1 != null) gaps.add((d1 - d0).toDouble())
        }
        val avgGap = if (gaps.isEmpty()) 0.0 else gaps.sum() / gaps.size
        val cadence = when {
            avgGap in 5.0..10.0 -> "weekly"
            avgGap in 25.0..35.0 -> "monthly"
            avgGap in 350.0..380.0 -> "yearly"
            else -> "irregular"
        }
        out.add(
            RecurringCandidate(
                label = sorted.last().description,
                key = key,
                amount = median,
                count = sorted.size,
                cadence = cadence,
                sample = sorted,
            ),
        )
    }
    // Prefer regular cadences, then more occurrences. Two comparators, in that
    // order, exactly as web's `||`-chained sort does.
    return out.sortedWith(
        compareBy<RecurringCandidate> { if (it.cadence == "irregular") 1 else 0 }
            .thenByDescending { it.count },
    )
}

/**
 * Days since the epoch for an ISO `YYYY-MM-DD`, or null when it will not parse.
 *
 * Hand-rolled (Hinnant's days_from_civil) rather than java.time, so the answer
 * is identical to Swift's and neither can drift with a platform's calendar
 * handling. Web uses `Date.parse(d + "T00:00:00")`, which is LOCAL time — but
 * only ever as a difference between two such values, so the offset cancels and
 * the gap in days is the same everywhere. The one case that would NOT cancel is
 * a DST boundary between the two dates; web's own arithmetic has that rounding
 * wobble and the cadence buckets are wide enough (5–10, 25–35, 350–380) that it
 * cannot change an answer.
 */
internal fun isoDaysOrNull(iso: String): Long? {
    if (iso.length < 10) return null
    val y = iso.substring(0, 4).toIntOrNull() ?: return null
    val m = iso.substring(5, 7).toIntOrNull() ?: return null
    val d = iso.substring(8, 10).toIntOrNull() ?: return null
    if (m !in 1..12 || d !in 1..31) return null
    val yy = if (m <= 2) y - 1 else y
    val era = (if (yy >= 0) yy else yy - 399) / 400
    val yoe = yy - era * 400
    val doy = (153 * (if (m > 2) m - 3 else m + 9) + 2) / 5 + d - 1
    val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return (era.toLong() * 146097 + doe - 719468)
}

/**
 * [iso] (YYYY-MM-DD) plus [n] days, or null when it will not parse.
 *
 * Pure calendar arithmetic, no time zone involved. Web's own `addDays` builds a
 * local `Date`, mutates it, and then calls `.toISOString()` — a local→UTC round
 * trip that can land a day off for anyone not on UTC. The only caller pads a
 * reconciliation window by four days, so the bug never surfaces there, and it is
 * not worth reproducing a defect whose observable effect is zero.
 */
fun addDaysIso(iso: String, n: Int): String? {
    val days = isoDaysOrNull(iso) ?: return null
    return isoFromEpochDays(days + n)
}

/** The inverse of [isoDaysOrNull] -- Hinnant's civil_from_days. */
internal fun isoFromEpochDays(days: Long): String {
    val z = days + 719_468L
    val era = (if (z >= 0) z else z - 146_096L) / 146_097L
    val doe = z - era * 146_097L
    val yoe = (doe - doe / 1460L + doe / 36_524L - doe / 146_096L) / 365L
    val y = yoe + era * 400L
    val doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
    val mp = (5L * doy + 2L) / 153L
    val d = doy - (153L * mp + 2L) / 5L + 1L
    val m = if (mp < 10) mp + 3L else mp - 9L
    return "%04d-%02d-%02d".format(
        java.util.Locale.ROOT,
        (if (m <= 2) y + 1 else y).toInt(),
        m.toInt(),
        d.toInt(),
    )
}

internal const val UNCATEGORISED = "Uncategorised"
internal const val REASON_SMALL_SAMPLE = "Much larger than your typical spend (~3× the median)"
internal const val REASON_IQR = "Unusually large — above the normal range for this statement"
