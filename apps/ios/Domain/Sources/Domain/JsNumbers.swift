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

 Three languages, three answers, and the differences are visible: `1.15` formats
 as `1.1` in JS (nearest on the EXACT BINARY value, which is 1.14999…), as `1.2`
 through Java's `%.1f` (HALF_UP on the DECIMAL text), and C's printf — which
 `String(format:)` uses — rounds ties to EVEN and disagrees with both.

 ECMA-262 strips the sign FIRST and then breaks ties toward the larger digit, so
 a tie on a negative rounds AWAY from zero: `(-1.25).toFixed(1)` is `"-1.3"`, not
 `"-1.2"`.
 */
public func jsToFixed1(_ x: Double) -> String {
    let negative = x < 0
    var input = Decimal(negative ? -x : x)
    var rounded = Decimal()
    NSDecimalRound(&rounded, &input, 1, .plain)
    let text = NSDecimalNumber(decimal: rounded).stringValue
    // stringValue drops a trailing zero ("1.0" comes back as "1"), and toFixed
    // never does.
    let padded = text.contains(".") ? text : text + ".0"
    return (negative ? "-" : "") + padded
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
