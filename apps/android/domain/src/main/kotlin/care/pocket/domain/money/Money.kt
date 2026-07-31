package care.pocket.domain.money

import java.math.BigDecimal
import java.math.RoundingMode

// Ported from packages/core/money/src/index.ts (P1.1a). Correctness is
// judged against tools/golden-vectors/vectors/money.json, not against a
// fresh reading of the TS -- see docs/plans/native-mobile-apps.md
// section 5 and CLAUDE.md golden rule 8 ("web is the spec").
//
// INVARIANTS (mirrors the TS file's header comment):
//  - A Money value is an INTEGER count of minor units + an ISO 4217
//    currency. Never Double/Float for storage/arithmetic -- amount is
//    Long, on purpose.
//  - Values are stored in their native currency and never mutated in
//    place; conversion produces a NEW Money in the target currency.
//  - Arithmetic across different currencies throws unless converted
//    first.
//
// format() (locale-aware currency string) is NOT ported yet. It needs a
// currency-to-locale table (150+ entries in the TS source) and its exact
// string output depends on ICU data, which can differ between the V8
// engine that exported the vectors and Android's ICU -- that's a real
// cross-platform risk worth its own careful, build-verified pass rather
// than a same-turn guess. money.json's 3 "format" vectors stay skipped
// until that follow-up task.

data class Money(val amount: Long, val currency: String)

// Matches the TS side's custom `CurrencyMismatchError` (whose `name`
// field is explicitly set to "CurrencyMismatchError" in its
// constructor). Kotlin exceptions don't have a settable `name` property
// the way JS Errors do, but they don't need one here: this class's own
// `::class.simpleName` is already the string "CurrencyMismatchError",
// which is exactly what VectorRunnerTest.kt compares a vector's
// `throws.name` against.
class CurrencyMismatchError(a: String, b: String) : RuntimeException("Currency mismatch: $a vs $b")

/** Number of minor-unit decimal places for a currency (USD=2, JPY=0, BHD=3). */
fun minorUnits(currency: String): Int {
    return try {
        val digits = java.util.Currency.getInstance(currency).defaultFractionDigits
        if (digits < 0) 2 else digits
    } catch (e: IllegalArgumentException) {
        // Unknown ISO 4217 code -- java.util.Currency.getInstance throws;
        // Intl.NumberFormat's equivalent failure is also caught in the TS
        // source and defaults to 2.
        2
    }
}

/**
 * Round half away from zero: 0.5 -> 1, -0.5 -> -1 (never banker's
 * rounding / round-half-to-even, and never JS's Math.round quirk of
 * always rounding .5 toward +Infinity for negatives). Verified against
 * java.math.RoundingMode.HALF_UP's documented behavior (rounds ties away
 * from zero, symmetric for positive and negative values) rather than
 * assumed -- money rounding is a "never guess" area (plan section 1 rule
 * 6). BigDecimal.valueOf(Double), not the BigDecimal(Double) raw-bits
 * constructor, so this rounds the same decimal value a human (or JS's
 * Double-to-string) would see, not the binary-float's exact expansion.
 */
private fun roundHalfAwayFromZero(n: Double): Long {
    return BigDecimal.valueOf(n).setScale(0, RoundingMode.HALF_UP).toLong()
}

/** Construct Money from an already-minor-unit integer. */
fun money(amount: Long, currency: String): Money {
    return Money(amount, currency)
}

/**
 * Construct Money from an already-minor-unit value that might not be a
 * whole number (mirrors the TS source, where `amount` is a JS `number`
 * and money() runtime-checks `Number.isInteger`). Real ports should
 * prefer the Long overload above; this exists so the vector adapter can
 * reproduce the TS "throws on non-integer amount" vector without a
 * separate code path.
 */
fun money(amount: Double, currency: String): Money {
    if (amount != Math.floor(amount) || amount.isInfinite() || amount.isNaN()) {
        throw IllegalArgumentException("Money.amount must be an integer minor-unit value, got ${formatJsNumber(amount)}")
    }
    return Money(amount.toLong(), currency)
}

/**
 * Formats a Double the way JS's template-literal `${amount}` would
 * (e.g. 1.5 -> "1.5", not "1.50" or "1.5000000000000002") -- needed only
 * to reproduce the exact error-message text a golden vector asserts on.
 * Kotlin's Double.toString() already matches JS's shortest-round-trip
 * decimal representation for the values the vectors actually use (whole
 * numbers and simple decimals like 1.5), so no special-casing beyond
 * stripping a trailing ".0" for whole numbers, which JS's `${n}` also
 * does (`${1.0}` is "1", not "1.0").
 */
private fun formatJsNumber(n: Double): String {
    val s = n.toString()
    return if (s.endsWith(".0")) s.dropLast(2) else s
}

/** Construct Money from a human/major value (e.g. 12.34 USD -> 1234). */
fun fromMajor(value: Double, currency: String): Money {
    val factor = Math.pow(10.0, minorUnits(currency).toDouble())
    return money(roundHalfAwayFromZero(value * factor), currency)
}

/** Major-unit number (e.g. 1234 cents -> 12.34). For display/formatting only. */
fun toMajor(m: Money): Double {
    return m.amount / Math.pow(10.0, minorUnits(m.currency).toDouble())
}

fun isZero(m: Money): Boolean = m.amount == 0L
fun isNegative(m: Money): Boolean = m.amount < 0L

private fun assertSameCurrency(a: Money, b: Money) {
    if (a.currency != b.currency) throw CurrencyMismatchError(a.currency, b.currency)
}

fun add(a: Money, b: Money): Money {
    assertSameCurrency(a, b)
    return money(a.amount + b.amount, a.currency)
}

fun subtract(a: Money, b: Money): Money {
    assertSameCurrency(a, b)
    return money(a.amount - b.amount, a.currency)
}

fun negate(m: Money): Money = money(-m.amount, m.currency)

/** Multiply by a scalar (e.g. a rate or quantity); rounds to whole minor units. */
fun scale(m: Money, factor: Double): Money {
    return money(roundHalfAwayFromZero(m.amount * factor), m.currency)
}

/** Sum a list; empty list requires an explicit currency. */
fun sum(items: List<Money>, currency: String? = null): Money {
    if (items.isEmpty()) {
        if (currency == null) throw IllegalArgumentException("sum() of empty list needs a currency")
        return money(0L, currency)
    }
    return items.reduce { acc, m -> add(acc, m) }
}

/**
 * Convert to another currency using an explicit rate (target per 1
 * source major). Returns Money in the target currency; the source is
 * unchanged. Rounds to the target currency's minor units.
 */
fun convert(m: Money, to: String, rate: Double): Money {
    if (m.currency == to) return m
    if (!(rate > 0)) throw IllegalArgumentException("convert() needs a positive rate, got ${formatJsNumber(rate)}")
    val sourceMajor = toMajor(m)
    val targetMinorFactor = Math.pow(10.0, minorUnits(to).toDouble())
    return money(roundHalfAwayFromZero(sourceMajor * rate * targetMinorFactor), to)
}

/**
 * Split a total into `parts` amounts that sum EXACTLY to the total
 * (largest-remainder distribution). Powers the transaction breakdown /
 * "+" sub-item builder so items always reconcile to the total.
 */
fun split(total: Money, parts: Int): List<Money> {
    if (parts <= 0) {
        throw IllegalArgumentException("split() needs a positive integer count, got $parts")
    }
    val base = total.amount / parts // Kotlin's Long / Int division truncates toward zero, matching Math.trunc.
    var remainder = total.amount - base * parts
    val step = if (remainder > 0) 1L else if (remainder < 0) -1L else 1L
    remainder = Math.abs(remainder)
    val out = mutableListOf<Money>()
    for (i in 0 until parts) {
        val extra = if (i < remainder) step else 0L
        out.add(money(base + extra, total.currency))
    }
    return out
}

/** True when breakdown items sum exactly to the transaction total (invariant #5). */
fun itemsReconcile(total: Money, items: List<Money>): Boolean {
    if (items.isEmpty()) return total.amount == 0L
    // Any item in a different currency can never reconcile.
    if (items.any { it.currency != total.currency }) return false
    return sum(items, total.currency).amount == total.amount
}
