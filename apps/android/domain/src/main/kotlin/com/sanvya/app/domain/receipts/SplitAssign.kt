package com.sanvya.app.domain.receipts

import com.sanvya.app.domain.csv.jsParseFloat
import com.sanvya.app.domain.money.minorUnits
import kotlin.math.abs

/**
 * The per-item split screen's logic, lifted out of the screen.
 *
 * Ported from the two pure functions at the bottom of
 * `apps/web/app/receipts/split/page.tsx` (`weightFor`, `validateLine`) plus the
 * mode lists and the two text helpers from `src/receipts/draft.ts` that only
 * that screen uses.
 *
 * They are here, not in the view models, because they are the part that decides
 * whether a bill is allowed to be written at all — "shares are off by ₹0.01"
 * has to mean the same thing on three clients, and it is the exact sort of
 * arithmetic that quietly drifts when it lives in a UI file twice.
 *
 * Validation returns a SHAPE, not a sentence: [LineProblem] carries the numbers
 * and the UI formats them through its own i18n. Same rule as `timeAgo` —
 * Domain never holds `Resources`.
 */

/** Modes offered for goods. `quantity` only appears when there is a quantity. */
val ITEM_SPLIT_MODES_FOR_ITEMS: List<String> = listOf("equal", "quantity", "exact", "percent")

/** Modes offered for tax / service charge / tip / discount. */
val ITEM_SPLIT_MODES_FOR_CHARGES: List<String> = listOf("proportional", "equal", "exact", "percent")

/** Which modes this line may be divided by. */
fun splitModesFor(line: ReceiptLine): List<String> = if (isCharge(line.kind)) {
    ITEM_SPLIT_MODES_FOR_CHARGES
} else {
    ITEM_SPLIT_MODES_FOR_ITEMS.filter { it != "quantity" || (line.quantity ?: 0L) > 0L }
}

/** Milli-units back to a plain count: 1500 -> 1.5. */
fun qtyToMajor(milli: Long): Double = milli.toDouble() / QTY_SCALE

/**
 * Minor-unit decimal places for a currency, defaulting to 2.
 *
 * Web wraps `minorUnits` in a try/catch here because its `Intl` path throws on
 * an unknown code; both native ports already default to 2 internally, so this
 * is a rename rather than a behaviour change — kept as its own name so the
 * screen reads the same on all three.
 */
fun receiptDigits(currency: String): Int = minorUnits(currency)

/**
 * `"12.34"` -> `1234`. Blank or garbage becomes 0 rather than NaN.
 *
 * A comma is accepted as a decimal separator, which is web's behaviour and is
 * deliberate: the on-screen keypad in several locales offers a comma.
 */
fun minorFromText(value: String, digits: Int): Long {
    val n = jsParseFloat(value.replace(",", ".")) ?: return 0L
    // Math.round, not roundToLong: JS breaks ties toward +Infinity and Kotlin
    // breaks them away from zero, which disagree on every negative half.
    return Math.round(n * pow10(digits))
}

/** `1234` -> `"12.34"`, for populating an editable input. */
fun majorTextFromMinor(minor: Long, digits: Int): String =
    // Locale.ROOT, or a comma-decimal locale turns "12.34" into "12,34" and the
    // text goes back through minorFromText as a different number.
    String.format(java.util.Locale.ROOT, "%.${digits}f", minor.toDouble() / pow10(digits))

private fun pow10(digits: Int): Double {
    var out = 1.0
    repeat(digits) { out *= 10.0 }
    return out
}

/**
 * Translate a raw input string into the weight the allocator expects.
 *
 * `null` means "this mode carries no weight" (equal / proportional), which is
 * what `allocateReceipt` reads as "divide it yourself".
 */
fun lineWeight(mode: String, raw: String?, lineAmount: Long, digits: Int): Double? {
    if (mode == "equal" || mode == "proportional") return null
    if (raw == null || raw.isBlank()) return 0.0
    if (mode == "exact") {
        // Exact weights are minor units and must carry the line's SIGN, so a
        // discount can be split exactly too.
        val v = minorFromText(raw, digits)
        return if (lineAmount < 0) -abs(v).toDouble() else v.toDouble()
    }
    val n = jsParseFloat(raw.replace(",", ".")) ?: return 0.0
    if (!n.isFinite() || n < 0) return 0.0
    return if (mode == "percent") {
        Math.round(n * PERCENT_SCALE).toDouble()
    } else {
        Math.round(n * QTY_SCALE).toDouble()
    }
}

/**
 * Why one line cannot be saved, or null when it is fine.
 *
 * Carries numbers, not sentences — see this file's header.
 */
sealed class LineProblem {
    /** Nobody is on this line. */
    data object NeedsSomeone : LineProblem()

    /** Exact shares do not sum to the line total. [diffMinor] is what is left over. */
    data class ExactMismatch(val diffMinor: Long) : LineProblem()

    /** Percentages do not sum to 100. [pct] is what they DO sum to, rounded. */
    data class PercentMismatch(val pct: Int) : LineProblem()

    /** Quantities do not sum to the line's quantity. Both are milli-units. */
    data class QuantityMismatch(val gotMilli: Long, val wantMilli: Long) : LineProblem()
}

/** Validate one line's assignment. Null means it is ready to save. */
fun validateSplitLine(
    line: ReceiptLine,
    mode: String,
    members: List<String>,
    weights: Map<String, String>,
    digits: Int,
): LineProblem? {
    if (members.isEmpty()) return LineProblem.NeedsSomeone

    if (mode == "exact") {
        var sum = 0L
        for (uid in members) {
            val v = minorFromText(weights[uid] ?: "", digits)
            sum += if (line.amount < 0) -abs(v) else v
        }
        if (sum != line.amount) return LineProblem.ExactMismatch(line.amount - sum)
    }

    if (mode == "percent") {
        var sum = 0.0
        for (uid in members) sum += jsParseFloat((weights[uid] ?: "").replace(",", ".")) ?: 0.0
        // Math.round again -- see minorFromText.
        val pct = Math.round(sum).toInt()
        if (pct != 100) return LineProblem.PercentMismatch(pct)
    }

    val quantity = line.quantity
    if (mode == "quantity" && quantity != null) {
        var sum = 0.0
        for (uid in members) sum += jsParseFloat((weights[uid] ?: "").replace(",", ".")) ?: 0.0
        val gotMilli = Math.round(sum * QTY_SCALE)
        if (gotMilli != quantity) return LineProblem.QuantityMismatch(gotMilli, quantity)
    }

    return null
}
