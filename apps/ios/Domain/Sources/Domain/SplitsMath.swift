import Foundation

// Ported from apps/web/src/splits/math.ts (P1.4b). Mirrors
// apps/android/domain/.../splitsmath/SplitsMath.kt (P1.4a). Correctness is
// judged against tools/golden-vectors/vectors/splits-math.json -- see
// docs/plans/native-mobile-apps.md section 5 and CLAUDE.md golden rule 8
// ("web is the spec"). Only pairwiseEdges is exercised by the golden
// vectors -- splitByWeights/splitEqual (re-exported from
// @pocketcare/receipts in the TS source) are that package's own port,
// tracked under P1.5 receipts, not duplicated here.
//
// Rounding: Math.round (ties toward +Infinity, same rule as Finance.swift,
// NOT Money's round-half-away-from-zero) -- reuses Finance.swift's
// jsMathRound rather than duplicating it.

public struct Party {
    public let userId: String
    public let share: Int64
    public let paid: Int64
    public init(userId: String, share: Int64, paid: Int64) {
        self.userId = userId
        self.share = share
        self.paid = paid
    }
}

public struct SplitEdge: Equatable {
    public let userId: String
    public let amount: Int64
}

/// Per-other-user edge (minor units) that the OTHER owes YOU on one
/// expense (negative = you owe them), via pro-rata payment allocation,
/// rounded so edges sum EXACTLY to your net (self.paid - self.share).
/// Multi-payer safe.
public func pairwiseEdges(_ parties: [Party], _ selfId: String) -> [SplitEdge] {
    let total = parties.reduce(Int64(0)) { $0 + $1.paid }
    let selfParty = parties.first { $0.userId == selfId } ?? Party(userId: selfId, share: 0, paid: 0)
    let others = parties.filter { $0.userId != selfId }
    if others.isEmpty { return [] }
    if total <= 0 { return others.map { SplitEdge(userId: $0.userId, amount: 0) } }

    let selfNet = selfParty.paid - selfParty.share
    let raw = others.map { o in
        (Double(o.share) * Double(selfParty.paid) - Double(selfParty.share) * Double(o.paid)) / Double(total)
    }
    var rounded = raw.map { Int64(jsMathRound($0)) }
    let residual = selfNet - rounded.reduce(Int64(0), +)
    if residual != 0 {
        var idx = 0
        for i in 1..<raw.count {
            if abs(raw[i]) > abs(raw[idx]) { idx = i }
        }
        rounded[idx] += residual
    }
    return others.enumerated().map { i, o in SplitEdge(userId: o.userId, amount: rounded[i]) }
}
