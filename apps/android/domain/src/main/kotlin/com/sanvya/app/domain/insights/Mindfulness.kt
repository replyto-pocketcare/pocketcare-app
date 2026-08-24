package com.sanvya.app.domain.insights

import com.sanvya.app.domain.money.fromMajor
import java.time.Instant

// Ported verbatim from packages/core/mindfulness/src/index.ts (92 lines) for
// the Insights feed's two mindfulness generator cards (task #28). Ported
// faithfully including the source's own acknowledged naivety (UTC-only
// late-night check, no real timezone handling) -- not "fixed" here.

data class TransactionForInsight(
    val id: String,
    val amount: Long,
    val currency: String,
    val occurredAt: String,
    /** "need" | "greed" | null */
    val intent: String?,
    val categoryId: String?,
)

data class MindfulInsight(val id: String, val type: String, val title: String, val body: String, val severity: String?)

/** The small-purchase-drift threshold, in MAJOR units. */
private const val SMALL_PURCHASE_MAJOR = 200.0

/**
 * Tier 1 insights (no tagging required).
 *
 * Takes the currency and the caller's formatter, which is this codebase's
 * established "domain never formats currency, screens do" convention --
 * `GenContext` already carries both. The original port interpolated a bare
 * `total / 100.0`, which was wrong in any currency that does not have two
 * minor units and could not be hidden by the hide-amounts toggle.
 */
fun computeTier1Insights(
    txns: List<TransactionForInsight>,
    currency: String,
    fmt: (Long) -> String,
): List<MindfulInsight> {
    val insights = mutableListOf<MindfulInsight>()
    if (txns.isEmpty()) return insights

    // Late-night spending (22:00-04:00). Naive UTC-hour check, matches the
    // TS source's own explicit caveat about not doing real timezone math.
    var lateNightCount = 0
    for (t in txns) {
        val hour = runCatching { Instant.parse(t.occurredAt).atZone(java.time.ZoneOffset.UTC).hour }.getOrNull() ?: continue
        if (hour >= 22 || hour < 4) lateNightCount++
    }
    if (lateNightCount > 0) {
        insights.add(MindfulInsight(
            id = "late_night_spending", type = "tier1", title = "Late-night spending",
            body = "You logged $lateNightCount transaction(s) between 22:00 and 04:00.", severity = "info",
        ))
    }

    // Small-purchase drift.
    //
    // The threshold is derived, not written down: 20000 minor units is 200 only
    // in a 2-decimal currency. In JPY it meant 20,000 yen and in KWD 20 dinar.
    val threshold = fromMajor(SMALL_PURCHASE_MAJOR, currency).amount

    // Same-currency only. Summing yen into dollars produced a number that was
    // not an amount in any currency, then labelled it with one.
    val smallTxns = txns.filter { it.currency == currency && it.amount < threshold }
    if (smallTxns.size > 5) {
        val totalSmall = smallTxns.sumOf { it.amount }
        insights.add(MindfulInsight(
            id = "small_purchase_drift", type = "tier1", title = "Small-purchase drift",
            body = "You had ${smallTxns.size} spends under ${fmt(threshold)}, totaling ${fmt(totalSmall)}.",
            severity = "info",
        ))
    }
    return insights
}

/** Tier 2 insights (unlocked by Need/Greed tagging). */
fun computeTier2Insights(txns: List<TransactionForInsight>): List<MindfulInsight> {
    val insights = mutableListOf<MindfulInsight>()
    val tagged = txns.filter { it.intent == "need" || it.intent == "greed" }
    if (tagged.size < 20) return insights // minimum 20 tagged items needed

    val greed = tagged.filter { it.intent == "greed" }
    val totalTaggedAmount = tagged.sumOf { it.amount }
    val totalGreedAmount = greed.sumOf { it.amount }
    val ratio = (totalGreedAmount.toDouble() / (if (totalTaggedAmount == 0L) 1.0 else totalTaggedAmount.toDouble())) * 100.0

    insights.add(MindfulInsight(
        id = "greed_ratio", type = "tier2", title = "Greed ratio",
        body = "${Math.round(ratio)}% of your tagged spending was marked as Greed.",
        severity = if (ratio > 50) "warn" else "success",
    ))
    return insights
}
