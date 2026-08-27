package com.sanvya.app.domain.statements

import kotlin.math.abs

/**
 * Reconcile a parsed statement against what is already recorded in the app.
 *
 * Ported from `apps/web/src/statements/reconcile.ts`. Pure and deterministic:
 * matches on amount (exact magnitude AND direction), a date window, and
 * description similarity. Signed minor units throughout.
 *
 * Note `reconcile` is deliberately NOT the name here — `domain.reconcile`
 * already owns that word for the receipt-vs-total check, and two functions
 * called `reconcile` in one codebase is a coin flip at every call site.
 */

data class RecordedTxn(
    val id: String,
    /** Signed minor (− out / + in). */
    val amount: Long,
    /** YYYY-MM-DD. */
    val date: String,
    val description: String,
)

data class StatementMatch(val parsed: StatementTxn, val recorded: RecordedTxn, val score: Double)

data class Reconciliation(
    val matched: List<StatementMatch>,
    /** In the statement but NOT recorded in the app → import candidates. */
    val missingOnPlatform: List<StatementTxn>,
    /** Recorded in the app but not in this statement. */
    val onlyOnPlatform: List<RecordedTxn>,
)

private fun tokensOf(s: String): Set<String> =
    normalizeMerchant(s).split(" ").filter { it.isNotEmpty() }.toSet()

private fun jaccard(a: String, b: String): Double {
    val ta = tokensOf(a)
    val tb = tokensOf(b)
    if (ta.isEmpty() || tb.isEmpty()) return 0.0
    val inter = ta.count { tb.contains(it) }
    return inter.toDouble() / (ta.size + tb.size - inter)
}

/** Default date window, in days. Web's `opts.dayWindow ?? 4`. */
const val RECONCILE_DAY_WINDOW = 4

/**
 * Greedy best-first pairing.
 *
 * Every candidate pair is scored, the list is sorted once, and pairs are taken
 * in order while both sides are still free. It is not optimal — a maximum
 * weighted matching would be — but it is what web does, and a native app that
 * matched a DIFFERENT pair than the browser for the same statement would be
 * far worse than a slightly suboptimal one.
 */
fun reconcileStatement(
    parsed: List<StatementTxn>,
    recorded: List<RecordedTxn>,
    dayWindow: Int = RECONCILE_DAY_WINDOW,
): Reconciliation {
    data class Pair3(val pi: Int, val ri: Int, val score: Double)
    val pairs = mutableListOf<Pair3>()
    parsed.forEachIndexed { pi, p ->
        recorded.forEachIndexed { ri, r ->
            // Exact magnitude AND sign. A ₹500 refund is not a ₹500 spend.
            if (p.amount != r.amount) return@forEachIndexed
            val d0 = isoDaysOrNull(p.date) ?: return@forEachIndexed
            val d1 = isoDaysOrNull(r.date) ?: return@forEachIndexed
            val dd = abs(d0 - d1)
            if (dd > dayWindow) return@forEachIndexed
            // Higher score = better: closer date plus description overlap.
            val score = (1 - dd.toDouble() / (dayWindow + 1)) * 0.6 +
                jaccard(p.description, r.description) * 0.4
            pairs.add(Pair3(pi, ri, score))
        }
    }
    // sortedByDescending is stable, and so is JS's sort -- so equally scored
    // pairs are taken in generation order on both platforms.
    val ranked = pairs.sortedByDescending { it.score }

    val usedP = mutableSetOf<Int>()
    val usedR = mutableSetOf<Int>()
    val matched = mutableListOf<StatementMatch>()
    for ((pi, ri, score) in ranked) {
        if (pi in usedP || ri in usedR) continue
        usedP.add(pi)
        usedR.add(ri)
        matched.add(StatementMatch(parsed[pi], recorded[ri], score))
    }
    return Reconciliation(
        matched = matched,
        missingOnPlatform = parsed.filterIndexed { i, _ -> i !in usedP },
        onlyOnPlatform = recorded.filterIndexed { i, _ -> i !in usedR },
    )
}
