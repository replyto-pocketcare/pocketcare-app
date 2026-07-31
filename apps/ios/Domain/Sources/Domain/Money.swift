import Foundation

// Ported from packages/core/money/src/index.ts (P1.1b). Correctness is
// judged against tools/golden-vectors/vectors/money.json, not against a
// fresh reading of the TS -- see docs/plans/native-mobile-apps.md
// section 5 and CLAUDE.md golden rule 8 ("web is the spec"). Mirrors
// apps/android/domain/.../money/Money.kt (P1.1a) -- same field names,
// same rounding semantics, same deferred format() decision below.
//
// INVARIANTS (mirrors the TS file's header comment):
//  - A Money value is an INTEGER count of minor units + an ISO 4217
//    currency. Never Double/Float for storage/arithmetic -- amount is
//    Int64, on purpose.
//  - Values are stored in their native currency and never mutated in
//    place; conversion produces a NEW Money in the target currency.
//  - Arithmetic across different currencies throws unless converted
//    first.
//
// format() (locale-aware currency string) is NOT ported yet. It needs a
// currency-to-locale table (150+ entries in the TS source) and its exact
// string output depends on ICU/CLDR data, which can differ between the
// V8 engine that exported the vectors and Apple's Foundation -- that's a
// real cross-platform risk worth its own careful, build-verified pass
// rather than a same-turn guess. money.json's 3 "format" vectors stay
// skipped until that follow-up task.

public struct Money: Equatable {
    public let amount: Int64
    public let currency: String
}

public struct CurrencyMismatchError: Error, CustomStringConvertible {
    let a: String
    let b: String
    public var description: String { "Currency mismatch: \(a) vs \(b)" }
}

/// Stands in for the TS source's plain `new Error(message)` call sites,
/// which don't map to any single specific Swift error type. The vector
/// runner treats a vector's `throws.name == "Error"` as "any error type
/// is fine, just check the message" for exactly this reason -- see
/// VectorRunnerTests.swift.
public struct MoneyError: Error, CustomStringConvertible {
    public let description: String
}

/// ISO 4217 currencies whose minor unit isn't the common default of 2
/// decimal places. Verified via search 2026-07-31 against multiple
/// cross-referenced sources (not guessed -- money rounding/decimals is a
/// "never guess" area per plan section 1 rule 6). Only INR (falls
/// through to the 2-decimal default), JPY, and BHD are exercised by the
/// current vectors; the rest of this table is included for when other
/// currencies are ported, and should be spot-checked against
/// java.util.Currency (the Android port's source of truth, via
/// Money.kt's minorUnits) if a vector ever exercises one of them and
/// disagrees.
private let zeroDecimalCurrencies: Set<String> = [
    "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF",
    "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF",
]
private let threeDecimalCurrencies: Set<String> = [
    "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND",
]

/// Number of minor-unit decimal places for a currency (USD=2, JPY=0, BHD=3).
public func minorUnits(_ currency: String) -> Int {
    if zeroDecimalCurrencies.contains(currency) { return 0 }
    if threeDecimalCurrencies.contains(currency) { return 3 }
    return 2
}

/// Round half away from zero: 0.5 -> 1, -0.5 -> -1. Uses Swift's
/// standard-library `.toNearestOrAwayFromZero` rounding rule directly --
/// its documented tie-breaking behavior ("the value with greater
/// magnitude is chosen") is exactly round-half-away-from-zero, no
/// hand-rolled tie-breaking logic needed (contrast the Kotlin port,
/// which reaches for BigDecimal/RoundingMode.HALF_UP because
/// kotlin.math.round's own tie-breaking rule isn't the one we want).
private func roundHalfAwayFromZero(_ n: Double) -> Int64 {
    Int64(n.rounded(.toNearestOrAwayFromZero))
}

/// Construct Money from an already-minor-unit integer.
public func money(_ amount: Int64, _ currency: String) -> Money {
    Money(amount: amount, currency: currency)
}

/// Construct Money from an already-minor-unit value that might not be a
/// whole number (mirrors the TS source, where `amount` is a JS `number`
/// and money() runtime-checks `Number.isInteger`). Real callers should
/// prefer the Int64 overload above; this exists so the vector adapter
/// can reproduce the TS "throws on non-integer amount" vector without a
/// separate code path.
public func money(_ amount: Double, _ currency: String) throws -> Money {
    guard amount.isFinite, amount == amount.rounded(.towardZero) else {
        throw MoneyError(description: "Money.amount must be an integer minor-unit value, got \(formatJsNumber(amount))")
    }
    return Money(amount: Int64(amount), currency: currency)
}

/// Formats a Double the way JS's template-literal `${amount}` would
/// (e.g. 1.5 -> "1.5", whole numbers with no trailing ".0") -- needed
/// only to reproduce the exact error-message text a golden vector
/// asserts on.
private func formatJsNumber(_ n: Double) -> String {
    if n == n.rounded(.towardZero) {
        return String(Int64(n))
    }
    return String(n)
}

/// Construct Money from a human/major value (e.g. 12.34 USD -> 1234).
/// Never throws: roundHalfAwayFromZero always produces a whole number,
/// so this can always use the plain Int64 `money` overload above rather
/// than the throwing Double one, which exists only for the direct
/// non-integer-input vector case.
public func fromMajor(_ value: Double, _ currency: String) -> Money {
    let factor = pow(10.0, Double(minorUnits(currency)))
    return money(roundHalfAwayFromZero(value * factor), currency)
}

/// Major-unit number (e.g. 1234 cents -> 12.34). For display/formatting only.
public func toMajor(_ m: Money) -> Double {
    Double(m.amount) / pow(10.0, Double(minorUnits(m.currency)))
}

public func isZero(_ m: Money) -> Bool { m.amount == 0 }
public func isNegative(_ m: Money) -> Bool { m.amount < 0 }

private func assertSameCurrency(_ a: Money, _ b: Money) throws {
    if a.currency != b.currency { throw CurrencyMismatchError(a: a.currency, b: b.currency) }
}

public func add(_ a: Money, _ b: Money) throws -> Money {
    try assertSameCurrency(a, b)
    return money(a.amount + b.amount, a.currency)
}

public func subtract(_ a: Money, _ b: Money) throws -> Money {
    try assertSameCurrency(a, b)
    return money(a.amount - b.amount, a.currency)
}

public func negate(_ m: Money) -> Money { money(-m.amount, m.currency) }

/// Multiply by a scalar (e.g. a rate or quantity); rounds to whole minor units.
public func scale(_ m: Money, _ factor: Double) -> Money {
    money(roundHalfAwayFromZero(Double(m.amount) * factor), m.currency)
}

/// Sum a list; empty list requires an explicit currency.
public func sum(_ items: [Money], currency: String? = nil) throws -> Money {
    if items.isEmpty {
        guard let currency else {
            throw MoneyError(description: "sum() of empty list needs a currency")
        }
        // Int64(0), not the bare literal 0 -- an untyped integer literal is
        // ambiguous between the money(Int64,_) and money(Double,_) throws
        // overloads (both conform to ExpressibleByIntegerLiteral), which
        // Swift reports as "Ambiguous use of 'money'" -- a real error the
        // first xcodebuild attempt against this file surfaced.
        return money(Int64(0), currency)
    }
    var acc = items[0]
    for m in items.dropFirst() {
        acc = try add(acc, m)
    }
    return acc
}

/// Convert to another currency using an explicit rate (target per 1
/// source major). Returns Money in the target currency; the source is
/// unchanged. Rounds to the target currency's minor units.
public func convert(_ m: Money, to: String, rate: Double) throws -> Money {
    if m.currency == to { return m }
    guard rate > 0 else {
        throw MoneyError(description: "convert() needs a positive rate, got \(formatJsNumber(rate))")
    }
    let sourceMajor = toMajor(m)
    let targetMinorFactor = pow(10.0, Double(minorUnits(to)))
    return money(roundHalfAwayFromZero(sourceMajor * rate * targetMinorFactor), to)
}

/// Split a total into `parts` amounts that sum EXACTLY to the total
/// (largest-remainder distribution). Powers the transaction breakdown /
/// "+" sub-item builder so items always reconcile to the total.
public func split(_ total: Money, _ parts: Int) throws -> [Money] {
    guard parts > 0 else {
        throw MoneyError(description: "split() needs a positive integer count, got \(parts)")
    }
    let partsL = Int64(parts)
    let base = total.amount / partsL // Swift integer division truncates toward zero, matching Math.trunc.
    var remainder = total.amount - base * partsL
    let step: Int64 = remainder > 0 ? 1 : (remainder < 0 ? -1 : 1)
    remainder = abs(remainder)
    var out: [Money] = []
    for i in 0..<parts {
        let extra: Int64 = Int64(i) < remainder ? step : 0
        out.append(money(base + extra, total.currency))
    }
    return out
}

/// True when breakdown items sum exactly to the transaction total (invariant #5).
public func itemsReconcile(_ total: Money, _ items: [Money]) -> Bool {
    if items.isEmpty { return total.amount == 0 }
    // Any item in a different currency can never reconcile.
    if items.contains(where: { $0.currency != total.currency }) { return false }
    // sum() can't actually throw on this path (items is non-empty and
    // same-currency, per the guards above), but it's a `throws` function
    // and itemsReconcile isn't, so `try?` bridges that -- matches the TS
    // source, which also doesn't guard this call.
    guard let s = try? sum(items, currency: total.currency) else { return false }
    return s.amount == total.amount
}
