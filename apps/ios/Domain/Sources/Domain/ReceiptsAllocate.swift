import Foundation

// Ported from packages/core/receipts/src/allocate.ts (P1.5b). Mirrors
// apps/android/domain/.../receipts/ReceiptsAllocate.kt (P1.5a). Every
// function here is pure and works in integer minor units (Int64). The
// single money-preserving primitive is splitByWeights (largest remainder):
// the returned parts ALWAYS sum exactly back to the input total.
//
// perLine/byUser/itemSubtotalByUser are plain [String: _] Dictionaries, not
// order-preserving structures -- unlike SplitsInsights.swift's
// computeFriendStats (P1.4, whose output is a JSON ARRAY the vector
// compares element-by-element in order), every one of these results is
// serialized as a JSON OBJECT, which the vector runner compares by
// key/value pairs regardless of iteration order. No insertion-order
// tracking is needed here, deliberately simpler than that precedent.

/// Distribute `total` minor units across `weights` via largest-remainder.
/// Sums exactly to `total` for positive AND negative totals (discount lines).
/// Weights are clamped at 0; an all-zero weight vector yields all zeros.
public func splitByWeights(_ total: Int64, _ weights: [Double]) -> [Int64] {
    let w = weights.reduce(0.0) { $0 + max(0.0, $1) }
    if w <= 0 { return weights.map { _ in 0 } }
    let raw = weights.map { (Double(total) * max(0.0, $0)) / w }
    var out = raw.map { Int64($0.rounded(.down)) }
    let rem = total - out.reduce(0, +)
    let order = raw.enumerated()
        .map { (i: $0.offset, frac: $0.element - $0.element.rounded(.down)) }
        .sorted { a, b in a.frac != b.frac ? a.frac > b.frac : a.i < b.i }
    var k = 0
    while Int64(k) < rem && k < order.count {
        out[order[k].i] += 1
        k += 1
    }
    return out
}

public func splitEqual(_ total: Int64, _ n: Int) -> [Int64] {
    splitByWeights(total, Array(repeating: 1.0, count: n))
}

/// Mirrors the TS source's `AllocationError extends Error` -- name matters,
/// the vector runner checks the thrown error's identity against the
/// vector's `throws.name` when it isn't the generic "Error".
public struct AllocationError: Error, CustomStringConvertible, Sendable {
    public let description: String
}

/// Allocate ONE line across its participants.
///
/// `proportional` is not handled here -- it needs the item subtotals, so it
/// is resolved by allocateReceipt. Calling this with `proportional` throws.
public func allocateItem(_ amount: Int64, _ shares: [ShareInput], _ mode: String) throws -> [ShareResult] {
    if shares.isEmpty { return [] }
    if mode == "proportional" {
        throw AllocationError(description: "proportional lines must be allocated via allocateReceipt()")
    }

    if mode == "exact" {
        // Weights ARE the amounts. No rebalancing: an exact split that does
        // not add up is a user error the UI must surface before saving.
        let parts = shares.map { Int64(jsMathRound($0.weight ?? 0)) }
        let sum = parts.reduce(0, +)
        if sum != amount {
            throw AllocationError(description: "Exact shares sum to \(sum), expected \(amount)")
        }
        return shares.enumerated().map { i, s in ShareResult(userId: s.userId, amount: parts[i]) }
    }

    let weights: [Double] = mode == "equal" ? shares.map { _ in 1.0 } : shares.map { max(0.0, $0.weight ?? 0) }

    // A quantity/percent split where nobody was given a weight is almost
    // always "the user hasn't filled it in yet" -- fall back to equal
    // rather than silently assigning the whole line to nobody.
    let totalWeight = weights.reduce(0, +)
    let effective = totalWeight > 0 ? weights : shares.map { _ in 1.0 }

    let parts = splitByWeights(amount, effective)
    return shares.enumerated().map { i, s in ShareResult(userId: s.userId, amount: parts[i]) }
}

/// Allocate a charge (tax / service / tip / discount) pro-rata to each
/// person's item subtotal. Participants with a zero subtotal get nothing --
/// unless NOBODY has a subtotal, in which case it falls back to an equal split.
public func allocateProportional(_ amount: Int64, _ participants: [String], _ subtotalByUser: [String: Int64]) -> [ShareResult] {
    if participants.isEmpty { return [] }
    let weights = participants.map { Double(max(0, subtotalByUser[$0] ?? 0)) }
    let total = weights.reduce(0, +)
    let parts = splitByWeights(amount, total > 0 ? weights : participants.map { _ in 1.0 })
    return zip(participants, parts).map { ShareResult(userId: $0, amount: $1) }
}

/// Sum per-line allocations into one total per user.
public func rollUp(_ perLine: [String: [ShareResult]]) -> [String: Int64] {
    var out: [String: Int64] = [:]
    for results in perLine.values {
        for r in results { out[r.userId] = (out[r.userId] ?? 0) + r.amount }
    }
    return out
}

public struct AllocationResult: Sendable {
    /// lineId -> per-user amounts.
    public let perLine: [String: [ShareResult]]
    /// userId -> total owed across every line. Sums exactly to `total`.
    public let byUser: [String: Int64]
    /// Sum of every line amount (what the expense row will carry).
    public let total: Int64
    /// userId -> subtotal from `item` lines only (what proportional charges use).
    public let itemSubtotalByUser: [String: Int64]
}

/// Allocate a whole receipt: item lines first, then charge lines (which may
/// be proportional to the item subtotals just computed), then roll up per
/// user.
///
/// Guarantees Sum(byUser) === Sum(lines[].amount), which is exactly the
/// invariant expense_participants needs so the existing balance logic keeps
/// working.
public func allocateReceipt(_ lines: [ReceiptLine], _ assignments: [LineAssignment]) throws -> AllocationResult {
    var byLineId: [String: LineAssignment] = [:]
    for a in assignments { byLineId[a.lineId] = a }

    var perLine: [String: [ShareResult]] = [:]

    // Pass 1 -- item lines. These define each person's subtotal.
    for line in lines {
        if isCharge(line.kind) { continue }
        guard let a = byLineId[line.id], !a.shares.isEmpty else { continue }
        if a.mode == "proportional" {
            throw AllocationError(description: "Line \(line.id) is an item; 'proportional' applies to charges only")
        }
        perLine[line.id] = try allocateItem(line.amount, a.shares, a.mode)
    }
    let itemSubtotalByUser = rollUp(perLine)

    // Pass 2 -- charges, which may lean on the subtotals from pass 1.
    for line in lines {
        if !isCharge(line.kind) { continue }
        guard let a = byLineId[line.id], !a.shares.isEmpty else { continue }
        perLine[line.id] = a.mode == "proportional"
            ? allocateProportional(line.amount, a.shares.map { $0.userId }, itemSubtotalByUser)
            : try allocateItem(line.amount, a.shares, a.mode)
    }

    let byUser = rollUp(perLine)
    let total = lines.reduce(Int64(0)) { $0 + $1.amount }

    // Defensive: an unassigned line would silently vanish from the roll-up
    // and leave the expense unbalanced. Fail loudly instead of writing bad data.
    let allocated = byUser.values.reduce(Int64(0), +)
    if allocated != total {
        throw AllocationError(description: "Allocated \(allocated) but lines total \(total) — every line must be assigned to at least one person")
    }

    return AllocationResult(perLine: perLine, byUser: byUser, total: total, itemSubtotalByUser: itemSubtotalByUser)
}
