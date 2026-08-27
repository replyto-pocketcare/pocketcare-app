import Foundation

/**
 The per-item split screen's logic, lifted out of the screen.

 Ported from the two pure functions at the bottom of
 `apps/web/app/receipts/split/page.tsx` (`weightFor`, `validateLine`) plus the
 mode lists and the two text helpers from `src/receipts/draft.ts` that only that
 screen uses.

 They are here, not in the view models, because they are the part that decides
 whether a bill is allowed to be written at all — "shares are off by ₹0.01" has
 to mean the same thing on three clients, and it is the exact sort of arithmetic
 that quietly drifts when it lives in a UI file twice.

 Validation returns a SHAPE, not a sentence: ``LineProblem`` carries the numbers
 and the UI formats them through its own i18n. Same rule as `timeAgo`.

 Mirrors Android's SplitAssign.kt exactly.
 */

/// Modes offered for goods. `quantity` only appears when there is a quantity.
public let itemSplitModesForItems: [String] = ["equal", "quantity", "exact", "percent"]

/// Modes offered for tax / service charge / tip / discount.
public let itemSplitModesForCharges: [String] = ["proportional", "equal", "exact", "percent"]

/// Which modes this line may be divided by.
public func splitModesFor(_ line: ReceiptLine) -> [String] {
    if isCharge(line.kind) { return itemSplitModesForCharges }
    return itemSplitModesForItems.filter { $0 != "quantity" || (line.quantity ?? 0) > 0 }
}

/// Milli-units back to a plain count: 1500 → 1.5.
public func qtyToMajor(_ milli: Int64) -> Double { Double(milli) / Double(RECEIPT_QTY_SCALE) }

/// Minor-unit decimal places for a currency, defaulting to 2.
///
/// Web wraps `minorUnits` in a try/catch here because its `Intl` path throws on
/// an unknown code; both native ports already default to 2 internally, so this
/// is a rename rather than a behaviour change — kept as its own name so the
/// screen reads the same on all three.
public func receiptDigits(_ currency: String) -> Int { minorUnits(currency) }

/// `"12.34"` → `1234`. Blank or garbage becomes 0 rather than NaN.
///
/// A comma is accepted as a decimal separator, which is web's behaviour and is
/// deliberate: the on-screen keypad in several locales offers a comma.
public func minorFromText(_ value: String, _ digits: Int) -> Int64 {
    guard let n = jsParseFloat(value.replacingOccurrences(of: ",", with: ".")) else { return 0 }
    // jsMathRound, not `.rounded()`: JS breaks ties toward +Infinity and Swift's
    // default breaks them away from zero, which disagree on every negative half.
    return Int64(jsMathRound(n * pow10(digits)))
}

/// `1234` → `"12.34"`, for populating an editable input.
public func majorTextFromMinor(_ minor: Int64, _ digits: Int) -> String {
    // A POSIX locale, or a comma-decimal locale turns "12.34" into "12,34" and
    // the text goes back through `minorFromText` as a different number.
    String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), Double(minor) / pow10(digits))
}

private func pow10(_ digits: Int) -> Double {
    var out = 1.0
    for _ in 0..<max(0, digits) { out *= 10 }
    return out
}

/// Translate a raw input string into the weight the allocator expects.
///
/// `nil` means "this mode carries no weight" (equal / proportional), which is
/// what `allocateReceipt` reads as "divide it yourself".
public func lineWeight(mode: String, raw: String?, lineAmount: Int64, digits: Int) -> Double? {
    if mode == "equal" || mode == "proportional" { return nil }
    guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
    if mode == "exact" {
        // Exact weights are minor units and must carry the line's SIGN, so a
        // discount can be split exactly too.
        let v = minorFromText(raw, digits)
        return lineAmount < 0 ? -Double(abs(v)) : Double(v)
    }
    guard let n = jsParseFloat(raw.replacingOccurrences(of: ",", with: ".")), n.isFinite, n >= 0 else { return 0 }
    return mode == "percent"
        ? jsMathRound(n * Double(RECEIPT_PERCENT_SCALE))
        : jsMathRound(n * Double(RECEIPT_QTY_SCALE))
}

/// Why one line cannot be saved, or nil when it is fine.
///
/// Carries numbers, not sentences — see this file's header.
public enum LineProblem: Equatable, Sendable {
    /// Nobody is on this line.
    case needsSomeone
    /// Exact shares do not sum to the line total; the value is what is left over.
    case exactMismatch(diffMinor: Int64)
    /// Percentages do not sum to 100; the value is what they DO sum to, rounded.
    case percentMismatch(pct: Int)
    /// Quantities do not sum to the line's quantity. Both are milli-units.
    case quantityMismatch(gotMilli: Int64, wantMilli: Int64)
}

/// Validate one line's assignment. `nil` means it is ready to save.
public func validateSplitLine(
    line: ReceiptLine,
    mode: String,
    members: [String],
    weights: [String: String],
    digits: Int
) -> LineProblem? {
    if members.isEmpty { return .needsSomeone }

    if mode == "exact" {
        var sum: Int64 = 0
        for uid in members {
            let v = minorFromText(weights[uid] ?? "", digits)
            sum += line.amount < 0 ? -abs(v) : v
        }
        if sum != line.amount { return .exactMismatch(diffMinor: line.amount - sum) }
    }

    if mode == "percent" {
        var sum = 0.0
        for uid in members {
            sum += jsParseFloat((weights[uid] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        let pct = Int(jsMathRound(sum))
        if pct != 100 { return .percentMismatch(pct: pct) }
    }

    if mode == "quantity", let quantity = line.quantity {
        var sum = 0.0
        for uid in members {
            sum += jsParseFloat((weights[uid] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        let gotMilli = Int64(jsMathRound(sum * Double(RECEIPT_QTY_SCALE)))
        if gotMilli != quantity { return .quantityMismatch(gotMilli: gotMilli, wantMilli: quantity) }
    }

    return nil
}
