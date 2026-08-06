package com.sanvya.app.domain.insights

import com.sanvya.app.domain.ledger.RateLookup
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.math.roundToLong

// Ported verbatim from apps/web/src/market/dividends.ts (89 lines) for the
// Insights feed's dividend_income/portfolio_projection cards (task #28).
// Neither this file's callers, nor apps/investments (P3.10/P3.15, task
// #26/#40), previously ported this math -- Investments' own spec lists a
// Dividend/Projection panel that was never actually built; this is the
// first mobile port of dividends.ts, done here because the Insights cards
// need it. Not golden-vector tested (dividends.ts has no vectors on web
// either -- see AUDIT_HISTORY's Insights entry).

/** A holding, reduced to the fields dividend matching needs. */
data class HoldingLite(val symbol: String, val exchange: String?, val quantity: Double, val currency: String)

/** One row from `market_dividends` (global, read-only). */
data class DivRow(val symbol: String, val exchange: String?, val exDate: String, val payDate: String?, val amount: Long, val currency: String)

/** One dividend payment estimated in the user's base currency (minor units). */
data class DivEvent(val date: String, val base: Long, val upcoming: Boolean)

private fun divKey(symbol: String, exchange: String?) = "${symbol.uppercase()}|${(exchange ?: "").uppercase()}"

/**
 * Estimate dividend income per ex-date in base currency: for each dividend
 * row, sum (amount-per-share x shares held) over matching holdings,
 * converted to base. Uses CURRENT quantity (historical share counts aren't
 * tracked -- a reasonable estimate, matches web exactly). Matches on
 * symbol+exchange, falling back to symbol only.
 */
fun computeDividendEvents(holdings: List<HoldingLite>, dividends: List<DivRow>, getRate: RateLookup, base: String): List<DivEvent> {
    val bySymEx = LinkedHashMap<String, MutableList<HoldingLite>>()
    val bySym = LinkedHashMap<String, MutableList<HoldingLite>>()
    for (h in holdings) {
        bySymEx.getOrPut(divKey(h.symbol, h.exchange)) { mutableListOf() }.add(h)
        bySym.getOrPut(h.symbol.uppercase()) { mutableListOf() }.add(h)
    }
    val today = LocalDate.now(ZoneOffset.UTC).toString()
    val events = mutableListOf<DivEvent>()
    for (d in dividends) {
        val matches = bySymEx[divKey(d.symbol, d.exchange)] ?: bySym[d.symbol.uppercase()] ?: emptyList()
        if (matches.isEmpty()) continue
        val shares = matches.sumOf { it.quantity }
        if (shares <= 0.0) continue
        val inCcy = d.amount * shares
        val rate = if (d.currency == base) 1.0 else getRate(d.currency, base)
        events.add(DivEvent(date = d.exDate, base = (inCcy * rate).roundToLong(), upcoming = d.exDate >= today))
    }
    return events.sortedBy { it.date }
}

enum class DividendPeriod { WEEK, MONTH, QUARTER, YEAR, ALL }

data class DividendBucket(val label: String, val key: String, val value: Long, val upcoming: Boolean)

private val MONTHS_SHORT = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

private fun isoWeek(d: LocalDate): String {
    val week = d.get(java.time.temporal.WeekFields.ISO.weekOfWeekBasedYear())
    val wby = d.get(java.time.temporal.WeekFields.ISO.weekBasedYear())
    return "$wby-W${week.toString().padStart(2, '0')}"
}

/** Group events into period buckets. Recent windows are capped; "all" spans
 * everything by year -- matches web's bucketize() exactly. */
fun bucketize(events: List<DivEvent>, period: DividendPeriod): List<DividendBucket> {
    val map = LinkedHashMap<String, DividendBucket>()
    fun put(k: String, label: String, v: Long, upcoming: Boolean) {
        val cur = map[k]
        map[k] = if (cur != null) cur.copy(value = cur.value + v, upcoming = cur.upcoming || upcoming) else DividendBucket(label, k, v, upcoming)
    }
    for (e in events) {
        val d = LocalDate.parse(e.date.take(10))
        when (period) {
            DividendPeriod.WEEK -> put(isoWeek(d), "${MONTHS_SHORT[d.monthValue - 1]} ${d.dayOfMonth}", e.base, e.upcoming)
            DividendPeriod.MONTH -> put("${d.year}-${d.monthValue.toString().padStart(2, '0')}", "${MONTHS_SHORT[d.monthValue - 1]} '${d.year.toString().takeLast(2)}", e.base, e.upcoming)
            DividendPeriod.QUARTER -> { val q = (d.monthValue - 1) / 3 + 1; put("${d.year}-Q$q", "Q$q '${d.year.toString().takeLast(2)}", e.base, e.upcoming) }
            else -> put(d.year.toString(), d.year.toString(), e.base, e.upcoming) // year & all -> by year
        }
    }
    val all = map.values.sortedBy { it.key }
    val cap = when (period) { DividendPeriod.WEEK -> 12; DividendPeriod.MONTH -> 12; DividendPeriod.QUARTER -> 8; DividendPeriod.YEAR -> 6; DividendPeriod.ALL -> 999 }
    return if (all.size > cap) all.takeLast(cap) else all
}

data class DividendSummary(val trailing12: Long, val upcoming12: Long, val total: Long)

/** Trailing-12-month realized income + projected next-12-month income (from
 * scheduled + trailing run-rate) -- matches web's dividendSummary() exactly. */
fun dividendSummary(events: List<DivEvent>): DividendSummary {
    val now = Instant.now().toEpochMilli()
    val yearMs = 365L * 86_400_000L
    var trailing12 = 0L; var upcoming12 = 0L; var total = 0L
    for (e in events) {
        total += e.base
        val t = LocalDate.parse(e.date.take(10)).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        if (t <= now && t >= now - yearMs) trailing12 += e.base
        if (t > now && t <= now + yearMs) upcoming12 += e.base
    }
    return DividendSummary(trailing12, upcoming12, total)
}
