package care.pocket.domain.receipts

// Ported from packages/core/receipts/src/money-text.ts (P1.5a). Parsing
// money and quantities out of OCR text -- deliberately separate from
// Money.kt, which deals in already-trusted values; this file deals in
// whatever a thermal printer and an OCR engine conspired to produce.
// Everything here returns null rather than guessing.
//
// Every Regex pattern is transcribed VERBATIM from the TS source (character
// for character, including the exact escaping), not re-derived, since a
// regex that looks equivalent but isn't would silently misparse a receipt.
// Kotlin's Regex is backed by java.util.regex, which -- like JS's engine --
// is a classic Perl-style backtracking NFA (not POSIX leftmost-longest),
// tries alternatives left-to-right, and (without the UNICODE_CHARACTER_CLASS
// flag, which is never set here) defines \b / \w using the ASCII
// [a-zA-Z0-9_] class exactly like JS's \b without the /u flag -- so every
// pattern below behaves identically to its JS original. Verified by
// documented behavior, not assumed, since word-boundary/Unicode divergence
// is exactly the class of cross-engine risk this codebase treats with
// "never guess" caution (same standard as money rounding/dates).

/** Currency symbols/codes we strip before parsing, and map for detection. */
private val CURRENCY_SYMBOLS: List<Pair<Regex, String>> = listOf(
    Regex("""₹|\brs\.?\b|\binr\b""", RegexOption.IGNORE_CASE) to "INR",
    Regex("""\$|\busd\b""", RegexOption.IGNORE_CASE) to "USD",
    Regex("""€|\beur\b""", RegexOption.IGNORE_CASE) to "EUR",
    Regex("""£|\bgbp\b""", RegexOption.IGNORE_CASE) to "GBP",
    Regex("""¥|\bjpy\b""", RegexOption.IGNORE_CASE) to "JPY",
    Regex("""\baed\b|\bdhs?\b""", RegexOption.IGNORE_CASE) to "AED",
)

/** First currency mentioned anywhere in the text, or null. */
fun detectCurrency(text: String): String? {
    for ((re, code) in CURRENCY_SYMBOLS) if (re.containsMatchIn(text)) return code
    return null
}

/**
 * Parse a money-ish string to integer minor units.
 *
 * Handles both separator conventions by looking at what comes AFTER the
 * last separator rather than assuming a locale: "1,234.56" and "1.234,56"
 * both give 123456, and Indian lakh grouping ("1,23,456") falls out for free.
 */
fun parseMoney(raw: String, minorDigits: Int = 2): Long? {
    var s = raw.trim()
    if (s.isEmpty()) return null

    var negative = false
    if (Regex("""^\(.*\)$""").matches(s)) { negative = true; s = s.substring(1, s.length - 1) } // (12.34)
    if (Regex("""-\s*$""").containsMatchIn(s)) negative = true // 12.34-

    s = Regex("""[^\d.,-]""").replace(s, "")
    if (s.startsWith("-")) negative = true
    s = s.replace("-", "")
    if (!Regex("""\d""").containsMatchIn(s)) return null

    // More than 12 digits is a phone number, GSTIN or invoice reference.
    if (Regex("""\d""").findAll(s).count() > 12) return null

    val lastDot = s.lastIndexOf('.')
    val lastComma = s.lastIndexOf(',')
    val lastSep = maxOf(lastDot, lastComma)
    var decIdx = -1
    if (lastSep >= 0) {
        val after = s.length - lastSep - 1
        val bothPresent = lastDot >= 0 && lastComma >= 0
        // Both separators present: the last one must be the decimal point.
        // Only one: it is a decimal point when it isn't grouping three digits.
        if (bothPresent) decIdx = lastSep
        else if (after == minorDigits || after == 1) decIdx = lastSep
    }

    val intPart = (if (decIdx >= 0) s.substring(0, decIdx) else s).replace(Regex("""[.,]"""), "")
    var fracPart = (if (decIdx >= 0) s.substring(decIdx + 1) else "").replace(Regex("""[.,]"""), "")
    if (intPart.isEmpty() && fracPart.isEmpty()) return null
    fracPart = (fracPart + "0".repeat(minorDigits)).substring(0, minorDigits)

    // Integer arithmetic throughout (not Math.pow-then-round-trip through
    // Double) -- exact, and this is a money value.
    var scale = 1L
    repeat(minorDigits) { scale *= 10 }
    val value = (intPart.ifEmpty { "0" }.toLong()) * scale + (fracPart.ifEmpty { "0" }.toLong())
    return if (negative) -value else value
}

/** A numeric run found in a line, with where it sat. */
data class NumberMatch(val raw: String, val start: Int, val end: Int, val value: Long)

private val NUMBER_RE = Regex("""-?\d[\d.,]*\d|-?\d""")

/** Every parseable number in a line, left to right. */
fun findNumbers(line: String, minorDigits: Int = 2): List<NumberMatch> {
    val out = mutableListOf<NumberMatch>()
    for (m in NUMBER_RE.findAll(line)) {
        val value = parseMoney(m.value, minorDigits) ?: continue
        out.add(NumberMatch(m.value, m.range.first, m.range.last + 1, value))
    }
    return out
}

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

private val MONTHS: Map<String, Int> = mapOf(
    "jan" to 1, "feb" to 2, "mar" to 3, "apr" to 4, "may" to 5, "jun" to 6,
    "jul" to 7, "aug" to 8, "sep" to 9, "oct" to 10, "nov" to 11, "dec" to 12,
)

private fun isoDate(y: Int, m: Int, d: Int): String =
    // Locale.ROOT explicitly, mirroring every other byte-for-byte-compared
    // date string in this codebase (Budget.kt/Finance.kt) -- %d is
    // digit-only so this shouldn't matter in practice, but it's not worth
    // trusting the JVM default locale for a vector-compared string.
    String.format(java.util.Locale.ROOT, "%04d-%02d-%02d", y, m, d)

private fun validDate(y: Int, m: Int, d: Int): Boolean =
    m in 1..12 && d in 1..31 && y in 2000..2100

/**
 * Find a date in receipt text. Day-first (India is the primary market), but
 * an unambiguous day > 12 flips the interpretation. Future dates are
 * rejected -- a receipt cannot be from tomorrow, so a "future" read means
 * we misparsed.
 */
fun findDate(text: String, today: String? = null): String? {
    // Every vector always passes `today` explicitly; this fallback (real
    // wall-clock date) mirrors the TS source's own `new Date()` default but
    // is never exercised by a golden vector.
    val cutoff = today ?: java.time.LocalDate.now(java.time.ZoneOffset.UTC).toString()
    val candidates = mutableListOf<String>()

    // ISO: 2026-07-25
    for (m in Regex("""\b(\d{4})-(\d{1,2})-(\d{1,2})\b""").findAll(text)) {
        val y = m.groupValues[1].toInt(); val mo = m.groupValues[2].toInt(); val d = m.groupValues[3].toInt()
        if (validDate(y, mo, d)) candidates.add(isoDate(y, mo, d))
    }

    // Numeric: 25/07/2026, 25-07-26, 25.07.2026
    for (m in Regex("""\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b""").findAll(text)) {
        var a = m.groupValues[1].toInt()
        var b = m.groupValues[2].toInt()
        val yStr = m.groupValues[3]
        val y = if (yStr.length == 2) 2000 + yStr.toInt() else yStr.toInt()
        // Day-first unless the second field can only be a day.
        if (b > 12 && a <= 12) { val t = a; a = b; b = t }
        if (validDate(y, b, a)) candidates.add(isoDate(y, b, a))
    }

    // Textual: 25 Jul 2026 / Jul 25, 2026
    for (m in Regex("""\b(\d{1,2})[\s\-]([A-Za-z]{3,9})[\s\-,]+(\d{2,4})\b""").findAll(text)) {
        val d = m.groupValues[1].toInt()
        val mo = MONTHS[m.groupValues[2].take(3).lowercase()]
        val yStr = m.groupValues[3]
        val y = if (yStr.length == 2) 2000 + yStr.toInt() else yStr.toInt()
        if (mo != null && validDate(y, mo, d)) candidates.add(isoDate(y, mo, d))
    }
    for (m in Regex("""\b([A-Za-z]{3,9})[\s\-](\d{1,2})[\s\-,]+(\d{2,4})\b""").findAll(text)) {
        val mo = MONTHS[m.groupValues[1].take(3).lowercase()]
        val d = m.groupValues[2].toInt()
        val yStr = m.groupValues[3]
        val y = if (yStr.length == 2) 2000 + yStr.toInt() else yStr.toInt()
        if (mo != null && validDate(y, mo, d)) candidates.add(isoDate(y, mo, d))
    }

    val usable = candidates.filter { it <= cutoff }
    if (usable.isEmpty()) return null
    // The latest plausible date: receipts print the transaction date
    // alongside older things like "member since" or a validity date.
    return usable.sorted().last()
}

// ---------------------------------------------------------------------------
// Quantities
// ---------------------------------------------------------------------------

const val UNIT_WORDS =
    "kg|kgs|g|gm|gms|gram|grams|l|ltr|ltrs|litre|litres|ml|pcs|pc|piece|pieces|nos|no|unit|units|dozen|dz|pkt|pack|packs|box|btl|bottle|bottles"

// A unit only counts when it directly follows a number. Without that
// anchor, the single-letter units match inside ordinary words -- "Parle-G"
// reads as grams, "Model L" as litres.
private val UNIT_RE = Regex("""\d\s*($UNIT_WORDS)\b""", RegexOption.IGNORE_CASE)

/** Canonical-ish unit label, or null. Keeps whatever the receipt printed. */
fun findUnit(text: String): String? {
    val m = UNIT_RE.find(text) ?: return null
    return m.groupValues[1].lowercase()
}

/** Trailing currency symbols and separators left behind after slicing an amount off. */
fun tidyDescription(text: String): String {
    var t = text
    t = Regex("""[₹$€£¥]|\b(rs|inr|usd|eur|gbp)\b\.?""", RegexOption.IGNORE_CASE).replace(t, " ")
    t = Regex("""[\s\-–:|@.,*]+$""").replace(t, "")
    t = Regex("""^[\s\-–:|@.,*]+""").replace(t, "")
    t = Regex("""\s+""").replace(t, " ")
    return t.trim()
}
