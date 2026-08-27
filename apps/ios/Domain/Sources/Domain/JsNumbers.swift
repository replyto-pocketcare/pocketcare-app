import Foundation

/**
 JavaScript number semantics, in one place.

 Every function here exists because a Swift or Kotlin built-in that LOOKS like
 the JS one gives a different answer, and every difference below has already been
 the cause of a divergence in this port. They live together rather than privately
 beside each caller because there were three copies of two of them before this
 file existed, and a fourth was about to be written.

 Web is the spec. These are not "better" than the JS versions; they are the JS
 versions.

 Mirrors Android's JsNumbers.kt.
 */

/**
 `Math.round` — half UP (toward +infinity), not half-away-from-zero.

 Swift's `.rounded()` is half-away-from-zero, so `(-0.5).rounded()` is `-1` where
 JS gives `-0`. `floor(x + 0.5)` is the spec, verbatim.
 */
public func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }

/**
 `Number.prototype.toFixed(1)`, which is not `String(format: "%.1f", …)`.

 Three languages, three answers. `1.15` is `1.1` in JS — nearest on the EXACT
 BINARY value, which is 1.14999… — `1.2` through Java's `%.1f` (HALF_UP on the
 DECIMAL text), and `1.2` again through `String(format: "%.1f", …)`, which is
 C's printf rounding ties to EVEN.

 ECMA-262 strips the sign FIRST and then breaks ties toward the larger digit, so
 a tie on a negative rounds AWAY from zero: `(-1.25).toFixed(1)` is `"-1.3"`, not
 `"-1.2"`.

 printf is still what produces the digits here, just not the rounding: asked for
 twenty decimal places it prints the exact value rather than a rounded one, and
 the single-digit decision below is then made by the spec's own rule.
 */
public func jsToFixed1(_ x: Double) -> String {
    let negative = x < 0
    let v = negative ? -x : x
    guard v.isFinite else { return "\(x)" }

    // `%.20f` prints C's correctly-rounded expansion of the EXACT binary value,
    // which is the whole point. `Decimal(Double)` does NOT: it converts via the
    // double's shortest decimal form, so `Decimal(1.15)` is exactly 1.15 and
    // rounds to 1.2, while the double itself is 1.14999999999999991 and JS says
    // 1.1. That was a real CI failure, caught by the tie fixtures.
    let exact = String(format: "%.20f", v)
    guard let dot = exact.firstIndex(of: ".") else { return (negative ? "-" : "") + exact + ".0" }
    var whole = String(exact[exact.startIndex..<dot])
    let frac = Array(exact[exact.index(after: dot)...])
    guard let first = frac.first, let tenthsDigit = first.wholeNumberValue else {
        return (negative ? "-" : "") + whole + ".0"
    }

    // Ties round toward the LARGER digit and the sign has already been stripped,
    // so "the next digit is >= 5" covers both "more than half" and "exactly
    // half" in one test.
    var tenths = tenthsDigit
    if frac.count > 1, frac[1] >= "5" { tenths += 1 }
    if tenths == 10 {
        tenths = 0
        whole = String((Int64(whole) ?? 0) + 1)
    }
    return (negative ? "-" : "") + whole + "." + String(tenths)
}

/**
 `Number.parseFloat` semantics: a leading numeric prefix wins and the rest is
 ignored.

 `Double(s)` requires the WHOLE string, and a bank cell really does contain
 things like "1,234.56 Cr" — so the difference is a row silently importing as
 zero rather than as its amount.
 */
public func jsParseFloat(_ s: String) -> Double? {
    guard let r = s.range(of: "^[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?", options: .regularExpression) else {
        return nil
    }
    return Double(s[r])
}
