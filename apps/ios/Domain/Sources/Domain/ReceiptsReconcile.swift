import Foundation

// Ported from packages/core/receipts/src/reconcile.ts (P1.5b). Mirrors
// apps/android/domain/.../receipts/ReceiptsReconcile.kt (P1.5a). This is
// the quality gate for the whole feature: OCR is confident and wrong far
// more often than it is unsure, so confidence alone is never trusted -- a
// draft only passes when the arithmetic closes exactly.
//
// This file's top-level `reconcile(_:)` (ReceiptDraft -> ReconcileResult) is
// a DIFFERENT function from the top-level bank-drift `reconcile(_:_:_:)`
// domain (P1.6, different parameter types) -- Swift resolves the overload
// by argument type at each call site, same disambiguation the TS source
// gets for free from two separate npm packages.

public struct Subtotals: Sendable {
    /// Sum of `item` lines.
    public let items: Int64
    public let tax: Int64
    public let serviceCharge: Int64
    public let tip: Int64
    /// Negative (discounts reduce the bill).
    public let discount: Int64
    /// items + tax + serviceCharge + tip + discount.
    public let computed: Int64
}

public func subtotals(_ lines: [ReceiptLine]) -> Subtotals {
    var items: Int64 = 0
    var tax: Int64 = 0
    var serviceCharge: Int64 = 0
    var tip: Int64 = 0
    var discount: Int64 = 0
    for l in lines {
        switch l.kind {
        case "item": items += l.amount
        case "tax": tax += l.amount
        case "service_charge": serviceCharge += l.amount
        case "tip": tip += l.amount
        default: discount += l.amount
        }
    }
    return Subtotals(items: items, tax: tax, serviceCharge: serviceCharge, tip: tip, discount: discount, computed: items + tax + serviceCharge + tip + discount)
}

public struct ReconcileResult: Sendable {
    public let ok: Bool
    public let reason: String // "balanced" | "no_lines" | "missing_total" | "mismatch"
    /// Sum of the parsed lines.
    public let computed: Int64
    /// The total as printed on the receipt, if we could read one.
    public let stated: Int64?
    /// stated - computed. Positive = missing lines worth this much.
    public let delta: Int64
    public let subtotals: Subtotals
}

/// Compare Sum(lines) against the printed total.
///
/// Exact-match only: a receipt that is off by even one minor unit means we
/// misread something, and quietly absorbing it would corrupt the ledger.
public func reconcile(_ draft: ReceiptDraft) -> ReconcileResult {
    let s = subtotals(draft.lines)
    if draft.lines.isEmpty {
        return ReconcileResult(ok: false, reason: "no_lines", computed: 0, stated: draft.total, delta: draft.total ?? 0, subtotals: s)
    }
    guard let total = draft.total else {
        return ReconcileResult(ok: false, reason: "missing_total", computed: s.computed, stated: nil, delta: 0, subtotals: s)
    }
    let delta = total - s.computed
    return ReconcileResult(
        ok: delta == 0,
        reason: delta == 0 ? "balanced" : "mismatch",
        computed: s.computed,
        stated: total,
        delta: delta,
        subtotals: s
    )
}

/// Confidence below this is treated as "we probably misread this".
public let RECEIPT_LOW_CONFIDENCE = 70

/// Should we offer the AI fallback? True when the arithmetic doesn't close,
/// no total was found, or the OCR itself was shaky. The caller still asks
/// the user -- the image never leaves the device without an explicit tap.
public func shouldEscalate(_ draft: ReceiptDraft) -> Bool {
    if draft.engine == "claude" { return false }
    if draft.confidence < RECEIPT_LOW_CONFIDENCE { return true }
    return !reconcile(draft).ok
}

/// One-tap fix for a mismatch: append a single line absorbing the
/// difference so the draft balances and can be saved.
public func balanceWithLine(_ draft: ReceiptDraft, _ id: String, _ description: String) -> ReceiptDraft {
    let r = reconcile(draft)
    guard !r.ok, r.stated != nil else { return draft }
    let line = ReceiptLine(
        id: id,
        kind: r.delta < 0 ? "discount" : "item",
        description: description,
        quantity: nil,
        unit: nil,
        unitPrice: nil,
        amount: r.delta,
        confidence: 0
    )
    return ReceiptDraft(
        merchant: draft.merchant,
        occurredAt: draft.occurredAt,
        currency: draft.currency,
        lines: draft.lines + [line],
        total: draft.total,
        confidence: draft.confidence,
        engine: draft.engine,
        rawText: draft.rawText
    )
}
