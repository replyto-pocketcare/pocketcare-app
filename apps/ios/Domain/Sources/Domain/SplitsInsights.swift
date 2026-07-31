import Foundation

// Ported from packages/core/splits-insights/src/index.ts (P1.4b). Mirrors
// apps/android/domain/.../splitsinsights/SplitsInsights.kt (P1.4a)
// field-for-field. Correctness is judged against
// tools/golden-vectors/vectors/splits-insights.json -- see
// docs/plans/native-mobile-apps.md section 5 and CLAUDE.md golden rule 8
// ("web is the spec"). Every field here is a plain JSON number/string/bool
// -- this domain's exported vectors never wrap results with a money-string
// convention, confirmed by reading the actual generated vector file.

/// Parses an ISO date/instant string to epoch milliseconds, matching JS's
/// `new Date(string).getTime()` for the two exact forms this domain's
/// vectors use: date-only ("2026-01-01", which ECMA-262's Date Time String
/// Format treats as UTC midnight) and a full UTC instant
/// ("2026-01-01T00:00:00Z"). `ISO8601DateFormatter` parsing a "Z"-suffixed
/// string has no timezone ambiguity to worry about (unlike Budget.swift's
/// Calendar-arithmetic concerns) -- the string specifies UTC explicitly and
/// `Date` itself is timezone-agnostic absolute-time storage, so this is a
/// much lower-risk use of Foundation than `Calendar.date(byAdding:)`.
///
/// A fresh formatter is created per call rather than shared as a global --
/// a real Swift 6 build error ("not concurrency-safe because non-Sendable
/// type 'ISO8601DateFormatter' may have shared mutable state") rejected a
/// single cached instance. `nonisolated(unsafe)` (the fix used for
/// FunctionRegistry.impls) would have silenced the compiler, but this is
/// production domain code, not test-only infra -- it can genuinely be
/// called from concurrent Swift Tasks in the real app, and
/// ISO8601DateFormatter's own thread-safety for concurrent reads isn't
/// documented as guaranteed. Allocating per call sidesteps the question
/// entirely rather than asserting an unverified safety claim; this
/// function isn't a hot loop (per-expense insight computation, not a
/// tight numeric kernel), so the allocation cost doesn't matter here.
private func parseIsoMillis(_ iso: String) -> Double {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let normalized = iso.count == 10 ? iso + "T00:00:00Z" : iso
    guard let date = formatter.date(from: normalized) else {
        fatalError("unparseable ISO date: \(iso)")
    }
    return date.timeIntervalSince1970 * 1000
}

private let dayMs = 86_400_000.0

func daysBetween(_ fromIso: String, _ toIso: String) -> Double {
    (parseIsoMillis(toIso) - parseIsoMillis(fromIso)) / dayMs
}

public struct DebtLike {
    public let at: String
    public let amount: Int64
    public init(at: String, amount: Int64) {
        self.at = at
        self.amount = amount
    }
}

public struct PaymentLike {
    public let at: String
    public let amount: Int64
    public init(at: String, amount: Int64) {
        self.at = at
        self.amount = amount
    }
}

public struct AverageSettleResult: Equatable {
    public let avgDays: Double?
    public let clearedCount: Int
}

private final class QueuedDebt {
    let at: String
    var left: Int64
    init(at: String, left: Int64) {
        self.at = at
        self.left = left
    }
}

/// FIFO age-of-debt at settlement -- see the TS source's own doc comment
/// for the "why" (weighted by chunk size; a prepayment before any debt
/// exists is ignored, not counted as negative-age).
public func averageSettleDays(_ debts: [DebtLike], _ payments: [PaymentLike]) -> AverageSettleResult {
    let queue = debts.filter { $0.amount > 0 }.sorted { $0.at < $1.at }.map { QueuedDebt(at: $0.at, left: $0.amount) }
    let pays = payments.filter { $0.amount > 0 }.sorted { $0.at < $1.at }

    var weighted = 0.0
    var weight = 0.0
    var cleared = 0
    var head = 0

    for pay in pays {
        var remaining = pay.amount
        while remaining > 0 && head < queue.count {
            let debt = queue[head]
            // Debts incurred after this payment can't have been cleared by it.
            if debt.at > pay.at { break }
            let chunk = min(remaining, debt.left)
            let age = max(0, daysBetween(debt.at, pay.at))
            weighted += age * Double(chunk)
            weight += Double(chunk)
            debt.left -= chunk
            remaining -= chunk
            if debt.left == 0 {
                cleared += 1
                head += 1
            }
        }
    }

    return AverageSettleResult(avgDays: weight > 0 ? weighted / weight : nil, clearedCount: cleared)
}

public struct FriendEdge {
    public let friendId: String
    public let groupId: String
    public let at: String
    public let amount: Int64
    public init(friendId: String, groupId: String, at: String, amount: Int64) {
        self.friendId = friendId
        self.groupId = groupId
        self.at = at
        self.amount = amount
    }
}

public struct FriendSettlement {
    public let friendId: String
    public let at: String
    public let amount: Int64
    public init(friendId: String, at: String, amount: Int64) {
        self.friendId = friendId
        self.at = at
        self.amount = amount
    }
}

public struct Contribution {
    public let userId: String
    public let paid: Int64
    public let share: Int64
    public init(userId: String, paid: Int64, share: Int64) {
        self.userId = userId
        self.paid = paid
        self.share = share
    }
}

public final class FriendStats {
    public let friendId: String
    public var net: Int64 = 0
    public var youCovered: Int64 = 0
    public var theyCovered: Int64 = 0
    public var lent: Int64 = 0
    public var borrowed: Int64 = 0
    public var groups: Int = 0
    public var groupsOwing: Int = 0
    public var groupsOwed: Int = 0
    public var expenses: Int = 0
    public var avgSettleDays: Double?
    public var settledDebts: Int = 0

    // Single initializer, not two -- friendId-only and a fuller
    // all-other-fields-defaulted version would be ambiguous at any call
    // site that only passes friendId (Swift can't tell which one you
    // meant), the same class of "ambiguous use of" bug as Money.swift's
    // sum() overload issue. This one covers both: computeFriendStats's
    // ensure() calls it with just friendId; the vector adapter's
    // "stats" parser calls it with every field.
    public init(
        friendId: String, net: Int64 = 0, youCovered: Int64 = 0, theyCovered: Int64 = 0,
        lent: Int64 = 0, borrowed: Int64 = 0, groups: Int = 0, groupsOwing: Int = 0,
        groupsOwed: Int = 0, expenses: Int = 0, avgSettleDays: Double? = nil, settledDebts: Int = 0
    ) {
        self.friendId = friendId
        self.net = net
        self.youCovered = youCovered
        self.theyCovered = theyCovered
        self.lent = lent
        self.borrowed = borrowed
        self.groups = groups
        self.groupsOwing = groupsOwing
        self.groupsOwed = groupsOwed
        self.expenses = expenses
        self.avgSettleDays = avgSettleDays
        self.settledDebts = settledDebts
    }
}

/// Per-friend rollup. Friends with no shared history are omitted.
public func computeFriendStats(
    _ edges: [FriendEdge],
    _ settlements: [FriendSettlement],
    _ contributions: [String: [Contribution]]? = nil
) -> [FriendStats] {
    // order + byFriend together stand in for JS's Map, which iterates in
    // insertion order -- Swift's Dictionary has no ordering guarantee, so
    // insertion order is tracked explicitly rather than assumed.
    var order: [String] = []
    var byFriend: [String: FriendStats] = [:]
    var perGroup: [String: [String: Int64]] = [:]

    func ensure(_ friendId: String) -> FriendStats {
        if let existing = byFriend[friendId] { return existing }
        let s = FriendStats(friendId: friendId)
        byFriend[friendId] = s
        perGroup[friendId] = [:]
        order.append(friendId)
        return s
    }

    for e in edges {
        let s = ensure(e.friendId)
        s.net += e.amount
        s.expenses += 1
        if e.amount > 0 { s.youCovered += e.amount } else if e.amount < 0 { s.theyCovered += -e.amount }
        perGroup[e.friendId, default: [:]][e.groupId, default: 0] += e.amount
    }

    for st in settlements {
        let s = ensure(st.friendId)
        // They paid you -> reduces what they owe. You paid them -> reduces what you owe.
        s.net -= st.amount
    }

    for friendId in order {
        let s = byFriend[friendId]!
        let g = perGroup[friendId] ?? [:]
        s.groups = g.count
        for net in g.values {
            if net > 0 { s.groupsOwing += 1 } else if net < 0 { s.groupsOwed += 1 }
        }

        let debts = edges.filter { $0.friendId == friendId && $0.amount > 0 }.map { DebtLike(at: $0.at, amount: $0.amount) }
        let pays = settlements.filter { $0.friendId == friendId && $0.amount > 0 }.map { PaymentLike(at: $0.at, amount: $0.amount) }
        let result = averageSettleDays(debts, pays)
        s.avgSettleDays = result.avgDays
        s.settledDebts = result.clearedCount

        for c in contributions?[friendId] ?? [] {
            let delta = c.paid - c.share
            if delta > 0 { s.lent += delta } else if delta < 0 { s.borrowed += -delta }
        }
    }

    return order.map { byFriend[$0]! }
}

public struct FriendInsight: Equatable {
    public let key: String
    public let friendId: String
    public let value: Double
    public let evidence: Int
}

/// Minimum evidence before a ranking is asserted at all.
public enum Thresholds {
    public static let consistentGroups = 2
    public static let settledDebts = 2
    public static let minAmount = 100
}

private func best<T>(_ xs: [T], _ score: (T) -> Double) -> T? {
    var top: T?
    var topScore = -Double.infinity
    for x in xs {
        let s = score(x)
        if s > topScore {
            topScore = s
            top = x
        }
    }
    return top
}

/// Pick the headline insights. Returns only what the data actually
/// supports -- an empty array is a valid, honest answer for a thin ledger.
public func pickFriendInsights(_ stats: [FriendStats]) -> [FriendInsight] {
    var out: [FriendInsight] = []
    func push(_ key: String, _ s: FriendStats?, _ value: Double, _ evidence: Int) {
        if let s, value >= Double(Thresholds.minAmount) {
            out.append(FriendInsight(key: key, friendId: s.friendId, value: value, evidence: evidence))
        }
    }

    let lender = best(stats.filter { $0.lent > 0 }) { Double($0.lent) }
    push("biggest_lender", lender, Double(lender?.lent ?? 0), lender?.expenses ?? 0)

    let owesYou = best(stats.filter { $0.net > 0 }) { Double($0.net) }
    push("owes_you_most", owesYou, Double(owesYou?.net ?? 0), owesYou?.expenses ?? 0)

    let youOwe = best(stats.filter { $0.net < 0 }) { -Double($0.net) }
    push("you_owe_most", youOwe, youOwe != nil ? -Double(youOwe!.net) : 0, youOwe?.expenses ?? 0)

    // "Always" means exactly that: every shared group lands the same way,
    // across at least consistentGroups of them. One-sided by construction.
    let alwaysOwes = best(stats.filter { $0.groupsOwing >= Thresholds.consistentGroups && $0.groupsOwed == 0 }) { Double($0.groupsOwing) }
    if let alwaysOwes {
        out.append(FriendInsight(key: "always_owes", friendId: alwaysOwes.friendId, value: Double(alwaysOwes.groupsOwing), evidence: alwaysOwes.groups))
    }

    let alwaysOwed = best(stats.filter { $0.groupsOwed >= Thresholds.consistentGroups && $0.groupsOwing == 0 }) { Double($0.groupsOwed) }
    if let alwaysOwed {
        out.append(FriendInsight(key: "always_owed", friendId: alwaysOwed.friendId, value: Double(alwaysOwed.groupsOwed), evidence: alwaysOwed.groups))
    }

    let settlers = stats.filter { $0.avgSettleDays != nil && $0.settledDebts >= Thresholds.settledDebts }
    if settlers.count >= 2 {
        let fastest = best(settlers) { -($0.avgSettleDays!) }
        let slowest = best(settlers) { $0.avgSettleDays! }
        // Only worth saying when they're actually different people.
        if let fastest, let slowest, fastest.friendId != slowest.friendId {
            out.append(FriendInsight(key: "fastest_settler", friendId: fastest.friendId, value: fastest.avgSettleDays!, evidence: fastest.settledDebts))
            out.append(FriendInsight(key: "slowest_settler", friendId: slowest.friendId, value: slowest.avgSettleDays!, evidence: slowest.settledDebts))
        }
    }

    return out
}
