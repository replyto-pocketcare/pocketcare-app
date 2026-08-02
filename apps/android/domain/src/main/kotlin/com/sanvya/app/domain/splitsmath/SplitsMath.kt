package com.sanvya.app.domain.splitsmath

import kotlin.math.abs
import kotlin.math.roundToLong

// Ported from apps/web/src/splits/math.ts (P1.4a). Correctness is judged
// against tools/golden-vectors/vectors/splits-math.json -- see
// docs/plans/native-mobile-apps.md section 5 and CLAUDE.md golden rule 8
// ("web is the spec"). Only pairwiseEdges is exercised by the golden
// vectors -- splitByWeights/splitEqual (re-exported from @sanvya/receipts
// in the TS source) are that package's own port, tracked under P1.5
// receipts, not duplicated here.
//
// Rounding: Math.round (ties toward +Infinity, same rule as Finance.kt/
// Finance.swift, NOT Money's round-half-away-from-zero). Kotlin's
// roundToLong() already matches this by its own documented contract.

data class Party(val userId: String, val share: Long, val paid: Long)

data class Edge(val userId: String, val amount: Long)

/**
 * Per-other-user edge (minor units) that the OTHER owes YOU on one expense
 * (negative = you owe them), via pro-rata payment allocation, rounded so
 * edges sum EXACTLY to your net (self.paid - self.share). Multi-payer safe.
 */
fun pairwiseEdges(parties: List<Party>, selfId: String): List<Edge> {
    val total = parties.fold(0L) { acc, p -> acc + p.paid }
    val self = parties.find { it.userId == selfId } ?: Party(selfId, 0, 0)
    val others = parties.filter { it.userId != selfId }
    if (others.isEmpty()) return emptyList()
    if (total <= 0) return others.map { Edge(it.userId, 0L) }

    val selfNet = self.paid - self.share
    val raw = others.map { o -> (o.share.toDouble() * self.paid - self.share.toDouble() * o.paid) / total }
    val rounded = raw.map { it.roundToLong() }.toMutableList()
    val residual = selfNet - rounded.fold(0L) { acc, x -> acc + x }
    if (residual != 0L) {
        var idx = 0
        for (i in 1 until raw.size) {
            if (abs(raw[i]) > abs(raw[idx])) idx = i
        }
        rounded[idx] = rounded[idx] + residual
    }
    return others.mapIndexed { i, o -> Edge(o.userId, rounded[i]) }
}
