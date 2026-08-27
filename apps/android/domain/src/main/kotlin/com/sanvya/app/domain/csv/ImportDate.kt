package com.sanvya.app.domain.csv

/**
 * Normalises whatever a CSV put in the date column into an ISO-8601 instant.
 * Ported from `toIso` in apps/web/src/data/importCsv.ts.
 *
 * **Two deliberate divergences, both because web's version is device-dependent
 * or unportable:**
 *
 * 1. **Everything is read as UTC.** Web builds `new Date(yr, mm-1, dd, hh, mi)`
 *    -- LOCAL time -- and then calls `.toISOString()`. The same CSV therefore
 *    imports different `occurred_at` values in Mumbai and in London, and a
 *    DD/MM/YYYY row dated the 1st lands on the previous day for anyone east of
 *    UTC. A date column with no timezone in it is a civil date; reading it as
 *    UTC is the only answer that gives every device the same ledger.
 * 2. **A closed set of formats.** Web's `new Date(s)` accepts anything the
 *    JavaScript engine will parse, including "Aug 1, 2026" and RFC-2822. There
 *    is no equivalent on either phone and no specification to port. ISO-8601
 *    and the day-first numeric forms are what real exports contain; anything
 *    else falls back to `nowIso`, exactly as an unparseable string does on web.
 *
 * `nowIso` is a parameter, not a clock read -- nothing in domain reads a clock.
 *
 * Mirrors apps/ios/Domain/Sources/Domain/ImportDate.swift.
 */
private val ISO = Regex("^(\\d{4})-(\\d{1,2})-(\\d{1,2})(?:[ T](\\d{1,2}):(\\d{2})(?::(\\d{2}))?)?")

/** Day first: `31/12/2026`, `31-12-26`, `31.12.2026`, optionally `HH:mm`. */
private val DAY_FIRST = Regex("^(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{2,4})(?:[ T](\\d{1,2}):(\\d{2}))?")

fun importDate(raw: String, nowIso: String): String {
    if (raw.isEmpty()) return nowIso

    ISO.find(raw)?.let { m ->
        val (y, mo, d) = Triple(m.groupValues[1].toInt(), m.groupValues[2].toInt(), m.groupValues[3].toInt())
        val h = m.groupValues[4].ifEmpty { "0" }.toInt()
        val mi = m.groupValues[5].ifEmpty { "0" }.toInt()
        val s = m.groupValues[6].ifEmpty { "0" }.toInt()
        return isoInstant(y, mo, d, h, mi, s) ?: nowIso
    }

    DAY_FIRST.find(raw)?.let { m ->
        val d = m.groupValues[1].toInt()
        val mo = m.groupValues[2].toInt()
        val rawYear = m.groupValues[3]
        // Web's rule, kept: a two-digit year is 20xx. It is wrong for anything
        // before 2000, and no personal-finance export contains one.
        val y = if (rawYear.length == 2) 2000 + rawYear.toInt() else rawYear.toInt()
        val h = m.groupValues[4].ifEmpty { "0" }.toInt()
        val mi = m.groupValues[5].ifEmpty { "0" }.toInt()
        return isoInstant(y, mo, d, h, mi, 0) ?: nowIso
    }

    return nowIso
}

/** `null` for a date that does not exist, e.g. 31 February. */
private fun isoInstant(y: Int, mo: Int, d: Int, h: Int, mi: Int, s: Int): String? {
    if (mo !in 1..12 || d < 1 || h > 23 || mi > 59 || s > 59) return null
    val date = runCatching { java.time.LocalDate.of(y, mo, d) }.getOrNull() ?: return null
    return String.format(
        java.util.Locale.ROOT,
        "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
        date.year, date.monthValue, date.dayOfMonth, h, mi, s,
    )
}

/**
 * Best-effort account type from its name -- users can change it afterwards.
 * Ported from `guessAccountType` in importCsv.ts, regex for regex.
 */
private val STOCKS = Regex("stock|equit|\\bshares?\\b")
private val MUTUAL = Regex("mutual|\\bmf\\b|\\bsip\\b")
private val CREDIT = Regex("credit|\\bcard\\b")
private val CASH = Regex("cash|wallet")
private val CURRENT = Regex("current|checking")

fun guessAccountType(name: String): String {
    val n = name.lowercase()
    return when {
        STOCKS.containsMatchIn(n) -> "stocks"
        MUTUAL.containsMatchIn(n) -> "mutual_funds"
        CREDIT.containsMatchIn(n) -> "credit_card"
        CASH.containsMatchIn(n) -> "cash"
        CURRENT.containsMatchIn(n) -> "current"
        else -> "savings"
    }
}
