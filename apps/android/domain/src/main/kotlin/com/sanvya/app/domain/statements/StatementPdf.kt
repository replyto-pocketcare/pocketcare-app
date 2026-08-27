package com.sanvya.app.domain.statements

import com.sanvya.app.domain.money.fromMajor
import kotlin.math.abs

/**
 * PDF statement parsing — the pure half.
 *
 * Ported from `apps/web/src/statements/parsePdf.ts`. Web's module does two
 * things: it drives pdf.js to get positioned text, and then it parses. Only the
 * SECOND half is here, because the first has no shared shape — pdf.js in a
 * browser, PDFBox on Android, PDFKit on iOS — and mixing them would put the
 * platform-specific part somewhere it cannot be vector-tested.
 *
 * Two parsers, in order of preference:
 *
 * 1. [parseStatementPdfRows] is COLUMN-AWARE. It keeps each text fragment's
 *    x-position and assigns every money cell to the nearest numeric column, so
 *    Withdrawal / Deposit / Balance keep their meaning — which is how Indian
 *    bank PDFs actually lay them out. Guessing the sign from a flattened line
 *    gets refunds and salary credits backwards.
 * 2. [parseStatementPdfText] is the line heuristic, for when no header is
 *    found. It says so in a warning, because it is genuinely less reliable and
 *    the user has a better option (the CSV export).
 */

/** One positioned text fragment. */
data class PdfCell(val x: Double, val str: String)

/** One visual line: cells ordered left → right. */
typealias PdfRow = List<PdfCell>

/**
 * One positioned glyph, as a platform's PDF library hands it over.
 *
 * [y] is TOP-DOWN (larger = further down the page). PDFBox's `getYDirAdj()`
 * already is; PDFKit's page space is bottom-up, so its extractor flips it. Web
 * doesn't need this type at all — pdf.js emits ready-made text runs — which is
 * exactly why [groupPdfGlyphs] exists here instead of in each app.
 */
data class PdfGlyph(val x: Double, val y: Double, val width: Double, val text: String)

/**
 * Baselines within this many points are the same visual line.
 *
 * Web's own bucket, from `parsePdf.ts`: superscripts, a slightly-raised currency
 * symbol and ordinary rounding all move a baseline by a point or so, and none of
 * them start a new row.
 */
const val PDF_ROW_BUCKET_PT = 2.0

/**
 * A horizontal gap wider than this fraction of a glyph starts a new cell.
 *
 * Erring towards MORE cells is deliberate. An over-split narration is rejoined
 * with a space and reads the same; an under-split one glues a money cell to
 * letters, [isMoney] then rejects it, and the whole transaction row is silently
 * dropped.
 */
const val PDF_CELL_GAP_RATIO = 0.35

/** Floor for that gap test, so a zero-width glyph can't split on every step. */
const val PDF_CELL_GAP_MIN_PT = 0.5

/** `Math.round` — half UP, not half-to-even and not half-away-from-zero. */
private fun jsRound(v: Double): Double = kotlin.math.floor(v + 0.5)

/**
 * Group positioned glyphs into rows of cells — the shared half of extraction.
 *
 * This is the piece web does not have: pdf.js hands back text RUNS already,
 * while PDFBox and PDFKit hand back glyphs. Doing the grouping in each app would
 * mean the two phones disagreed about where a cell ends, and therefore about a
 * narration's spacing and occasionally about a whole row. So each platform's
 * extractor contributes nothing but ordered, positioned glyphs and this decides
 * the rest, identically, under vector test.
 */
fun groupPdfGlyphs(glyphs: List<PdfGlyph>): List<PdfRow> {
    val byRow = LinkedHashMap<Double, MutableList<PdfGlyph>>()
    for (g in glyphs) {
        if (g.text.isEmpty()) continue
        val key = jsRound(g.y / PDF_ROW_BUCKET_PT) * PDF_ROW_BUCKET_PT
        byRow.getOrPut(key) { mutableListOf() }.add(g)
    }

    return byRow.entries
        .sortedBy { it.key } // top-down
        .map { (_, gs) -> rowFromGlyphs(gs.sortedBy { it.x }) }
        .filter { it.isNotEmpty() }
}

private fun rowFromGlyphs(sorted: List<PdfGlyph>): PdfRow {
    val cells = mutableListOf<PdfCell>()
    var text = StringBuilder()
    var cellX = 0.0
    var prevEnd = 0.0
    var prevWidth = 0.0

    fun flush() {
        val t = text.toString().trim()
        if (t.isNotEmpty()) cells.add(PdfCell(cellX, t))
        text = StringBuilder()
    }

    for (g in sorted) {
        if (text.isEmpty()) {
            cellX = g.x
        } else {
            val threshold = PDF_CELL_GAP_RATIO * maxOf(g.width, prevWidth)
            if (g.x - prevEnd > maxOf(threshold, PDF_CELL_GAP_MIN_PT)) {
                flush()
                cellX = g.x
            }
        }
        text.append(g.text)
        prevEnd = g.x + g.width
        prevWidth = g.width
    }
    flush()
    return cells
}

private val HDR_DATE = Regex("\\bdate\\b", RegexOption.IGNORE_CASE)
private val HDR_DESC = Regex("narration|description|particular|remarks|details|transaction remarks", RegexOption.IGNORE_CASE)
private val HDR_DEBIT = Regex("debit|withdrawal|withdrawl", RegexOption.IGNORE_CASE)
private val HDR_CREDIT = Regex("credit|deposit", RegexOption.IGNORE_CASE)
private val HDR_AMOUNT = Regex("^\\s*amount\\b", RegexOption.IGNORE_CASE)
private val HDR_BALANCE = Regex("balance", RegexOption.IGNORE_CASE)
private val HDR_DRCR = Regex("^(dr/?cr|type|indicator)$", RegexOption.IGNORE_CASE)

/** Roles in web's own declaration order — the first match wins, so it matters. */
private val ROLES = listOf(
    "date" to HDR_DATE,
    "desc" to HDR_DESC,
    "debit" to HDR_DEBIT,
    "credit" to HDR_CREDIT,
    "amount" to HDR_AMOUNT,
    "balance" to HDR_BALANCE,
    "drcr" to HDR_DRCR,
)

/**
 * A deliberately different number reader from [statementNum].
 *
 * Web keeps two, and the difference is real: this one strips commas
 * unconditionally (`[^0-9.\-]`), so it has none of the European-decimal
 * behaviour the CSV one reproduces. A PDF's money cells are already
 * `1,234.56`-shaped by the time pdf.js hands them over.
 */
private fun pdfNum(s: String): Double {
    val cleaned = s.replace(Regex("[^0-9.\\-]"), "")
    // `Number.parseFloat`, not `Number`: a leading numeric prefix wins and the
    // rest is dropped, so "12.34.56" is 12.34 on every platform rather than 0
    // on one of them.
    val n = jsParseFloat(cleaned)
    return if (n != null && n.isFinite()) n else 0.0
}

/**
 * A cell that looks like money: digits with exactly two decimals, and no word
 * in it once Dr/Cr is discounted. The letter test is what keeps "Balance as on
 * 01.04.2026" out of the amount columns.
 */
private fun isMoney(s: String): Boolean =
    Regex("\\d[\\d,]*\\.\\d{2}\\b").containsMatchIn(s) &&
        !Regex("[a-z]{3,}", RegexOption.IGNORE_CASE).containsMatchIn(s.replace(Regex("dr|cr", RegexOption.IGNORE_CASE), ""))

private data class HeaderCol(val role: String, val x: Double)

/** Find the header row and each detected column's x-position. */
private fun detectPdfHeader(rows: List<PdfRow>): Pair<Int, List<HeaderCol>> {
    var bestIdx = -1
    var bestCols: List<HeaderCol> = emptyList()
    rows.take(40).forEachIndexed { i, row ->
        val seen = mutableSetOf<String>()
        val cols = mutableListOf<HeaderCol>()
        for (cell in row) {
            for ((role, rx) in ROLES) {
                if (!seen.contains(role) && rx.containsMatchIn(cell.str)) {
                    seen.add(role)
                    cols.add(HeaderCol(role, cell.x))
                    break
                }
            }
        }
        if (cols.size > bestCols.size) {
            bestCols = cols
            bestIdx = i
        }
    }
    return bestIdx to bestCols.sortedBy { it.x }
}

/** Nearest column by x among a candidate set of roles. */
private fun nearestRole(cols: List<HeaderCol>, roles: Set<String>, x: Double): String? {
    var best: String? = null
    var bestD = Double.MAX_VALUE
    for (c in cols) {
        if (c.role !in roles) continue
        val d = abs(c.x - x)
        if (d < bestD) { bestD = d; best = c.role }
    }
    return best
}

internal const val WARN_PDF_COLUMNS =
    "PDF parsed with column detection — review a few rows to be sure the debits/credits look right."
internal const val WARN_PDF_LINES =
    "Couldn't detect statement columns — parsed line-by-line (less reliable). Review amounts, or try the CSV/Excel export."
internal const val WARN_PDF_NOTHING =
    "Couldn't read any transactions — this may be a scanned image (needs OCR) or an unusual layout. Try the CSV/Excel export instead."

/**
 * Column-aware parse. Returns null when no usable header was found, so the
 * caller can fall back to [parseStatementPdfText].
 */
fun parseStatementPdfRows(rows: List<PdfRow>, currency: String, kind: String): ParsedStatement? {
    val (headerIdx, cols) = detectPdfHeader(rows)
    val roles = cols.map { it.role }.toSet()
    val hasNumeric = "debit" in roles || "credit" in roles || "amount" in roles
    if (headerIdx < 0 || cols.size < 2 || !hasNumeric) return null

    val numericRoles = listOf("debit", "credit", "amount", "balance").filter { it in roles }.toSet()
    val firstNumX = cols.filter { it.role in numericRoles }.minOf { it.x }
    val drcrX = cols.find { it.role == "drcr" }?.x

    val txns = mutableListOf<StatementTxn>()
    for (row in rows.drop(headerIdx + 1)) {
        // A transaction row has a date somewhere near the start.
        val dateCell = row.firstOrNull { parseStatementDate(it.str) != null } ?: continue
        val date = parseStatementDate(dateCell.str) ?: continue

        var debit = 0.0
        var credit = 0.0
        var amount = 0.0
        var balance = 0.0
        var drcr = ""
        val descParts = mutableListOf<String>()

        for (cell in row) {
            if (cell === dateCell) continue
            if (isMoney(cell.str)) {
                val v = pdfNum(cell.str)
                when (nearestRole(cols, numericRoles, cell.x)) {
                    "debit" -> debit = v
                    "credit" -> credit = v
                    "balance" -> balance = v
                    "amount" -> amount = v
                }
                if (Regex("\\bcr\\b", RegexOption.IGNORE_CASE).containsMatchIn(cell.str)) drcr = "cr"
                else if (Regex("\\bdr\\b", RegexOption.IGNORE_CASE).containsMatchIn(cell.str)) drcr = "dr"
            } else if (drcrX != null && abs(cell.x - drcrX) < 12 &&
                Regex("^(dr|cr)$", RegexOption.IGNORE_CASE).matches(cell.str.trim())
            ) {
                drcr = cell.str.trim().lowercase()
            } else if (cell.x < firstNumX - 4) {
                // Left of the numeric columns = narration.
                descParts.add(cell.str)
            }
        }

        val signed = when {
            "debit" in roles || "credit" in roles -> credit - debit
            amount != 0.0 -> when (drcr) {
                "cr" -> abs(amount)
                "dr" -> -abs(amount)
                // Neither marker: a bare amount column on a bank statement is a
                // debit far more often than not, and web assumes the same.
                else -> -amount
            }
            else -> 0.0
        }
        if (signed == 0.0) continue

        txns.add(
            StatementTxn(
                date = date,
                description = descParts.joinToString(" ").replace(Regex("\\s+"), " ").trim()
                    .ifEmpty { DEFAULT_DESCRIPTION },
                // fromMajor, not `* 100` -- web bug #8's fifth site.
                amount = fromMajor(signed, currency).amount,
                balance = if ("balance" in roles && balance != 0.0) fromMajor(balance, currency).amount else null,
            ),
        )
    }
    if (txns.isEmpty()) return null

    val dates = txns.map { it.date }.sorted()
    return ParsedStatement(
        kind = kind,
        label = if (kind == "card") LABEL_CARD else LABEL_BANK,
        currency = currency,
        period = StatementPeriod(dates.firstOrNull(), dates.lastOrNull()),
        openingBalance = txns.firstOrNull { it.balance != null }?.balance,
        closingBalance = txns.lastOrNull { it.balance != null }?.balance,
        txns = txns,
        warnings = listOf(WARN_PDF_COLUMNS),
    )
}

private val MONEY_RX = Regex("(?:₹|inr|rs\\.?)?\\s?(-?\\d[\\d,]*\\.\\d{2})(?:\\s?(dr|cr))?", RegexOption.IGNORE_CASE)
private val LEADING_DATE_RX = Regex(
    "^\\s*(\\d{1,2}[/\\-.]\\d{1,2}[/\\-.]\\d{2,4}|\\d{4}-\\d{2}-\\d{2}|\\d{1,2}[-\\s][A-Za-z]{3}[A-Za-z]*[-\\s']\\d{2,4})",
)
private val CREDIT_WORDS = Regex(
    "salary|refund|reversal|received|credit|cashback|interest|neft cr|imps cr",
    RegexOption.IGNORE_CASE,
)

/** Fallback: parse flattened text lines when column detection fails. */
fun parseStatementPdfText(text: String, currency: String, kind: String): ParsedStatement {
    val txns = mutableListOf<StatementTxn>()
    val warnings = mutableListOf(WARN_PDF_LINES)

    for (line in text.split("\n")) {
        val dm = LEADING_DATE_RX.find(line) ?: continue
        val date = parseStatementDate(dm.groupValues[1]) ?: continue
        val monies = MONEY_RX.findAll(line).toList()
        if (monies.isEmpty()) continue

        val nums = monies.map { m ->
            (m.groupValues[1].replace(",", "").toDoubleOrNull() ?: 0.0) to m.groupValues[2].lowercase()
        }
        // Two or more numbers on the line means the LAST is the running balance
        // and the one before it is the amount. One number is just the amount.
        val balance = if (nums.size >= 2) nums.last().first else null
        val amtTok = if (nums.size >= 2) nums[nums.size - 2] else nums[0]
        val rest = MONEY_RX.replace(line.substring(dm.value.length), "").replace(Regex("\\s+"), " ").trim()

        val credit = amtTok.second == "cr" || CREDIT_WORDS.containsMatchIn(rest)
        val signed = if (credit) abs(amtTok.first) else -abs(amtTok.first)

        txns.add(
            StatementTxn(
                date = date,
                description = rest.ifEmpty { DEFAULT_DESCRIPTION },
                amount = fromMajor(signed, currency).amount,
                balance = balance?.let { fromMajor(it, currency).amount },
            ),
        )
    }

    if (txns.isEmpty()) warnings.add(WARN_PDF_NOTHING)
    val dates = txns.map { it.date }.sorted()
    return ParsedStatement(
        kind = kind,
        label = if (kind == "card") LABEL_CARD else LABEL_BANK,
        currency = currency,
        period = StatementPeriod(dates.firstOrNull(), dates.lastOrNull()),
        openingBalance = txns.firstOrNull { it.balance != null }?.balance,
        closingBalance = txns.lastOrNull { it.balance != null }?.balance,
        txns = txns,
        warnings = warnings,
    )
}

/** Flatten positioned rows to text lines — the fallback's input, and useful for debugging. */
fun pdfRowsToText(rows: List<PdfRow>): String = rows
    .map { r -> r.joinToString(" ") { it.str }.replace(Regex("\\s+"), " ").trim() }
    .filter { it.isNotEmpty() }
    .joinToString("\n")

/**
 * Parse extracted rows: column-aware first, line heuristic as fallback.
 *
 * Takes ROWS, not a file. Getting the rows is the platform's job — see each
 * app's `PdfTextExtractor`.
 */
fun parsePdfStatement(rows: List<PdfRow>, currency: String, kind: String): ParsedStatement =
    parseStatementPdfRows(rows, currency, kind)?.takeIf { it.txns.isNotEmpty() }
        ?: parseStatementPdfText(pdfRowsToText(rows), currency, kind)

/**
 * The whole pipeline, and the only entry point an app needs: positioned glyphs
 * in, a parsed statement out.
 *
 * Everything between here and the platform's PDF library is shared and vector-
 * tested, so an extractor is done as soon as it can produce ordered [PdfGlyph]s.
 */
fun parsePdfStatementFromGlyphs(glyphs: List<PdfGlyph>, currency: String, kind: String): ParsedStatement =
    parsePdfStatement(groupPdfGlyphs(glyphs), currency, kind)
