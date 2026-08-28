package com.sanvya.app.domain.receipts

import com.sanvya.app.domain.js.jsRound
import com.sanvya.app.domain.money.fromMajor
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * The AI fallback's reply, turned into a [ReceiptDraft].
 *
 * Ported from `mapLine` and the draft assembly in
 * `apps/web/src/receipts/aiParse.ts`. The NETWORK call is not here -- only the
 * mapping, which is the part that decides money and therefore the part that
 * belongs under vectors. A model's reply is untrusted input: every field is
 * optional, every number can be a string, a NaN or absent, and the difference
 * between handling that correctly and not is a bill that silently inflates.
 *
 * **One deliberate divergence from web, and it is the x100 again.** Web's
 * `toMinor` is `Math.round(value * 10 ** minorDigits)` with `minorDigits`
 * defaulting to 2, and no caller ever passes anything else -- so a JPY receipt
 * comes back a hundred times too large. This uses `fromMajor(major, currency)`.
 * For INR, USD and EUR the two are byte-identical; a vector pins the JPY case.
 *
 * Mirrors iOS's AiReceipt.swift.
 */

/** One line as the edge function's `emit_receipt` tool emits it. */
data class AiLine(
    val kind: String? = null,
    val description: String? = null,
    val quantity: Double? = null,
    val unit: String? = null,
    val unitPrice: Double? = null,
    val amount: Double? = null,
)

/** The `receipt` object in the edge function's reply. */
data class AiReceipt(
    val merchant: String? = null,
    val date: String? = null,
    val currency: String? = null,
    val total: Double? = null,
    val confidence: Double? = null,
    val lines: List<AiLine> = emptyList(),
)

/**
 * The kinds the ledger understands. Anything else the model invents is read as
 * an ordinary item rather than dropped -- an unrecognised kind on a real line
 * would otherwise remove money from the bill.
 */
private val VALID_KINDS = setOf("item", "tax", "service_charge", "tip", "discount")

/** Web's `/^\d{4}-\d{2}-\d{2}$/`. */
private val ISO_DAY = Regex("""^\d{4}-\d{2}-\d{2}$""")

private fun Double?.finite(): Boolean = this != null && !isNaN() && !isInfinite()

/**
 * One line, or null when there is no usable amount.
 *
 * Web drops a line whose `amount` is not a finite number, and so does this: a
 * line with no money on it is not a line, and inventing a zero would make the
 * reconciliation pass on a bill that was never read.
 */
private fun mapLine(raw: AiLine, index: Int, currency: String): ReceiptLine? {
    if (!raw.amount.finite()) return null
    val kind = if (raw.kind in VALID_KINDS) raw.kind!! else "item"
    val amount = fromMajor(raw.amount!!, currency).amount
    val description = raw.description.orEmpty().trim().ifEmpty { kind.replace("_", " ") }
    return ReceiptLine(
        id = "ai$index",
        kind = kind,
        description = description,
        quantity = if (raw.quantity.finite() && raw.quantity!! > 0) {
            jsRound(raw.quantity * QTY_SCALE).toLong()
        } else {
            null
        },
        // Web's `raw.unit ? ... : null` -- an EMPTY string is falsy and becomes
        // null, but a whitespace-only one is truthy and trims to "". Faithful
        // to the quirk because a vector pins it either way.
        unit = if (raw.unit.isNullOrEmpty()) null else raw.unit.trim().lowercase(),
        unitPrice = if (raw.unitPrice.finite()) fromMajor(raw.unitPrice!!, currency).amount else null,
        // Belt and braces, in web's own words: the prompt asks for negative
        // discounts, but a model that forgets must not silently inflate the bill.
        amount = if (kind == "discount") -abs(amount) else amount,
        confidence = 90,
    )
}

/**
 * The whole reply as a draft.
 *
 * [currencyHint] is the user's base currency, used when the model does not name
 * one. [currency] is what the AMOUNTS are denominated in -- normally the same
 * value, and separate only so a caller can be explicit about which of the two
 * decides the minor-unit scale.
 */
fun aiReceiptDraft(
    receipt: AiReceipt,
    currencyHint: String,
    rawText: String? = null,
): ReceiptDraft {
    val currency = (receipt.currency ?: currencyHint).uppercase()
    val lines = receipt.lines.mapIndexedNotNull { i, l -> mapLine(l, i, currency) }
    return ReceiptDraft(
        // Same falsy-empty quirk as `unit` above.
        merchant = if (receipt.merchant.isNullOrEmpty()) null else receipt.merchant.trim(),
        occurredAt = receipt.date?.takeIf { ISO_DAY.matches(it) },
        currency = currency,
        lines = lines,
        total = if (receipt.total.finite()) fromMajor(receipt.total!!, currency).amount else null,
        // Web clamps to 0..100 and rounds. A model that returns 130 confidence
        // is not 130% sure of anything.
        confidence = if (receipt.confidence.finite()) {
            max(0, min(100, jsRound(receipt.confidence!!).toInt()))
        } else {
            80
        },
        engine = "claude",
        rawText = rawText,
    )
}
