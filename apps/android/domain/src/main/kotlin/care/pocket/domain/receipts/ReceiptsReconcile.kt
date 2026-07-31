package care.pocket.domain.receipts

// Ported from packages/core/receipts/src/reconcile.ts (P1.5a). This is the
// quality gate for the whole feature: OCR is confident and wrong far more
// often than it is unsure, so confidence alone is never trusted -- a draft
// only passes when the arithmetic closes exactly.
//
// Package-scoped `reconcile()`/`Subtotals` here are a DIFFERENT domain from
// care.pocket.domain.reconcile's bank-drift `reconcile()` (P1.6) -- same
// function name, same as the TS source's two separate `reconcile.ts`
// modules under different npm packages, disambiguated here the same way:
// by package, not by name.

data class Subtotals(
    /** Sum of `item` lines. */
    val items: Long,
    val tax: Long,
    val serviceCharge: Long,
    val tip: Long,
    /** Negative (discounts reduce the bill). */
    val discount: Long,
    /** items + tax + serviceCharge + tip + discount. */
    val computed: Long,
)

fun subtotals(lines: List<ReceiptLine>): Subtotals {
    var items = 0L
    var tax = 0L
    var serviceCharge = 0L
    var tip = 0L
    var discount = 0L
    for (l in lines) {
        when (l.kind) {
            "item" -> items += l.amount
            "tax" -> tax += l.amount
            "service_charge" -> serviceCharge += l.amount
            "tip" -> tip += l.amount
            else -> discount += l.amount
        }
    }
    return Subtotals(items, tax, serviceCharge, tip, discount, items + tax + serviceCharge + tip + discount)
}

data class ReconcileResult(
    val ok: Boolean,
    val reason: String, // "balanced" | "no_lines" | "missing_total" | "mismatch"
    /** Sum of the parsed lines. */
    val computed: Long,
    /** The total as printed on the receipt, if we could read one. */
    val stated: Long?,
    /** stated - computed. Positive = we're missing lines worth this much. */
    val delta: Long,
    val subtotals: Subtotals,
)

/**
 * Compare Sum(lines) against the printed total.
 *
 * Exact-match only: a receipt that is off by even one minor unit means we
 * misread something, and quietly absorbing it would corrupt the ledger.
 */
fun reconcile(draft: ReceiptDraft): ReconcileResult {
    val s = subtotals(draft.lines)
    if (draft.lines.isEmpty()) {
        return ReconcileResult(ok = false, reason = "no_lines", computed = 0L, stated = draft.total, delta = draft.total ?: 0L, subtotals = s)
    }
    if (draft.total == null) {
        return ReconcileResult(ok = false, reason = "missing_total", computed = s.computed, stated = null, delta = 0L, subtotals = s)
    }
    val delta = draft.total - s.computed
    return ReconcileResult(
        ok = delta == 0L,
        reason = if (delta == 0L) "balanced" else "mismatch",
        computed = s.computed,
        stated = draft.total,
        delta = delta,
        subtotals = s,
    )
}

/** Confidence below this is treated as "we probably misread this". */
const val LOW_CONFIDENCE = 70

/**
 * Should we offer the AI fallback? True when the arithmetic doesn't close,
 * we found no total, or the OCR itself was shaky. The caller still asks the
 * user -- the image never leaves the device without an explicit tap.
 */
fun shouldEscalate(draft: ReceiptDraft): Boolean {
    if (draft.engine == "claude") return false
    if (draft.confidence < LOW_CONFIDENCE) return true
    return !reconcile(draft).ok
}

/**
 * One-tap fix for a mismatch: append a single line absorbing the difference
 * so the draft balances and can be saved. Used by the review screen's
 * "add the missing amount as an unlabelled line" action.
 */
fun balanceWithLine(draft: ReceiptDraft, id: String, description: String): ReceiptDraft {
    val r = reconcile(draft)
    if (r.ok || r.stated == null) return draft
    val line = ReceiptLine(
        id = id,
        kind = if (r.delta < 0) "discount" else "item",
        description = description,
        quantity = null,
        unit = null,
        unitPrice = null,
        amount = r.delta,
        confidence = 0,
    )
    return draft.copy(lines = draft.lines + line)
}
