import Foundation

/// The Search screen's filter, ported from apps/web/app/search/page.tsx.
///
/// Web computes this inside a `useMemo` in the page component. It is a pure
/// function of (rows, criteria) with no React in it, so it lives here and is
/// vector-tested; the screen keeps only the criteria and the rendering.
/// Mirrors apps/android/domain/.../search/Search.kt.

/// Type filter chips, in web's order.
public let searchTypes = ["all", "income", "expense", "transfer"]

/// Web slices the filtered list to 300 before rendering.
public let searchResultLimit = 300

/// A transaction with its display names already resolved.
///
/// Web resolves them in the component (`catName`, `acct`, and the
/// `method_label` correlated subquery); doing it in the caller keeps this
/// function pure and keeps the joins in `Data` where the other queries live.
public struct SearchRow: Sendable {
    public let id: String
    public let type: String
    public let accountId: String
    public let toAccountId: String?
    public let occurredAt: String
    public let amountMinor: Int64
    public let currency: String
    public let labels: String?
    public let note: String?
    public let description: String?
    public let methodLabel: String?
    public let categoryName: String?
    public let accountName: String?
    public let accountType: String?

    public init(
        id: String, type: String, accountId: String, toAccountId: String?,
        occurredAt: String, amountMinor: Int64, currency: String,
        labels: String?, note: String?, description: String?, methodLabel: String?,
        categoryName: String?, accountName: String?, accountType: String?
    ) {
        self.id = id
        self.type = type
        self.accountId = accountId
        self.toAccountId = toAccountId
        self.occurredAt = occurredAt
        self.amountMinor = amountMinor
        self.currency = currency
        self.labels = labels
        self.note = note
        self.description = description
        self.methodLabel = methodLabel
        self.categoryName = categoryName
        self.accountName = accountName
        self.accountType = accountType
    }
}

public struct SearchCriteria: Equatable, Sendable {
    public var query: String
    public var type: String
    public var accountId: String
    /// `YYYY-MM-DD`, inclusive.
    public var from: String
    /// `YYYY-MM-DD`, inclusive.
    public var to: String
    /// Major units, as typed. Blank or unparseable means "no bound".
    public var min: String
    /// Major units, as typed. Blank or unparseable means "no bound".
    public var max: String

    public init(
        query: String = "", type: String = "all", accountId: String = "",
        from: String = "", to: String = "", min: String = "", max: String = ""
    ) {
        self.query = query
        self.type = type
        self.accountId = accountId
        self.from = from
        self.to = to
        self.min = min
        self.max = max
    }
}

/// How many filters are set — web shows this as "Filters · N".
public func activeFilterCount(_ c: SearchCriteria) -> Int {
    [
        c.type != "all",
        !c.accountId.isEmpty,
        !c.from.isEmpty,
        !c.to.isEmpty,
        !c.min.isEmpty,
        !c.max.isEmpty,
    ].filter { $0 }.count
}

/// Everything web's `hay` concatenates, lowercased, in web's order.
///
/// The amount is included so "499" finds a ₹499 charge. Web renders it as
/// `toMajor(money(...)).toFixed(2)` — a hardcoded two decimals, which is wrong
/// for JPY and KWD; this uses the currency's own minor-unit count. INR, USD and
/// EUR are unaffected, which is why web's version has survived.
private func haystack(_ r: SearchRow) -> String {
    let decimals = minorUnits(r.currency)
    let major = toMajor(money(r.amountMinor, r.currency))
    let amountText = String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), major)
    let parts: [String?] = [
        r.labels, r.note, r.description, r.type, r.methodLabel,
        r.categoryName, r.accountName, r.accountType, amountText,
    ]
    return parts.compactMap { ($0?.isEmpty ?? true) ? nil : $0 }.joined(separator: " ").lowercased()
}

/// The amount bound in the ROW's own currency.
///
/// Web writes `Math.round(Number(min) * 100)` — the same hardcoded ×100 the
/// de-hardcoding programme is removing everywhere else, and it compares that
/// against `Math.abs(t.amount)`, which is in the row's own minor units. So on
/// web a "500" bound means ¥50000 against a yen row. Converting per row with
/// `fromMajor` is what the comparison web is *trying* to make actually needs.
///
/// An unparseable bound returns nil and therefore filters nothing, matching
/// web: `Number("abc")` is NaN and every NaN comparison is false.
private func bound(_ text: String, _ currency: String) -> Int64? {
    guard !text.isEmpty, let value = Double(text), value.isFinite else { return nil }
    return fromMajor(value, currency).amount
}

/// Filters `rows` — which the caller supplies newest-first — and caps the
/// result at `searchResultLimit`, exactly as web's `useMemo` does.
public func searchTransactions(_ rows: [SearchRow], _ c: SearchCriteria) -> [SearchRow] {
    let term = c.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    var out: [SearchRow] = []
    out.reserveCapacity(Swift.min(rows.count, searchResultLimit))
    for r in rows {
        if c.type != "all" && r.type != c.type { continue }
        if !c.accountId.isEmpty && r.accountId != c.accountId && r.toAccountId != c.accountId { continue }
        let day = String(r.occurredAt.prefix(10))
        if !c.from.isEmpty && day < c.from { continue }
        if !c.to.isEmpty && day > c.to { continue }
        if let minA = bound(c.min, r.currency), abs(r.amountMinor) < minA { continue }
        if let maxA = bound(c.max, r.currency), abs(r.amountMinor) > maxA { continue }
        if !term.isEmpty && !haystack(r).contains(term) { continue }
        out.append(r)
        if out.count == searchResultLimit { break }
    }
    return out
}
