package com.sanvya.app.domain.insights

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

/** Tier 1 insights (no tagging required). */
fun computeTier1Insights(txns: List<TransactionForInsight>): List<MindfulInsight> {
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

    // Small-purchase drift (<200 major units == <20000 minor).
    val smallTxns = txns.filter { it.amount < 20_000 }
    if (smallTxns.size > 5) {
        val totalSmall = smallTxns.sumOf { it.amount }
        insights.add(MindfulInsight(
            id = "small_purchase_drift", type = "tier1", title = "Small-purchase drift",
            body = "You had ${smallTxns.size} spends under 200, totaling ${totalSmall / 100.0}.", severity = "info",
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
