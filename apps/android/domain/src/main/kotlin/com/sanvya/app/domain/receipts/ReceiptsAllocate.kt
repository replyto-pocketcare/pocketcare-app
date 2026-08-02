package com.sanvya.app.domain.receipts

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.roundToLong

// Ported from packages/core/receipts/src/allocate.ts (P1.5a). Every
// function here is pure and works in integer minor units (Long). The
// single money-preserving primitive is splitByWeights (largest remainder):
// the returned parts ALWAYS sum exactly back to the input total, so no
// minor unit is ever created or lost no matter how the weights fall --
// same algorithm family as Money.kt's split(), independently re-derived
// here because this version takes arbitrary (possibly fractional) weights
// rather than an equal part count.

/**
 * Distribute `total` minor units across `weights` via largest-remainder.
 * Sums exactly to `total` for positive AND negative totals (discount lines).
 * Weights are clamped at 0; an all-zero weight vector yields all zeros.
 */
fun splitByWeights(total: Long, weights: List<Double>): List<Long> {
    val w = weights.sumOf { max(0.0, it) }
    if (w <= 0) return weights.map { 0L }
    val raw = weights.map { (total * max(0.0, it)) / w }
    val out = raw.map { floor(it).toLong() }.toMutableList()
    val rem = total - out.sum()
    val order = raw.mapIndexed { i, x -> Triple(i, x - floor(x), x) }
        .sortedWith(compareByDescending<Triple<Int, Double, Double>> { it.second }.thenBy { it.first })
    var k = 0
    while (k < rem && k < order.size) {
        out[order[k].first] += 1
        k++
    }
    return out
}

fun splitEqual(total: Long, n: Int): List<Long> = splitByWeights(total, List(n) { 1.0 })

/** Mirrors the TS source's `AllocationError extends Error` -- name matters, the
 * vector runner checks the thrown exception's simple class name against the
 * vector's `throws.name`. */
class AllocationError(message: String) : Exception(message)

/**
 * Allocate ONE line across its participants.
 *
 * `proportional` is not handled here -- it needs the item subtotals, so it
 * is resolved by allocateReceipt. Calling this with `proportional` throws.
 */
fun allocateItem(amount: Long, shares: List<ShareInput>, mode: String): List<ShareResult> {
    if (shares.isEmpty()) return emptyList()
    if (mode == "proportional") {
        throw AllocationError("proportional lines must be allocated via allocateReceipt()")
    }

    if (mode == "exact") {
        // Weights ARE the amounts. We do not rebalance: an exact split that
        // does not add up is a user error the UI must surface before saving.
        val parts = shares.map { (it.weight ?: 0.0).roundToLong() }
        val sum = parts.sum()
        if (sum != amount) {
            throw AllocationError("Exact shares sum to $sum, expected $amount")
        }
        return shares.mapIndexed { i, s -> ShareResult(s.userId, parts[i]) }
    }

    val weights: List<Double> = if (mode == "equal") shares.map { 1.0 } else shares.map { max(0.0, it.weight ?: 0.0) }

    // A quantity/percent split where nobody was given a weight is almost
    // always "the user hasn't filled it in yet" -- fall back to equal
    // rather than silently assigning the whole line to nobody.
    val totalWeight = weights.sum()
    val effective = if (totalWeight > 0) weights else shares.map { 1.0 }

    val parts = splitByWeights(amount, effective)
    return shares.mapIndexed { i, s -> ShareResult(s.userId, parts[i]) }
}

/**
 * Allocate a charge (tax / service / tip / discount) pro-rata to each
 * person's item subtotal. Participants with a zero subtotal get nothing --
 * unless NOBODY has a subtotal, in which case it falls back to an equal split.
 */
fun allocateProportional(amount: Long, participants: List<String>, subtotalByUser: Map<String, Long>): List<ShareResult> {
    if (participants.isEmpty()) return emptyList()
    val weights = participants.map { max(0L, subtotalByUser[it] ?: 0L).toDouble() }
    val total = weights.sum()
    val parts = splitByWeights(amount, if (total > 0) weights else participants.map { 1.0 })
    return participants.mapIndexed { i, userId -> ShareResult(userId, parts[i]) }
}

/** Sum per-line allocations into one total per user. */
fun rollUp(perLine: Map<String, List<ShareResult>>): Map<String, Long> {
    val out = LinkedHashMap<String, Long>()
    for (results in perLine.values) {
        for (r in results) out[r.userId] = (out[r.userId] ?: 0L) + r.amount
    }
    return out
}

data class AllocationResult(
    /** lineId -> per-user amounts. */
    val perLine: Map<String, List<ShareResult>>,
    /** userId -> total owed across every line. Sums exactly to `total`. */
    val byUser: Map<String, Long>,
    /** Sum of every line amount (what the expense row will carry). */
    val total: Long,
    /** userId -> subtotal from `item` lines only (what proportional charges use). */
    val itemSubtotalByUser: Map<String, Long>,
)

/**
 * Allocate a whole receipt: item lines first, then charge lines (which may
 * be proportional to the item subtotals just computed), then roll up per
 * user.
 *
 * Guarantees Sum(byUser) === Sum(lines[].amount), which is exactly the
 * invariant expense_participants needs so the existing balance logic keeps
 * working.
 */
fun allocateReceipt(lines: List<ReceiptLine>, assignments: List<LineAssignment>): AllocationResult {
    val byLineId = assignments.associateBy { it.lineId }
    val perLine = LinkedHashMap<String, List<ShareResult>>()

    // Pass 1 -- item lines. These define each person's subtotal.
    for (line in lines) {
        if (isCharge(line.kind)) continue
        val a = byLineId[line.id] ?: continue
        if (a.shares.isEmpty()) continue
        if (a.mode == "proportional") {
            throw AllocationError("Line ${line.id} is an item; 'proportional' applies to charges only")
        }
        perLine[line.id] = allocateItem(line.amount, a.shares, a.mode)
    }
    val itemSubtotalByUser = rollUp(perLine)

    // Pass 2 -- charges, which may lean on the subtotals from pass 1.
    for (line in lines) {
        if (!isCharge(line.kind)) continue
        val a = byLineId[line.id] ?: continue
        if (a.shares.isEmpty()) continue
        perLine[line.id] = if (a.mode == "proportional") {
            allocateProportional(line.amount, a.shares.map { it.userId }, itemSubtotalByUser)
        } else {
            allocateItem(line.amount, a.shares, a.mode)
        }
    }

    val byUser = rollUp(perLine)
    val total = lines.sumOf { it.amount }

    // Defensive: an unassigned line would silently vanish from the roll-up
    // and leave the expense unbalanced. Fail loudly instead of writing bad data.
    val allocated = byUser.values.sum()
    if (allocated != total) {
        throw AllocationError("Allocated $allocated but lines total $total — every line must be assigned to at least one person")
    }

    return AllocationResult(perLine, byUser, total, itemSubtotalByUser)
}
