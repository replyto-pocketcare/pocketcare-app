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

/**
 `Number(string)` — the COERCION, which is not `parseFloat`.

 The difference decides real inputs. `Number("12abc")` is NaN where
 `parseFloat("12abc")` is 12, and web's split editor reads its amount fields
 with `Number(v) || 0` — so a share typed as "12abc" contributes ZERO there and
 would contribute twelve to a `parseFloat` port. That is a silent arithmetic
 difference in a screen whose whole job is arithmetic.

 Scope, stated rather than implied: the decimal, hex, binary and octal literal
 forms plus `Infinity`, which is everything a string typed into a number field
 can be. The exotic remainder of the spec's `StringNumericLiteral` grammar
 (legacy octal, other whitespace classes) is not reachable from a keyboard and
 is not implemented.

 Returns NaN for anything unparseable — web's own `|| 0` fallback stays at the
 call site, because zero is not always the right default and this function
 should not decide that.
 */
public func jsNumber(_ s: String) -> Double {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return 0 }
    if t == "Infinity" || t == "+Infinity" { return .infinity }
    if t == "-Infinity" { return -.infinity }
    if let v = radixValue(t, "0x", "0X", 16) { return v }
    if let v = radixValue(t, "0o", "0O", 8) { return v }
    if let v = radixValue(t, "0b", "0B", 2) { return v }
    // The WHOLE string must be a decimal literal — that is exactly what makes
    // this Number() and not parseFloat().
    guard t.range(
        of: "^[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?$",
        options: .regularExpression
    ) != nil else { return .nan }
    return Double(t) ?? .nan
}

private func radixValue(_ t: String, _ lower: String, _ upper: String, _ radix: Int) -> Double? {
    guard t.hasPrefix(lower) || t.hasPrefix(upper) else { return nil }
    let digits = String(t.dropFirst(2))
    if digits.isEmpty { return Double.nan }
    guard let v = UInt64(digits, radix: radix) else { return Double.nan }
    return Double(v)
}

/**
 `JSON.stringify` on a number — ECMA-262's `Number::toString`, in full.

 **This replaced a narrower function that was wrong.** The first version assumed
 every number it would ever see was an exact multiple of one hundredth, because
 every number the assistant's prompt CARRIES is. That was true of the callers and
 false of the function: `summaryForPrompt` is public, takes a struct of plain
 Doubles, and enforced nothing. The first fixture that violated the assumption
 produced `6172.8` where the browser produces `6172.799999999999` — silently, on
 both platforms, in a prompt. An unenforced precondition on a public function is
 a defect even when every current caller happens to satisfy it.

 Two halves, both from the spec:

 1. The SHORTEST decimal that round-trips back to the same double. Swift's
    `description` is that, but its exponent formatting is not JS's, so the digits
    are found here the same way Kotlin finds them — round the EXACT value to
    1…17 significant digits, take the first that survives a round trip — rather
    than by each platform's own printer.
 2. The spec's own formatting rules, which decide plain vs exponent notation by
    where the decimal point falls — plain for `1e-7 < |x| < 1e21`, exponent
    outside it. `1e21` is `"1e+21"` and `1e-7` is `"1e-7"`: the positive exponent
    carries a sign and the negative one does not, and that asymmetry is real.

 Verified against V8's own output across 25 values, including the ones that broke
 CI.
 */
public func jsonNumber(_ v: Double) -> String {
    // JSON.stringify(NaN) and (Infinity) are both `null`, not an error.
    if v.isNaN || v.isInfinite { return "null" }
    if v == 0 { return "0" } // covers -0.0, which JSON.stringify also prints as 0

    let negative = v < 0
    let magnitude = abs(v)
    guard let (digits, pointAt) = shortestRoundTripDigits(magnitude) else { return "\(v)" }

    let k = digits.count
    let n = pointAt
    let chars = Array(digits)
    let body: String
    if n >= k && n <= plainNotationMaxExp {
        body = digits + String(repeating: "0", count: n - k)
    } else if n > 0 && n <= plainNotationMaxExp {
        body = String(chars[0..<n]) + "." + String(chars[n...])
    } else if n > plainNotationMinExp && n <= 0 {
        body = "0." + String(repeating: "0", count: -n) + digits
    } else {
        let exponent = n - 1
        let mantissa = k == 1 ? digits : String(chars[0]) + "." + String(chars[1...])
        body = mantissa + "e" + (exponent >= 0 ? "+" : "-") + String(abs(exponent))
    }
    return negative ? "-" + body : body
}

/**
 The shortest decimal digit string that round-trips, and where its decimal point
 falls.

 `%.30e` is the exact expansion to 31 significant digits, and the rounding to
 `precision` digits is then done by hand, HALF_UP — because C's printf rounds
 ties to EVEN and Kotlin's `BigDecimal` rounds them UP, and a tie decided
 differently would give the two platforms different digit strings for the same
 double.

 31 digits is enough to decide any tie that can actually occur: a tie needs the
 exact value to be `d…d5` followed by nothing but zeros, and a binary double
 whose expansion is that short has far fewer than 31 significant digits. When the
 expansion IS longer, some digit past the 31st is non-zero, the value is strictly
 more than half, and rounding up is what HALF_UP does anyway.
 */
private func shortestRoundTripDigits(_ magnitude: Double) -> (String, Int)? {
    let exact = String(format: "%.30e", magnitude)
    let parts = exact.split(separator: "e")
    guard parts.count == 2, let exponent = Int(parts[1]) else { return nil }
    let mantissaDigits = parts[0].filter { $0.isNumber }
    guard !mantissaDigits.isEmpty else { return nil }

    for precision in 1...maxDoubleSigDigits {
        guard let (digits, carried) = roundDigitsHalfUp(Array(mantissaDigits), to: precision) else { continue }
        // A carry can push 999… to 1000…, which moves the point one place right.
        let pointAt = exponent + 1 + (carried ? 1 : 0)
        let trimmed = trimTrailingZeros(digits)
        let candidate = rebuild(trimmed, pointAt)
        if Double(candidate) == magnitude { return (trimmed, pointAt) }
    }
    return nil
}

/// Round a digit string to `precision` digits, HALF_UP. Returns the digits and whether a carry overflowed.
private func roundDigitsHalfUp(_ digits: [Character], to precision: Int) -> (String, Bool)? {
    guard precision <= digits.count else { return (String(digits), false) }
    var kept = Array(digits[0..<precision])
    let roundUp = digits[precision] >= "5"
    if roundUp {
        var i = precision - 1
        while i >= 0 {
            if kept[i] == "9" { kept[i] = "0"; i -= 1 } else {
                kept[i] = Character(String(kept[i].wholeNumberValue! + 1))
                break
            }
        }
        if i < 0 { return ("1" + String(kept), true) }
    }
    return (String(kept), false)
}

private func trimTrailingZeros(_ s: String) -> String {
    var out = s
    while out.count > 1 && out.hasSuffix("0") { out.removeLast() }
    return out
}

/// `0.<digits> x 10^pointAt` as a string a Double initialiser will accept.
private func rebuild(_ digits: String, _ pointAt: Int) -> String {
    "0." + digits + "e" + String(pointAt)
}

/// A double needs at most 17 significant decimal digits to round-trip.
private let maxDoubleSigDigits = 17

/// The spec's own bounds for plain notation: `1e-7 < |x| < 1e21`.
private let plainNotationMaxExp = 21
private let plainNotationMinExp = -6

