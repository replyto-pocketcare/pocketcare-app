import Foundation

/// Split display-collapse. Ported from apps/web/src/splits/collapse.ts.
///
/// A single split expense writes up to three private ledger rows for you —
/// `own_share` (real account), `lend` (transfer to the virtual "Owed to me"
/// account when you overpaid) and `borrow` (expense on the virtual "I owe"
/// account when you underpaid). Those rows are REQUIRED for correct balances
/// and are never removed. But in transaction *lists* they read as 2–3 separate
/// rows for one real-world event, which is confusing — so every posting of the
/// same expense collapses into ONE row, badged "Split".
///
/// The row shows the **total you paid** (own_share + lend); if you paid nothing,
/// it falls back to your share so the row isn't a meaningless zero.
///
/// Web keeps this in a React hook, so the query lives in `Data` and only the
/// arithmetic lives here — which is also what makes it vector-testable.
/// Mirrors apps/android/domain/.../splits/Collapse.kt.

/// One `expense_postings` row joined to its transaction — web's `Row`.
public struct SplitPosting: Sendable {
    public let transactionId: String
    public let expenseId: String
    public let role: String
    public let amountMinor: Int64
    public let currency: String
    public let groupId: String?

    public init(
        transactionId: String,
        expenseId: String,
        role: String,
        amountMinor: Int64,
        currency: String,
        groupId: String?
    ) {
        self.transactionId = transactionId
        self.expenseId = expenseId
        self.role = role
        self.amountMinor = amountMinor
        self.currency = currency
        self.groupId = groupId
    }
}

public struct SplitInfo: Equatable, Sendable {
    public let expenseId: String
    public let groupId: String?
    /// Amount shown on the collapsed row — total you actually paid.
    public let displayPaid: Int64
    /// Your share of the expense (what it cost you).
    public let yourShare: Int64
    /// You overpaid and are owed this back.
    public let owedToYou: Int64
    /// You underpaid and owe this.
    public let youOwe: Int64
    public let currency: String
}

/// Transaction id → its split expense info. Only split postings appear; a
/// transaction absent from the map is an ordinary row.
///
/// The currency and group id come from the FIRST posting seen for an expense,
/// which is web's behaviour (its aggregate seeds them once and never revisits).
/// Postings of one expense are written together and always share both.
public func splitInfoByTransaction(_ rows: [SplitPosting]) -> [String: SplitInfo] {
    struct Agg {
        var own: Int64 = 0
        var lend: Int64 = 0
        var borrow: Int64 = 0
        let currency: String
        let groupId: String?
        var txIds: [String] = []
    }

    // A parallel key array keeps expense order stable: Swift dictionaries have
    // no insertion order, and a vector compares serialised JSON.
    var order: [String] = []
    var byExpense: [String: Agg] = [:]
    for r in rows {
        if byExpense[r.expenseId] == nil {
            byExpense[r.expenseId] = Agg(currency: r.currency, groupId: r.groupId)
            order.append(r.expenseId)
        }
        switch r.role {
        case "own_share": byExpense[r.expenseId]!.own += r.amountMinor
        case "lend": byExpense[r.expenseId]!.lend += r.amountMinor
        case "borrow": byExpense[r.expenseId]!.borrow += r.amountMinor
        default: break
        }
        byExpense[r.expenseId]!.txIds.append(r.transactionId)
    }

    var out: [String: SplitInfo] = [:]
    for expenseId in order {
        guard let a = byExpense[expenseId] else { continue }
        let paid = a.own + a.lend
        let info = SplitInfo(
            expenseId: expenseId,
            groupId: a.groupId,
            displayPaid: paid > 0 ? paid : a.borrow,
            yourShare: a.own + a.borrow,
            owedToYou: a.lend,
            youOwe: a.borrow,
            currency: a.currency
        )
        for txId in a.txIds { out[txId] = info }
    }
    return out
}

/// The ids that survive collapse, in order: the first posting seen for each
/// split expense is kept, its siblings dropped. Non-split ids pass through.
///
/// Ids rather than web's generic `<T extends { id: string }>`: the caller
/// already has the rows and can look each one up, and a generic here would be
/// one more thing the golden vectors could not exercise directly.
public func collapseSplitRowIds(_ orderedIds: [String], _ infoByTx: [String: SplitInfo]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for id in orderedIds {
        guard let info = infoByTx[id] else {
            out.append(id)
            continue
        }
        if seen.contains(info.expenseId) { continue } // sibling of an already-shown split
        seen.insert(info.expenseId)
        out.append(id)
    }
    return out
}
