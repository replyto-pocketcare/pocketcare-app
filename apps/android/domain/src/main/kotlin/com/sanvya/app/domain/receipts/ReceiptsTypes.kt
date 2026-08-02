package com.sanvya.app.domain.receipts

// Ported from packages/core/receipts/src/types.ts (P1.5a). Correctness is
// judged against tools/golden-vectors/vectors/receipts-*.json, not a fresh
// reading of the TS -- see docs/plans/native-mobile-apps.md section 5 and
// CLAUDE.md golden rule 8 ("web is the spec"). Unlike money/finance/budget,
// this domain's exported vectors never wrap amounts with amt()/mny() --
// every money/quantity field here is a PLAIN JSON number, confirmed by
// reading the actual generated receipts-*.json files (same convention as
// splits-insights/splits-math, P1.4).
//
// Kind/mode/engine fields are plain Strings compared with `when`, not a
// Kotlin enum -- matches the established Budget.kt/Finance.kt convention
// for the TS source's string-literal unions (RECEIPT_LINE_KINDS,
// ITEM_SPLIT_MODES, RECEIPT_ENGINES).

/** Quantities are milli-units: 1000 === one unit. */
const val QTY_SCALE = 1000

/** True for the non-goods lines (tax / service charge / tip / discount). */
fun isCharge(kind: String): Boolean = kind != "item"

/** One printed line on a receipt. `item` lines are goods; the rest are charges. */
data class ReceiptLine(
    val id: String,
    val kind: String, // "item" | "tax" | "service_charge" | "tip" | "discount"
    val description: String,
    /** Milli-units. Null when the receipt didn't print a quantity. */
    val quantity: Long?,
    /** Free-text unit as printed ("kg", "pcs", "L"). Null when absent. */
    val unit: String?,
    /** Minor units per single unit. Null when the receipt didn't print one. */
    val unitPrice: Long?,
    /** Minor units. The authoritative line total. Negative for `discount`. */
    val amount: Long,
    /** 0-100. How sure the parser is about THIS line. */
    val confidence: Int,
)

data class ReceiptDraft(
    val merchant: String?,
    /** ISO-8601 date (YYYY-MM-DD) as printed. Null when unreadable. */
    val occurredAt: String?,
    /** ISO 4217. Falls back to the user's base currency when unreadable. */
    val currency: String,
    val lines: List<ReceiptLine>,
    /** Minor units, as PRINTED on the receipt. Null when unreadable. */
    val total: Long?,
    /** 0-100 overall parse confidence. */
    val confidence: Int,
    val engine: String, // "tesseract" | "claude" | "pdf_text" | "manual"
    /** Raw OCR text, kept for re-parsing and debugging. Never contains an image. */
    val rawText: String? = null,
)

// ---------------------------------------------------------------------------
// Split modes
// ---------------------------------------------------------------------------

/** Percent weights are stored x100 so "33.33%" is the integer 3333. */
const val PERCENT_SCALE = 100

/**
 * A participant's claim on one line. The meaning of `weight` depends on the
 * line's mode: milli-quantity, percent x100, exact minor units, or ignored
 * (`equal`). `proportional` derives its weights and ignores this field.
 */
data class ShareInput(val userId: String, val weight: Double? = null)

/** Resolved allocation: minor units this user owes for this line. */
data class ShareResult(val userId: String, val amount: Long)

/** One line plus who is on it and how it's divided. */
data class LineAssignment(val lineId: String, val mode: String, val shares: List<ShareInput>)
