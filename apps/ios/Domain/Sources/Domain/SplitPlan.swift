import Foundation

/**
 The split editor on Add transaction, as arithmetic.

 Ported from the `splitPlan` useMemo in `apps/web/app/transactions/new/page.tsx`
 — the single largest block of web behaviour that was missing from both native
 ports, and the one that cascades: without it there is no "paid for someone
 else", no auto-split trip, no `?split=` entry, and Edit's SplitBanner has
 nothing to explain.

 It is here rather than in two screens because it is entirely rules and the
 rules decide money. What each person owes, whether the numbers add up, and
 whether Save is allowed at all are computed once and pinned by vectors.

 **One deliberate divergence from web, and it is the ×100 again.** Web's
 `toMinor` is `Math.round(Number(v) * 100)`, the same hardcoded constant the
 de-hardcoding programme is removing everywhere else. Here it is worse than
 cosmetic: an exact-mode split of a ¥3000 dinner would read every typed share as
 a hundredth of itself and refuse to balance, so the user could not save at all.
 This uses `fromMajor(major, currency)`. For INR, USD and EUR the two are
 byte-identical; for JPY they differ, and a vector pins the difference.

 Mirrors Android's SplitPlan.kt.
 */

/// Web's `SplitMode`. The strings are the values written to the database.
public enum SplitModes {
    public static let equal = "equal"
    public static let exact = "exact"
    public static let percent = "percent"
}

/// One participant, as `createSplitExpense` wants them.
public struct SplitParticipantPlan: Equatable, Sendable {
    public let userId: String
    /// Percent in percent mode, minor units in exact mode, nil when equal.
    public let value: Double?

    public init(userId: String, value: Double?) {
        self.userId = userId
        self.value = value
    }
}

/// One payer, as `createSplitExpense` wants them.
public struct SplitPayerPlan: Equatable, Sendable {
    public let userId: String
    public let paidMinor: Int64
    /// True for the current user — only their leg carries an account.
    public let isMe: Bool

    public init(userId: String, paidMinor: Int64, isMe: Bool) {
        self.userId = userId
        self.paidMinor = paidMinor
        self.isMe = isMe
    }
}

/// Everything the editor state implies.
public struct SplitPlan: Equatable, Sendable {
    /// Per-participant share, in `memberIds` order.
    public let shares: [Int64]
    public let sharesSum: Int64
    /// The typed percentages, summed. Only meaningful in percent mode.
    public let percentSum: Double
    public let paidSum: Int64
    /// Whether Save may proceed.
    public let valid: Bool
    public let participants: [SplitParticipantPlan]
    /// Payers with a non-zero amount. Web drops the zero legs before writing.
    public let payers: [SplitPayerPlan]
}

/**
 Compute the plan.

 `shareText` and `paidText` are the RAW field contents, keyed by user id,
 because that is what the user typed and rounding them earlier would hide a
 disagreement the editor is supposed to surface.
 */
public func splitPlan(
    groupId: String,
    mode: String,
    memberIds: [String],
    me: String,
    totalMinor: Int64,
    currency: String,
    shareText: [String: String],
    multiPayer: Bool,
    paidText: [String: String],
    hasAccount: Bool
) -> SplitPlan {
    // Web's `Number(v) || 0` — an unparseable field is zero, not a refusal.
    func number(_ key: String, _ source: [String: String]) -> Double {
        let v = jsNumber(source[key] ?? "")
        return v.isNaN ? 0 : v
    }
    func minor(_ key: String, _ source: [String: String]) -> Int64 {
        fromMajor(number(key, source), currency).amount
    }

    let n = memberIds.count
    let shares: [Int64]
    switch mode {
    case SplitModes.percent:
        shares = splitByWeights(totalMinor, memberIds.map { number($0, shareText) })
    case SplitModes.exact:
        shares = memberIds.map { minor($0, shareText) }
    default:
        shares = splitEqual(totalMinor, n)
    }
    let sharesSum = shares.reduce(Int64(0), +)
    let percentSum = memberIds.reduce(0.0) { $0 + number($1, shareText) }

    let payerList: [SplitPayerPlan]
    if multiPayer {
        payerList = memberIds.map {
            SplitPayerPlan(userId: $0, paidMinor: minor($0, paidText), isMe: $0 == me)
        }
    } else {
        // Single payer: the whole amount is mine. Web writes exactly this, and
        // it is why the account is required below.
        payerList = [SplitPayerPlan(userId: me, paidMinor: totalMinor, isMe: true)]
    }
    let paidSum = payerList.reduce(Int64(0)) { $0 + $1.paidMinor }
    let myPaid = payerList.filter(\.isMe).reduce(Int64(0)) { $0 + $1.paidMinor }

    let modeBalances: Bool
    switch mode {
    case SplitModes.exact:
        modeBalances = sharesSum == totalMinor
    case SplitModes.percent:
        // `Math.round` on the SUM, not on each share: three people at 33.33%
        // sum to 99.99 and are accepted, which is the whole reason the rounding
        // is here rather than a strict equality.
        modeBalances = jsRound(percentSum) == 100
    default:
        modeBalances = true
    }

    let valid = !groupId.isEmpty
        && n >= 2
        && totalMinor > 0
        && memberIds.contains(me)
        && modeBalances
        && (!multiPayer || paidSum == totalMinor)
        // An account is needed only when MY money moved. A split where someone
        // else paid every rupee records what I owe and touches no account of
        // mine, so demanding one would block a legitimate entry.
        && (myPaid <= 0 || hasAccount)

    return SplitPlan(
        shares: shares,
        sharesSum: sharesSum,
        percentSum: percentSum,
        paidSum: paidSum,
        valid: valid,
        participants: memberIds.map { key in
            let value: Double?
            switch mode {
            case SplitModes.percent: value = number(key, shareText)
            case SplitModes.exact: value = Double(minor(key, shareText))
            default: value = nil
            }
            return SplitParticipantPlan(userId: key, value: value)
        },
        payers: payerList.filter { $0.paidMinor > 0 }
    )
}

/**
 Whether the split editor is actually in play.

 Web's `splitActive`: expense only, toggle on, a group chosen, and at least two
 people. Anything less and the transaction is written as an ordinary one — which
 is why this is a separate question from `SplitPlan.valid`, and why a
 half-filled editor does not block Save.
 */
public func splitActive(type: String, splitOn: Bool, groupId: String, memberCount: Int) -> Bool {
    type == "expense" && splitOn && !groupId.isEmpty && memberCount >= 2
}

/**
 Whether "I paid for someone else" is in play.

 Web's `forOtherActive`, and the ordering matters: it is mutually exclusive with
 the split toggle, so turning the split on wins. It is modelled as a 1:1 split
 where their share is 100% and mine is 0.
 */
public func forOtherActive(
    type: String,
    splitOn: Bool,
    forOtherOn: Bool,
    otherUserId: String,
    totalMinor: Int64
) -> Bool {
    type == "expense" && !splitOn && forOtherOn && !otherUserId.isEmpty && totalMinor > 0
}

/// A group the auto-split effect may preselect.
public struct AutoSplitCandidate: Equatable, Sendable {
    public let id: String
    public let startDate: String?
    public let endDate: String?
    public let autoSplit: Bool

    public init(id: String, startDate: String?, endDate: String?, autoSplit: Bool) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.autoSplit = autoSplit
    }
}

/**
 The group an auto-split trip would preselect for a given date.

 Web looks for a group with `auto_split = 1` whose date range contains the
 transaction's day; its own open end is `"9999-12-31"`, which is a sentinel
 rather than a real date and is reproduced as one. Returns the FIRST match, as
 `Array.find` does — with two overlapping trips the earlier row wins, which is
 arbitrary but is what the browser does.
 */
public func autoSplitGroupFor(groups: [AutoSplitCandidate], dateIso: String) -> String? {
    let day = String(dateIso.prefix(10))
    return groups.first { g in
        guard g.autoSplit, let start = g.startDate else { return false }
        return day >= start && day <= (g.endDate ?? "9999-12-31")
    }?.id
}
