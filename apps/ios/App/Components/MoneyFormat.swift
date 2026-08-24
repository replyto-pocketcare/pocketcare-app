import Foundation
import Domain

/**
 The one money formatter.

 Before this file there were four, and every one of them was wrong in a
 different way:

 - `formatMoneyAware` (SettingsView.swift) masked correctly but hardcoded
   `"₹%.2f"`, so every non-INR amount rendered with a rupee sign.
 - `formatMoney` (LoansViewModel.swift) divided by 100, forced `en_IN`, and
   showed zero fraction digits.
 - `formatMoney` (ReceiptReviewView.swift) divided by 100 with two fraction
   digits — and, being a second module-scope declaration of the same name,
   was a hard compile error.
 - `formatCents` (DashboardView.swift) divided by 100 and hardcoded INR.

 Three of the four ignored the hide-amounts setting entirely, which is the
 privacy leak class that has already shipped on web three times (PARITY_AUDIT.md
 trap 7), and all four hardcoded ÷100, which is wrong for JPY (no minor unit)
 and BHD (three) and contradicts golden rule 1.

 Everything now goes through `Domain.format`, which is generated from
 `packages/core/money` and takes its fraction digits from `minorUnits(currency)`
 and its grouping from the currency's own locale.
 */

/// Mask shown in place of an amount when hide-amounts is on. Matches web's
/// `useMoneyFmt` default.
public let moneyMask = "••••"

/// Whether amounts are currently hidden, readable from any isolation context.
///
/// `Prefs` is `@MainActor` because it is an `ObservableObject` driving SwiftUI,
/// but some formatting happens in `@Sendable` closures with no actor at all —
/// the insight generators hand a plain formatter closure to domain code. Making
/// the formatter `@MainActor` would put those call sites permanently out of
/// reach of the masking rule, which is exactly how an amount leaks. Reading the
/// same UserDefaults key directly is thread-safe and needs no isolation, so
/// there is one setting with one meaning and no context where it cannot be
/// honoured.
public func amountsHiddenNow() -> Bool {
    UserDefaults.standard.bool(forKey: Prefs.hideKey)
}

/// Format a `Money`, respecting the hide-amounts privacy setting.
///
/// This is the native `useMoneyFmt()`. Use it for every amount that reaches the
/// screen — including inside charts, which is where web's leaks happened.
public func formatMoneyAware(_ money: Domain.Money, mask: String = moneyMask) -> String {
    amountsHiddenNow() ? mask : Domain.format(money)
}

/// Convenience for the common `(minorUnits, currencyCode)` call shape.
public func formatMoney(_ minor: Int64, _ currency: String, mask: String = moneyMask) -> String {
    formatMoneyAware(Domain.money(minor, currency), mask: mask)
}

/// Format without masking — for the rare place an amount must always be
/// legible, such as the confirmation text of a destructive action the user has
/// deliberately opened. Call sites should be few and obvious.
public func formatMoneyUnmasked(_ money: Domain.Money) -> String {
    Domain.format(money)
}

/// The user's base currency, readable without isolation — same reasoning as
/// `amountsHiddenNow()`.
public func baseCurrencyNow() -> String {
    UserDefaults.standard.string(forKey: Prefs.currencyKey) ?? FormOptions.defaultCurrency
}

/// A bare, ungrouped major-unit number for an EDITABLE field — "1200", or
/// "1200.5" when there is a fraction. Never masked: it is what the user is
/// typing, not something being shown to them.
///
/// Four identical private copies of this existed, all dividing by 100. The
/// divisor now comes from `minorUnits(currency)`, so a JPY amount is not
/// silently divided by a hundred.
public func formatMajorPlain(_ minor: Int64, currency: String = baseCurrencyNow()) -> String {
    let digits = Domain.minorUnits(currency)
    let major = Double(minor) / pow(10.0, Double(digits))
    return major == major.rounded() ? String(Int64(major)) : String(major)
}

/// Abbreviated amount for tight spaces — ₹1.5L / ₹2.3Cr for Indian-numbering
/// currencies, $1.2K / $3.4M otherwise. Masked like any other displayed amount.
///
/// Web renders these through `Intl.NumberFormat`'s `notation: "compact"`, whose
/// exact breakpoints are not reproducible here; the spec accepts the drift.
public func compactMoney(_ minor: Int64, _ currency: String) -> String {
    if amountsHiddenNow() { return moneyMask }
    let digits = Domain.minorUnits(currency)
    let major = Double(minor) / pow(10.0, Double(digits))
    let magnitude = abs(major)
    let indian = ["INR", "PKR", "LKR", "BDT", "NPR"].contains(currency.uppercased())

    let (value, suffix): (Double, String)
    if indian, magnitude >= 10_000_000 { (value, suffix) = (major / 10_000_000, "Cr") }
    else if indian, magnitude >= 100_000 { (value, suffix) = (major / 100_000, "L") }
    else if !indian, magnitude >= 1_000_000_000 { (value, suffix) = (major / 1_000_000_000, "B") }
    else if !indian, magnitude >= 1_000_000 { (value, suffix) = (major / 1_000_000, "M") }
    else if magnitude >= 1_000 { (value, suffix) = (major / 1_000, "K") }
    else { return Domain.format(Domain.money(minor, currency)) }

    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.locale = Locale(identifier: currencyLocales[currency] ?? "en_US")
    formatter.maximumFractionDigits = abs(value) >= 100 ? 0 : 1
    let body = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    return body + suffix
}
