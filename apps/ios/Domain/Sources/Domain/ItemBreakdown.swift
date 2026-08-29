import Foundation

/// The per-item view of an itemised bill. Ported from the render-time
/// arithmetic in apps/web/src/splits/ItemBreakdown.tsx.
///
/// Read-only by design, exactly as web is: editing a split after the fact means
/// rewriting ledger postings, which is the edit-transaction flow's job. This
/// answers "why do I owe this much?", which is the question people actually ask
/// after a group dinner — and the one nobody could ask on either phone, because
/// `expense_items` had no UI at all.
///
/// The balances are NOT computed from these numbers. `expense_participants` is
/// still the only thing any balance reads; item shares are a BREAKDOWN that
/// already rolled up into it when the bill was written (see
/// `createSplitExpenseItemized`). Nothing here can move what anybody owes.
///
/// Web keeps this inside a React component, so only the arithmetic lives here —
/// which is also what makes it vector-testable.
/// Mirrors apps/android/domain/.../splits/ItemBreakdown.kt.

/// One `expense_items` row, reduced to what the arithmetic reads.
public struct ItemBreakdownItem: Equatable, Sendable {
    public let id: String
    public let amount: Int64

    public init(id: String, amount: Int64) {
        self.id = id
        self.amount = amount
    }
}

/// One `expense_item_shares` row: what `userId` is on the hook for on `itemId`.
public struct ItemBreakdownShare: Equatable, Sendable {
    public let itemId: String
    public let userId: String
    public let shareAmount: Int64

    public init(itemId: String, userId: String, shareAmount: Int64) {
        self.itemId = itemId
        self.userId = userId
        self.shareAmount = shareAmount
    }
}

/// A single person's slice of one line, for the row's caption.
public struct ItemBreakdownLineShare: Equatable, Sendable {
    public let userId: String
    public let amount: Int64

    public init(userId: String, amount: Int64) {
        self.userId = userId
        self.amount = amount
    }
}

public struct ItemBreakdownLine: Equatable, Sendable {
    public let itemId: String
    /// The number shown on the right: one person's slice when filtered, the
    /// whole line when not.
    public let amount: Int64
    /// Who is on this line, zero slices dropped. EMPTY while a person filter is
    /// on — web hides the caption then, because "Ana ₹120 · Bo ₹80" under a row
    /// that already says "Ana" is noise.
    public let shares: [ItemBreakdownLineShare]

    public init(itemId: String, amount: Int64, shares: [ItemBreakdownLineShare]) {
        self.itemId = itemId
        self.amount = amount
        self.shares = shares
    }
}

public struct ItemBreakdownView: Equatable, Sendable {
    /// Everyone with a slice of anything, for the filter chips.
    public let everyone: [String]
    public let lines: [ItemBreakdownLine]
    /// The sum of what is actually shown — the filtered person's total, or the
    /// bill's.
    public let total: Int64

    public init(everyone: [String], lines: [ItemBreakdownLine], total: Int64) {
        self.everyone = everyone
        self.lines = lines
        self.total = total
    }
}

/**
 `items` in `sort` order and `shares` in query order, both as the repository read
 them, plus the person the chips have selected (nil or "" = everyone).

 Ordering is load-bearing and is taken from the ROW ORDER, not re-sorted: web
 builds two nested JS Maps out of the same rows and reads their insertion order
 straight back out for the chip row and every caption. A hash-ordered dictionary
 here would give the two clients different chip orders for the same bill — which
 is why the per-item slices are kept as an ordered array of keys alongside the
 dictionary rather than iterating the dictionary itself.
 */
public func itemBreakdown(
    items: [ItemBreakdownItem],
    shares: [ItemBreakdownShare],
    filterUserId: String?
) -> ItemBreakdownView {
    var byItem: [String: [String: Int64]] = [:]
    var itemOrder: [String] = []
    var userOrder: [String: [String]] = [:]
    for share in shares {
        if byItem[share.itemId] == nil {
            byItem[share.itemId] = [:]
            itemOrder.append(share.itemId)
            userOrder[share.itemId] = []
        }
        if byItem[share.itemId]?[share.userId] == nil {
            userOrder[share.itemId]?.append(share.userId)
        }
        byItem[share.itemId]?[share.userId] = share.shareAmount
    }

    var everyone: [String] = []
    var seen = Set<String>()
    for itemId in itemOrder {
        for userId in userOrder[itemId] ?? [] {
            if seen.contains(userId) { continue }
            seen.insert(userId)
            everyone.append(userId)
        }
    }

    // Web's filter state is a String whose empty value means "everyone", so an
    // empty id has to mean the same here — otherwise the "Everyone" chip would
    // filter for a user whose id is "" and show nothing.
    let filter: String? = (filterUserId?.isEmpty ?? true) ? nil : filterUserId

    // A line where the filtered person owes nothing is not their line at all.
    let visible: [ItemBreakdownItem]
    if let filter {
        visible = items.filter { (byItem[$0.id]?[filter] ?? 0) != 0 }
    } else {
        visible = items
    }

    let lines: [ItemBreakdownLine] = visible.map { item in
        let perUser = byItem[item.id] ?? [:]
        return ItemBreakdownLine(
            itemId: item.id,
            amount: filter.map { perUser[$0] ?? 0 } ?? item.amount,
            shares: filter == nil
                ? (userOrder[item.id] ?? []).compactMap { userId in
                    let amount = perUser[userId] ?? 0
                    return amount == 0 ? nil : ItemBreakdownLineShare(userId: userId, amount: amount)
                }
                : []
        )
    }

    return ItemBreakdownView(
        everyone: everyone,
        lines: lines,
        total: lines.reduce(Int64(0)) { $0 + $1.amount }
    )
}
