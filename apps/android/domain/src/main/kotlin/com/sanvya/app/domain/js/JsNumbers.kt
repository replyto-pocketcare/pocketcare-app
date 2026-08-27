package com.sanvya.app.domain.js

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode

/**
 * JavaScript number semantics, in one place.
 *
 * Every function here exists because a Kotlin or Swift built-in that LOOKS like
 * the JS one gives a different answer, and every difference below has already
 * been the cause of a divergence in this port. They live together rather than
 * privately beside each caller because there were three copies of two of them
 * before this file existed, and a fourth was about to be written.
 *
 * Web is the spec. These are not "better" than the JS versions; they are the JS
 * versions.
 *
 * Mirrors iOS's JsNumbers.swift.
 */

/**
 * `Math.round` — half UP (toward +infinity), not half-away-from-zero.
 *
 * `Math.round(-0.5)` is `-0` in JS and `0` once printed; Kotlin's
 * `Math.round(-0.5)` is `0` but `kotlin.math.round(-1.5)` is `-2`. `floor(x+0.5)`
 * is the spec, verbatim.
 */
fun jsRound(v: Double): Double = kotlin.math.floor(v + 0.5)

/**
 * `Number.prototype.toFixed(1)`, which is not `"%.1f".format(...)`.
 *
 * Three languages, three answers, and the differences are visible: `1.15`
 * formats as `1.2` through Java's `%.1f` (HALF_UP on the DECIMAL text) and as
 * `1.1` in JS (nearest on the EXACT BINARY value, which is 1.14999…). C's
 * printf, which Swift's `String(format:)` uses, rounds ties to EVEN and
 * disagrees with both.
 *
 * ECMA-262 strips the sign FIRST and then breaks ties toward the larger digit,
 * so a tie on a negative rounds AWAY from zero: `(-1.25).toFixed(1)` is
 * `"-1.3"`, not `"-1.2"`. `BigDecimal(double)` is exact-binary, and HALF_UP on a
 * positive is exactly that rule.
 */
fun jsToFixed1(x: Double): String {
    val negative = x < 0
    val rounded = BigDecimal(if (negative) -x else x).setScale(1, RoundingMode.HALF_UP)
    return (if (negative) "-" else "") + rounded.toPlainString()
}

/**
 * `Number.parseFloat` semantics: a leading numeric prefix wins and the rest is
 * ignored.
 *
 * Kotlin's `toDoubleOrNull` requires the WHOLE string, and a bank cell really
 * does contain things like "1,234.56 Cr" — so the difference is a row silently
 * importing as zero rather than as its amount.
 */
fun jsParseFloat(s: String): Double? {
    val m = Regex("^[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?").find(s) ?: return null
    return m.value.toDoubleOrNull()
}

/**
 * `JSON.stringify` on a number — ECMA-262's `Number::toString`, in full.
 *
 * **This replaced a narrower function that was wrong.** The first version
 * assumed every number it would ever see was an exact multiple of one hundredth,
 * because every number the assistant's prompt CARRIES is. That was true of the
 * callers and false of the function: `summaryForPrompt` is public, takes a
 * struct of plain Doubles, and enforced nothing. The first fixture that violated
 * the assumption produced `6172.8` where the browser produces
 * `6172.799999999999` — silently, on both platforms, in a prompt. An unenforced
 * precondition on a public function is a defect even when every current caller
 * happens to satisfy it.
 *
 * Two halves, both from the spec:
 *
 * 1. The SHORTEST decimal that round-trips back to the same double. Kotlin's own
 *    `Double.toString()` is not that on JDK 17 (JDK-4511638 landed in 19), so
 *    the digits are found by trying 1..17 significant digits and taking the
 *    first that survives a round trip.
 * 2. The spec's own formatting rules, which decide plain vs exponent notation by
 *    where the decimal point falls — plain for `1e-7 < |x| < 1e21`, exponent
 *    outside it. `1e21` is `"1e+21"` and `1e-7` is `"1e-7"`: the positive
 *    exponent carries a sign and the negative one does not, and that asymmetry
 *    is real.
 *
 * Verified against V8's own output across 25 values, including the ones that
 * broke CI.
 */
fun jsonNumber(v: Double): String {
    // JSON.stringify(NaN) and (Infinity) are both `null`, not an error.
    if (v.isNaN() || v.isInfinite()) return "null"
    if (v == 0.0) return "0" // covers -0.0, which JSON.stringify also prints as 0

    val negative = v < 0
    val magnitude = kotlin.math.abs(v)

    // HALF_UP on the EXACT binary value, so the digits are decided the same way
    // on both platforms rather than by each one's printf.
    var digits = ""
    var pointAt = 0
    for (precision in 1..MAX_DOUBLE_SIG_DIGITS) {
        val rounded = BigDecimal(magnitude).round(MathContext(precision, RoundingMode.HALF_UP))
        if (rounded.toDouble() == magnitude) {
            val trimmed = rounded.stripTrailingZeros()
            digits = trimmed.unscaledValue().toString()
            pointAt = trimmed.precision() - trimmed.scale()
            break
        }
    }
    if (digits.isEmpty()) return v.toString() // unreachable for a finite double

    val k = digits.length
    val n = pointAt
    val body = when {
        n in k..PLAIN_NOTATION_MAX_EXP -> digits + "0".repeat(n - k)
        n in 1..PLAIN_NOTATION_MAX_EXP -> digits.substring(0, n) + "." + digits.substring(n)
        n > PLAIN_NOTATION_MIN_EXP && n <= 0 -> "0." + "0".repeat(-n) + digits
        else -> {
            val exponent = n - 1
            val mantissa = if (k == 1) digits else digits.substring(0, 1) + "." + digits.substring(1)
            mantissa + "e" + (if (exponent >= 0) "+" else "-") + kotlin.math.abs(exponent)
        }
    }
    return if (negative) "-$body" else body
}

/** A double needs at most 17 significant decimal digits to round-trip. */
private const val MAX_DOUBLE_SIG_DIGITS = 17

/** The spec's own bounds for plain notation: `1e-7 < |x| < 1e21`. */
private const val PLAIN_NOTATION_MAX_EXP = 21
private const val PLAIN_NOTATION_MIN_EXP = -6

