package com.sanvya.app.domain.receipts

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

// Ported from packages/core/receipts/src/parse.ts (P1.5a). Turning OCR
// output into a structured receipt. Every Regex pattern here is transcribed
// verbatim from the TS source -- see ReceiptsMoneyText.kt's header comment
// for why that transcription is trustworthy across Kotlin's java.util.regex
// and JS's engine.
//
// Guiding rule (mirrors the TS source): NEVER invent a number. Anything
// unsure of is left off and surfaced by reconcile() failing.

// ---------------------------------------------------------------------------
// Input shapes
// ---------------------------------------------------------------------------

data class OcrToken(val text: String, val x0: Double, val x1: Double, val y0: Double, val y1: Double, val confidence: Int)

data class TextLine(
    val text: String,
    val tokens: List<OcrToken>,
    /** Vertical centre, used only for ordering. */
    val y: Double,
    /** Mean token confidence, 0-100. */
    val confidence: Int,
)

/**
 * Rebuild lines from loose tokens.
 *
 * Tesseract's own line grouping gives up on the two- and three-column
 * layouts grocery bills use, so lines are regrouped by vertical overlap
 * using the median glyph height as tolerance -- adapts to image scale
 * instead of hard-coding pixels.
 */
fun groupIntoLines(tokens: List<OcrToken>): List<TextLine> {
    if (tokens.isEmpty()) return emptyList()

    val heights = tokens.map { max(1.0, it.y1 - it.y0) }.sorted()
    val medianHeight = heights[heights.size / 2]
    val tolerance = medianHeight * 0.6

    val sorted = tokens.sortedBy { (it.y0 + it.y1) / 2 }
    val rows = mutableListOf<MutableList<OcrToken>>()
    var current = mutableListOf<OcrToken>()
    var currentY = Double.NaN

    for (t in sorted) {
        val y = (t.y0 + t.y1) / 2
        if (current.isEmpty() || abs(y - currentY) <= tolerance) {
            current.add(t)
            // Running mean keeps a slightly skewed line from drifting away.
            currentY = if (currentY.isNaN()) y else (currentY * (current.size - 1) + y) / current.size
        } else {
            rows.add(current)
            current = mutableListOf(t)
            currentY = y
        }
    }
    if (current.isNotEmpty()) rows.add(current)

    return rows.map { row ->
        val ordered = row.sortedBy { it.x0 }
        TextLine(
            text = Regex("""\s+""").replace(ordered.joinToString(" ") { it.text }, " ").trim(),
            tokens = ordered,
            y = ordered.sumOf { (it.y0 + it.y1) / 2 } / ordered.size,
            confidence = (ordered.sumOf { it.confidence }.toDouble() / ordered.size).roundToLong().toInt(),
        )
    }
}

/** Wrap plain text (PDF text layer, or a paste) as lines with no geometry. */
fun linesFromText(text: String, confidence: Int = 100): List<TextLine> {
    return text.split(Regex("""\r?\n"""))
        .mapIndexed { i, raw -> TextLine(Regex("""\s+""").replace(raw, " ").trim(), emptyList(), i.toDouble(), confidence) }
        .filter { it.text.isNotEmpty() }
}

// ---------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------

/**
 * Lines that carry numbers but are NOT part of the bill's arithmetic.
 * Getting this list wrong is the most common way to double-count.
 */
private val IGNORE_PATTERNS: List<Regex> = listOf(
    Regex("""\b(cash|change|tendered|tender|card|visa|master(card)?|maestro|rupay|amex|upi|paytm|gpay|phonepe|wallet|pin|contactless)\b""", RegexOption.IGNORE_CASE),
    Regex("""\b(balance|due|payable\s*by|received|payment\s*mode|mode\s*of\s*payment)\b.*\b(card|cash|upi)\b""", RegexOption.IGNORE_CASE),
    Regex("""\b(gstin|gst\s*no|tin|pan|fssai|cin|vat\s*no|btw[\s-]*nr|tax\s*invoice|invoice\s*(no|#)|bill\s*(no|#)|order\s*(no|#)|receipt\s*(no|#)|token)\b""", RegexOption.IGNORE_CASE),
    Regex("""\b(thank\s*you|visit\s*again|welcome|customer\s*copy|merchant\s*copy|bedankt|dhanyavaad|have\s*a\s*(nice|great))\b""", RegexOption.IGNORE_CASE),
    Regex("""\b(table|server|waiter|cashier|counter|terminal|till|operator|staff)\b""", RegexOption.IGNORE_CASE),
    // NOTE: no trailing \b after "ph\s*[:.]" -- a word boundary cannot
    // follow a colon, which silently disables part of this alternation.
    // Transcribed verbatim from the TS source's own quirk, not "fixed".
    Regex("""\bphone\b|\btel\b|\bmob(ile)?\b|\bcontact\b|\bph\b\s*[:.]|www\.|https?:|@\w+\.(com|in|co|nl)""", RegexOption.IGNORE_CASE),
    Regex("""\b(total\s*(qty|items?|quantity|nos?\.?)|no\.?\s*of\s*items?|item\s*count|aantal)\b""", RegexOption.IGNORE_CASE),
    Regex("""\b(points?|loyalty|reward|membership|member\s*since|valid\s*(till|until))\b""", RegexOption.IGNORE_CASE),
    Regex("""\b(date|time|dated|datum|tijd|dinank)\b""", RegexOption.IGNORE_CASE),
    Regex("""\b(qty|quantity|aantal)\b\s*(x|rate|price|amount|amt)\b""", RegexOption.IGNORE_CASE), // column header row
    Regex("""^\s*[-=*_.~]{3,}\s*$"""), // separator rule
)

/**
 * Header-zone-only ignores. An address line is full of numbers and reads
 * exactly like an expensive item, but these words are also plausible
 * product names, so only suppressed near the top where the shop's own
 * details are printed.
 */
private val HEADER_NOISE_RE = Regex(
    """\b(road|rd|street|st|marg|nagar|sector|shop\s*no|shop|floor|plot|opp|near|layout|colony|cross|avenue|lane|block|straat|weg|pin\s*code)\b""",
    RegexOption.IGNORE_CASE,
)
private const val HEADER_ZONE_LINES = 5

/** A line that is essentially just a date, with no label and nothing else. */
private fun isBareDate(text: String): Boolean {
    if (findDate(text, "9999-12-31") == null) return false
    var rest = text
    rest = Regex("""\b\d{1,4}[/\-.]\d{1,2}[/\-.]\d{2,4}\b""").replace(rest, " ")
    rest = Regex("""\b\d{1,2}[\s\-][A-Za-z]{3,9}[\s\-,]+\d{2,4}\b""").replace(rest, " ")
    rest = Regex("""\b[A-Za-z]{3,9}[\s\-]\d{1,2}[\s\-,]+\d{2,4}\b""").replace(rest, " ")
    rest = Regex("""[^A-Za-z]""").replace(rest, "")
    return rest.length < 3
}

/** Running subtotals: recorded for cross-checking, never stored as a line. */
private val SUBTOTAL_RE = Regex(
    """\b(sub\s*-?\s*total|subtotal|subtotaal|tussentotaal|net\s*amount|taxable\s*(value|amount)|gross\s*amount|item\s*total)\b""",
    RegexOption.IGNORE_CASE,
)

/** The bill total. Checked AFTER subtotal so "sub total" can't win. */
private val TOTAL_RE = Regex(
    """\b(grand\s*total|net\s*payable|amount\s*payable|total\s*payable|bill\s*(amount|total)|invoice\s*total|total\s*amount|te\s*betalen|totaal|total)\b""",
    RegexOption.IGNORE_CASE,
)

private val KIND_PATTERNS: List<Pair<Regex, String>> = listOf(
    // Service charge before tax: "service charge" and "service tax" are
    // different things and only the second is a tax.
    Regex("""\b(service\s*(charge|chg|fee)|svc\s*(charge|chg)|delivery\s*(charge|fee)|packaging\s*(charge|fee)|packing\s*(charge|fee)|convenience\s*fee|handling\s*(charge|fee)|servicekosten|bedieningsgeld)\b""", RegexOption.IGNORE_CASE) to "service_charge",
    Regex("""\b(tip|gratuity|fooi)\b""", RegexOption.IGNORE_CASE) to "tip",
    Regex("""\b(c?gst|sgst|igst|ugst|vat|btw|service\s*tax|sales\s*tax|cess|tax|belasting)\b""", RegexOption.IGNORE_CASE) to "tax",
    Regex("""\b(discount|disc\b|savings?|coupon|promo|offer|less\b|off\b|redeem(ed)?|korting)\b""", RegexOption.IGNORE_CASE) to "discount",
)

private val ROUND_OFF_RE = Regex("""\bround(ed)?\s*(off|ing)?\b""", RegexOption.IGNORE_CASE)
private val CONTAINS_TOTAL_WORD = Regex("""total""", RegexOption.IGNORE_CASE)

private fun classify(text: String, isHeaderZone: Boolean): String {
    for (re in IGNORE_PATTERNS) if (re.containsMatchIn(text)) return "ignore"
    if (isBareDate(text)) return "ignore"
    if (isHeaderZone && HEADER_NOISE_RE.containsMatchIn(text)) return "ignore"
    if (SUBTOTAL_RE.containsMatchIn(text)) return "subtotal"
    // Round-off is a real adjustment to the total, so it must stay in the
    // maths, but it is not a "total" line even though some printers label
    // it as one.
    if (ROUND_OFF_RE.containsMatchIn(text) && !CONTAINS_TOTAL_WORD.containsMatchIn(text)) return "item"
    if (TOTAL_RE.containsMatchIn(text)) return "total"
    for ((re, kind) in KIND_PATTERNS) if (re.containsMatchIn(text)) return kind
    return "item"
}

// ---------------------------------------------------------------------------
// Quantity / unit price extraction
// ---------------------------------------------------------------------------

private data class QtyInfo(val quantity: Long?, val unit: String?, val unitPrice: Long?, val description: String)

private val QTY_PREFIX_RE = Regex("""^(\d+(?:[.,]\d+)?)\s*(?:x|\*|@)\s*(.+)$""", RegexOption.IGNORE_CASE)
private val QTY_SUFFIX_RE = Regex("""^(.+?)\s*(?:x|\*)\s*(\d+(?:[.,]\d+)?)$""", RegexOption.IGNORE_CASE)
private val TRAILING_DASH_RE = Regex("""[-–:|]+$""")
private val MONEYISH_ONLY_RE = Regex("""^[\d.,\s]+$""")
private val TRAIL_INT_RE = Regex("""^(.*[A-Za-z])\s+(\d{1,3})$""")
private val LEAD_INT_RE = Regex("""^(\d{1,2})\s+([A-Za-z][^\d]{2,})$""")
private val WHITESPACE_RE = Regex("""\s+""")

private fun toQty(s: String): Long = (s.replace(",", ".").toDouble() * QTY_SCALE).roundToLong()

/**
 * Work out quantity and unit price for an item line.
 *
 * The reliable signal is ARITHMETIC, not layout: if a line ends with three
 * numbers and the first two multiply to the third, they are unambiguously
 * qty x rate = amount.
 */
private fun extractQty(description: String, amount: Long, minorDigits: Int): QtyInfo {
    val base = QtyInfo(null, null, null, description.trim())
    var scale = 1L
    repeat(minorDigits) { scale *= 10 }
    val nums = findNumbers(description, minorDigits)

    // --- qty x rate = amount, verified by multiplication -------------------
    if (nums.size >= 2) {
        val rate = nums[nums.size - 1]
        val qty = nums[nums.size - 2]
        val qtyMajor = qty.value.toDouble() / scale
        if (qtyMajor > 0 && qtyMajor <= 1000) {
            val product = (qtyMajor * rate.value).roundToLong()
            // One minor unit of slack: printers round the extension, not the rate.
            if (abs(product - amount) <= 1) {
                val desc = TRAILING_DASH_RE.replace(description.substring(0, qty.start).trim(), "").trim()
                return QtyInfo(
                    quantity = (qtyMajor * QTY_SCALE).roundToLong(),
                    unit = findUnit(description),
                    unitPrice = rate.value,
                    description = desc.ifEmpty { base.description },
                )
            }
        }
    }

    // --- explicit "2 x Latte" / "Latte x 2" --------------------------------
    var m = QTY_PREFIX_RE.find(description)
    if (m != null) {
        val quantity = toQty(m.groupValues[1])
        val rest = m.groupValues[2].trim()
        // "2 x 60.00" is qty x rate, not a description.
        val asMoney = parseMoney(rest, minorDigits)
        if (asMoney != null && MONEYISH_ONLY_RE.matches(rest)) {
            return QtyInfo(quantity, findUnit(description), asMoney, base.description)
        }
        return QtyInfo(
            quantity = quantity,
            unit = findUnit(description),
            unitPrice = if (quantity > 0) ((amount.toDouble() * QTY_SCALE) / quantity).roundToLong() else null,
            description = rest,
        )
    }
    m = QTY_SUFFIX_RE.find(description)
    if (m != null) {
        val quantity = toQty(m.groupValues[2])
        return QtyInfo(
            quantity = quantity,
            unit = findUnit(description),
            unitPrice = if (quantity > 0) ((amount.toDouble() * QTY_SCALE) / quantity).roundToLong() else null,
            description = m.groupValues[1].trim(),
        )
    }

    // --- "1.5 kg Basmati Rice" ---------------------------------------------
    val unit = findUnit(description)
    if (unit != null) {
        // Regex.escape is defensive-only here: `unit` always comes from the
        // fixed UNIT_WORDS list (plain alphabetic text, no regex
        // metacharacters), so escaping is a no-op for matching purposes --
        // strictly safer than the TS source's raw interpolation, never
        // behaviorally different from it.
        val um = Regex("""(\d+(?:[.,]\d+)?)\s*${Regex.escape(unit)}\b""", RegexOption.IGNORE_CASE).find(description)
        if (um != null) {
            val quantity = toQty(um.groupValues[1])
            // replaceRange, not replace(string,string): JS's single-string
            // .replace() only replaces the FIRST occurrence, but Kotlin's
            // String.replace(String,String) replaces ALL occurrences --
            // replaceRange(range, ...) replaces exactly the matched span,
            // matching JS semantics exactly rather than accidentally
            // replacing every occurrence of an identical unit phrase
            // elsewhere in the description.
            val desc = WHITESPACE_RE.replace(description.replaceRange(um.range, " "), " ").trim()
            return QtyInfo(
                quantity = quantity,
                unit = unit,
                unitPrice = if (quantity > 0) ((amount.toDouble() * QTY_SCALE) / quantity).roundToLong() else null,
                description = desc.ifEmpty { base.description },
            )
        }
    }

    // --- trailing bare integer, e.g. "Paneer Tikka  1" ----------------------
    val trail = TRAIL_INT_RE.find(description)
    if (trail != null) {
        val quantity = toQty(trail.groupValues[2])
        if (quantity > 0) {
            return QtyInfo(
                quantity = quantity,
                unit = findUnit(description),
                unitPrice = ((amount.toDouble() * QTY_SCALE) / quantity).roundToLong(),
                description = trail.groupValues[1].trim(),
            )
        }
    }

    // --- leading small integer, e.g. "2 Masala Dosa" -----------------------
    val lead = LEAD_INT_RE.find(description)
    if (lead != null) {
        val quantity = toQty(lead.groupValues[1])
        return QtyInfo(
            quantity = quantity,
            unit = null,
            unitPrice = if (quantity > 0) ((amount.toDouble() * QTY_SCALE) / quantity).roundToLong() else null,
            description = lead.groupValues[2].trim(),
        )
    }

    return base
}

// ---------------------------------------------------------------------------
// Merchant
// ---------------------------------------------------------------------------

private val LETTER_RE = Regex("""[A-Za-z]""")
private val DIGIT_RE = Regex("""\d""")
private val MERCHANT_STRIP_RE = Regex("""[*_|]+""")

private fun findMerchant(lines: List<TextLine>): String? {
    // Merchants print their name big, at the top. Look only at the first
    // few lines and prefer the most name-like: mostly letters, few digits.
    val head = lines.take(6)
    var best: Pair<String, Double>? = null
    for (line in head) {
        val t = line.text.trim()
        if (t.length < 3 || t.length > 60) continue
        if (IGNORE_PATTERNS.any { it.containsMatchIn(t) }) continue
        val letters = LETTER_RE.findAll(t).count()
        val digits = DIGIT_RE.findAll(t).count()
        if (letters < 3 || digits > letters) continue
        val score = letters.toDouble() / t.length - digits.toDouble() / t.length
        if (best == null || score > best.second) best = t to score
    }
    return best?.first?.let { MERCHANT_STRIP_RE.replace(it, "").trim() }
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

data class ParseOptions(
    /** Fallback when the receipt doesn't print a currency. */
    val currency: String,
    val minorDigits: Int = 2,
    /** ISO date; dates after this are rejected as misreads. Defaults to today. */
    val today: String? = null,
    /** Prefix for the generated stable line ids. */
    val idPrefix: String = "l",
    val engine: String? = null,
)

private val DIGIT_2_TAIL_RE = Regex("""[.,]\d{1,2}$""")

fun parseReceipt(lines: List<TextLine>, opts: ParseOptions): ReceiptDraft {
    val minorDigits = opts.minorDigits
    val prefix = opts.idPrefix
    val fullText = lines.joinToString("\n") { it.text }

    val out = mutableListOf<ReceiptLine>()
    var total: Long? = null
    var subtotal: Long? = null
    var seq = 0

    for (i in lines.indices) {
        val line = lines[i]
        val text = line.text
        if (text.isEmpty()) continue

        val kind = classify(text, i < HEADER_ZONE_LINES)
        if (kind == "ignore") continue

        val nums = findNumbers(text, minorDigits)
        if (nums.isEmpty()) continue

        // The rightmost number on a line is the amount. Percentages, rates
        // and quantities all sit to its left on every receipt layout seen.
        val last = nums.last()
        val amount = last.value

        // Identifier guard: printed prices carry decimals. A long run of
        // digits with no decimal separator is a PIN code, phone number or
        // invoice reference, not a huge line item. Dropping it makes
        // reconciliation fail loudly, which is the outcome wanted over a
        // silent corruption.
        if (kind == "item" && !DIGIT_2_TAIL_RE.containsMatchIn(last.raw) && DIGIT_RE.findAll(last.raw).count() >= 5) {
            continue
        }
        if (kind == "total") {
            // Prefer the LAST total-ish line: printers put "Total" then "Grand Total".
            total = amount
            continue
        }
        if (kind == "subtotal") {
            subtotal = amount
            continue
        }

        val description = tidyDescription(text.substring(0, last.start))
        // A bare number with no label is noise (page numbers, stray marks).
        if (description.isEmpty() && kind == "item") continue

        if (kind == "item") {
            val q = extractQty(description, amount, minorDigits)
            out.add(
                ReceiptLine(
                    id = "$prefix${seq++}",
                    kind = "item",
                    description = q.description.ifEmpty { description },
                    quantity = q.quantity,
                    unit = q.unit,
                    unitPrice = q.unitPrice,
                    amount = amount,
                    confidence = line.confidence,
                )
            )
        } else {
            // Charges: discounts are stored negative regardless of how they print.
            out.add(
                ReceiptLine(
                    id = "$prefix${seq++}",
                    kind = kind,
                    description = description.ifEmpty { kind.replace("_", " ") },
                    quantity = null,
                    unit = null,
                    unitPrice = null,
                    amount = if (kind == "discount") -abs(amount) else amount,
                    confidence = line.confidence,
                )
            )
        }
    }

    val computed = out.sumOf { it.amount }
    // If no total was printed but a subtotal was, and the lines agree with
    // the subtotal, the arithmetic can be trusted and the total derived.
    if (total == null && subtotal != null) {
        val itemsOnly = out.filter { it.kind == "item" }.sumOf { it.amount }
        if (itemsOnly == subtotal) total = computed
    }

    val meanConfidence = if (lines.isNotEmpty()) {
        (lines.sumOf { it.confidence }.toDouble() / lines.size).roundToLong().toInt()
    } else 0

    return ReceiptDraft(
        merchant = findMerchant(lines),
        occurredAt = findDate(fullText, opts.today),
        currency = detectCurrency(fullText) ?: opts.currency,
        lines = out,
        total = total,
        confidence = scoreConfidence(meanConfidence, out.size, total, computed),
        engine = opts.engine ?: "tesseract",
        rawText = fullText,
    )
}

/** Convenience wrapper for a PDF text layer or pasted text. */
fun parseReceiptText(text: String, opts: ParseOptions): ReceiptDraft {
    return parseReceipt(linesFromText(text), opts.copy(engine = opts.engine ?: "pdf_text"))
}

/**
 * Blend raw OCR confidence with structural evidence. OCR confidence alone
 * is a poor predictor; whether the numbers ADD UP is a much stronger
 * signal, so it dominates the score.
 */
private fun scoreConfidence(ocrConfidence: Int, lineCount: Int, total: Long?, computed: Long): Int {
    if (lineCount == 0) return 0
    var score = ocrConfidence * 0.5
    if (total != null) {
        score += 20
        if (total == computed) {
            score += 30
        } else {
            // Near-misses are more recoverable than wild ones.
            val drift = abs(total - computed).toDouble() / max(1.0, abs(total).toDouble())
            score += if (drift < 0.05) 12.0 else if (drift < 0.2) 5.0 else 0.0
        }
    }
    if (lineCount >= 3) score += 5
    return max(0.0, min(100.0, score.roundToLong().toDouble())).toInt()
}
