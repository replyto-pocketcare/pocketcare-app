package com.sanvya.app.domain.js

import java.math.BigDecimal
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
