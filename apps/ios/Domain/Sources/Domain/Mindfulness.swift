import Foundation

// Ported verbatim from packages/core/mindfulness/src/index.ts (92 lines) for
// the Insights feed's two mindfulness generator cards (task #28). Mirrors
// Android's domain/insights/Mindfulness.kt added the same session. Ported
// faithfully including the source's own acknowledged naivety (UTC-only
// late-night check, no real timezone handling) -- not "fixed" here.

public struct TransactionForInsight: Sendable {
    public let id: String
    public let amount: Int64
    public let currency: String
    public let occurredAt: String
    /// "need" | "greed" | nil
    public let intent: String?
    public let categoryId: String?
    public init(id: String, amount: Int64, currency: String, occurredAt: String, intent: String?, categoryId: String?) {
        self.id = id; self.amount = amount; self.currency = currency
        self.occurredAt = occurredAt; self.intent = intent; self.categoryId = categoryId
    }
}

public struct MindfulInsight: Sendable {
    public let id: String
    public let type: String
    public let title: String
    public let body: String
    public let severity: String?
}

/// The small-purchase-drift threshold, in MAJOR units.
private let smallPurchaseMajor: Double = 200

/**
 Tier 1 insights (no tagging required).

 Takes the currency and the caller's formatter, which is this codebase's
 established "domain never formats currency, screens do" convention —
 `GenContext` already carries both. The original port interpolated a bare
 `total / 100`, which was wrong in any currency that does not have two minor
 units and could not be hidden by the hide-amounts toggle.
 */
public func computeTier1Insights(
    _ txns: [TransactionForInsight],
    currency: String,
    fmt: (Int64) -> String
) -> [MindfulInsight] {
    var insights: [MindfulInsight] = []
    if txns.isEmpty { return insights }

    // Late-night spending (22:00-04:00). Naive UTC-hour check, matches the
    // TS source's own explicit caveat about not doing real timezone math.
    var lateNightCount = 0
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let fractionalFmt: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    for t in txns {
        guard let d = fractionalFmt.date(from: t.occurredAt) ?? ISO8601DateFormatter().date(from: t.occurredAt) else { continue }
        let hour = cal.component(.hour, from: d)
        if hour >= 22 || hour < 4 { lateNightCount += 1 }
    }
    if lateNightCount > 0 {
        insights.append(MindfulInsight(
            id: "late_night_spending", type: "tier1", title: "Late-night spending",
            body: "You logged \(lateNightCount) transaction(s) between 22:00 and 04:00.", severity: "info"
        ))
    }

    // Small-purchase drift.
    //
    // The threshold is derived, not written down: 20000 minor units is 200 only
    // in a 2-decimal currency. In JPY it meant 20,000 yen and in KWD 20 dinar.
    let threshold = fromMajor(smallPurchaseMajor, currency).amount

    // Same-currency only. Summing yen into dollars produced a number that was
    // not an amount in any currency, then labelled it with one.
    let smallTxns = txns.filter { $0.currency == currency && $0.amount < threshold }
    if smallTxns.count > 5 {
        let totalSmall = smallTxns.reduce(Int64(0)) { $0 + $1.amount }
        insights.append(MindfulInsight(
            id: "small_purchase_drift", type: "tier1", title: "Small-purchase drift",
            body: "You had \(smallTxns.count) spends under \(fmt(threshold)), totaling \(fmt(totalSmall)).",
            severity: "info"
        ))
    }
    return insights
}

/// Tier 2 insights (unlocked by Need/Greed tagging).
public func computeTier2Insights(_ txns: [TransactionForInsight]) -> [MindfulInsight] {
    var insights: [MindfulInsight] = []
    let tagged = txns.filter { $0.intent == "need" || $0.intent == "greed" }
    if tagged.count < 20 { return insights } // minimum 20 tagged items needed

    let greed = tagged.filter { $0.intent == "greed" }
    let totalTaggedAmount = tagged.reduce(0) { $0 + $1.amount }
    let totalGreedAmount = greed.reduce(0) { $0 + $1.amount }
    let ratio = (Double(totalGreedAmount) / (totalTaggedAmount == 0 ? 1.0 : Double(totalTaggedAmount))) * 100.0

    insights.append(MindfulInsight(
        id: "greed_ratio", type: "tier2", title: "Greed ratio",
        body: "\(Int(ratio.rounded()))% of your tagged spending was marked as Greed.",
        severity: ratio > 50 ? "warn" : "success"
    ))
    return insights
}
