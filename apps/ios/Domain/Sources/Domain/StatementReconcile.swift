import Foundation

/**
 Reconcile a parsed statement against what is already recorded in the app.

 Ported from `apps/web/src/statements/reconcile.ts`. Pure and deterministic:
 matches on amount (exact magnitude AND direction), a date window, and
 description similarity. Signed minor units throughout.

 Note `reconcile` is deliberately NOT the name here — `ReceiptsReconcile.swift`
 already owns that word for the receipt-vs-total check, and two functions called
 `reconcile` in one module is a coin flip at every call site.

 Mirrors Android's StatementReconcile.kt.
 */

public struct RecordedTxn: Equatable, Sendable {
    public let id: String
    /// Signed minor (− out / + in).
    public let amount: Int64
    /// YYYY-MM-DD.
    public let date: String
    public let description: String

    public init(id: String, amount: Int64, date: String, description: String) {
        self.id = id
        self.amount = amount
        self.date = date
        self.description = description
    }
}

public struct StatementMatch: Equatable, Sendable {
    public let parsed: StatementTxn
    public let recorded: RecordedTxn
    public let score: Double
}

public struct Reconciliation: Equatable, Sendable {
    public let matched: [StatementMatch]
    /// In the statement but NOT recorded in the app → import candidates.
    public let missingOnPlatform: [StatementTxn]
    /// Recorded in the app but not in this statement.
    public let onlyOnPlatform: [RecordedTxn]
}

private func tokensOf(_ s: String) -> Set<String> {
    Set(normalizeMerchant(s).split(separator: " ").map(String.init).filter { !$0.isEmpty })
}

private func jaccard(_ a: String, _ b: String) -> Double {
    let ta = tokensOf(a)
    let tb = tokensOf(b)
    if ta.isEmpty || tb.isEmpty { return 0 }
    let inter = ta.filter { tb.contains($0) }.count
    return Double(inter) / Double(ta.count + tb.count - inter)
}

/// Default date window, in days. Web's `opts.dayWindow ?? 4`.
public let reconcileDayWindow = 4

/**
 Greedy best-first pairing.

 Every candidate pair is scored, the list is sorted once, and pairs are taken in
 order while both sides are still free. It is not optimal — a maximum weighted
 matching would be — but it is what web does, and a native app that matched a
 DIFFERENT pair than the browser for the same statement would be far worse than
 a slightly suboptimal one.
 */
public func reconcileStatement(
    _ parsed: [StatementTxn],
    _ recorded: [RecordedTxn],
    dayWindow: Int = reconcileDayWindow
) -> Reconciliation {
    struct Pair3 { let pi: Int; let ri: Int; let score: Double }
    var pairs: [Pair3] = []
    for (pi, p) in parsed.enumerated() {
        for (ri, r) in recorded.enumerated() {
            // Exact magnitude AND sign. A ₹500 refund is not a ₹500 spend.
            if p.amount != r.amount { continue }
            guard let d0 = isoDaysOrNil(p.date), let d1 = isoDaysOrNil(r.date) else { continue }
            let dd = abs(d0 - d1)
            if dd > dayWindow { continue }
            // Higher score = better: closer date plus description overlap.
            let score = (1 - Double(dd) / Double(dayWindow + 1)) * 0.6
                + jaccard(p.description, r.description) * 0.4
            pairs.append(Pair3(pi: pi, ri: ri, score: score))
        }
    }
    // Stable, so equally scored pairs are taken in generation order on both
    // platforms — see stableSorted's own comment.
    let ranked = stableSorted(pairs) { $0.score > $1.score }

    var usedP: Set<Int> = []
    var usedR: Set<Int> = []
    var matched: [StatementMatch] = []
    for pair in ranked {
        if usedP.contains(pair.pi) || usedR.contains(pair.ri) { continue }
        usedP.insert(pair.pi)
        usedR.insert(pair.ri)
        matched.append(StatementMatch(parsed: parsed[pair.pi], recorded: recorded[pair.ri], score: pair.score))
    }
    return Reconciliation(
        matched: matched,
        missingOnPlatform: parsed.enumerated().filter { !usedP.contains($0.offset) }.map(\.element),
        onlyOnPlatform: recorded.enumerated().filter { !usedR.contains($0.offset) }.map(\.element)
    )
}
