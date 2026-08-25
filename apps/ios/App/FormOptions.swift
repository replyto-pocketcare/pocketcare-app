import Foundation

// GENERATED FILE — do not hand-edit.
// Source: packages/core/catalog/src/index.ts
// Regenerate with: node tools/parity/generate-options.mjs

/**
 The option lists every form offers.

 These are *offered* options, not the currencies the app can handle: the money
 layer knows the minor units of every ISO 4217 code, and an account synced in a
 currency absent from this list still formats correctly. This is only what a
 picker shows.
 */
public enum FormOptions {
    public static let currencies = ["INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED"]

    /**
     The fallback when nothing else is known — a fresh install, or a row whose
     currency column is null. The ONLY place a currency literal belongs;
     everywhere else reads the user's base-currency setting.
     */
    public static let defaultCurrency = "INR"

    public static let periods = ["daily", "weekly", "monthly", "yearly"]

    public static let accountTypes = ["savings", "current", "credit_card", "cash", "mutual_funds", "stocks", "demat"]

    /// Accounts that only RECORD investments — they hold holdings, not
    /// spendable money. Every picker that moves real money filters these out.
    public static let investmentAccountTypes = ["demat", "stocks", "mutual_funds"]

    /// True when the type is an investment account. Mirrors web isInvestmentAccount.
    public static func isInvestmentAccount(_ type: String?) -> Bool {
        guard let type, !type.isEmpty else { return false }
        return investmentAccountTypes.contains(type)
    }

    /**
     Hex, not `Color`: this is what gets written to `accounts.color`, so all
     three apps must agree on the string. Converted at the point of use.
     */
    public static let accountColors = ["#3e4a38", "#5f6647", "#6b7a4f", "#9cae8e", "#b06a4f", "#c98a72", "#a8503a", "#7c4a3a", "#5f4636", "#c9b79c", "#c08a3e", "#4f46e5", "#6d5acf", "#3f5a8a", "#2f6f6a", "#7a4a6b", "#4b5563", "#2b2723"]

    public static let defaultAccountColor = accountColors[0]

    /// Insights' multi-series palette — web's INSIGHT_PALETTE.
    public static let chartColors = ["#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#7c7264", "#5f6647"]

    /// The dashboard tiles' palette — web's PIE. NOT the same list.
    public static let dashboardChartColors = ["#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#4f46e5", "#7c7264"]

    public static let fallbackAccountColor = "#7c7264"

    /// `value` is what is stored. `label` is English and NOT yet translated —
    /// there are no `gender.*` keys in the i18n on any platform. See the note
    /// in packages/core/catalog.
    public struct Option: Identifiable, Sendable {
        public let value: String
        public let label: String
        public var id: String { value }
    }

    public static let genders: [Option] = [
        Option(value: "", label: "Not specified"),
        Option(value: "female", label: "Female"),
        Option(value: "male", label: "Male"),
        Option(value: "non-binary", label: "Non-binary"),
        Option(value: "prefer not to say", label: "Prefer not to say"),
    ]

    public static let countries = ["", "IN", "US", "GB", "CA", "AU", "SG", "AE", "DE", "FR", "NL", "JP", "BR", "ZA", "NG", "KE", "Other"]

    /**
     A stable colour for an id, when none was chosen.

     Deterministic so the same account is the same colour on every device and in
     every session. Ported with the palette rather than re-implemented, because
     a platform that re-derived the hash would disagree with web about a colour
     the user has already seen.
     */
    public static func colorForId(_ id: String?, fallback: String = fallbackAccountColor) -> String {
        guard let id, !id.isEmpty else { return fallback }
        // `utf16`, not `unicodeScalars`: the source is JavaScript's
        // `charCodeAt`, which yields UTF-16 code UNITS. Scalars would agree on
        // everything in the BMP and silently diverge on an emoji — and account
        // ids are user-supplied often enough for that to matter one day.
        var h: UInt32 = 0
        for unit in id.utf16 {
            h = h &* 31 &+ UInt32(unit)
        }
        return accountColors[Int(h % UInt32(accountColors.count))]
    }
}
