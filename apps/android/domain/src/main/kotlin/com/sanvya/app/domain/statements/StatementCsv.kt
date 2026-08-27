package com.sanvya.app.domain.statements

import com.sanvya.app.domain.money.fromMajor

/**
 * Generic bank/card statement CSV parser.
 *
 * Ported from `apps/web/src/statements/parseCsv.ts`. Rather than hard-coding
 * every Indian bank it auto-detects the header row and maps columns by keyword
 * (date / narration / debit / credit / amount / balance), which covers the
 * common shape used by HDFC, ICICI, SBI, Axis, Kotak and the rest. The mapping
 * comes back with the result so the UI can show it and let the user correct a
 * wrong guess.
 */

/**
 * Minimal CSV → rows, with quotes and embedded commas/newlines.
 *
 * Deliberately NOT `domain.csv.parseCsv`. That one is the app's own
 * export/import format: it detects only comma vs semicolon, reads the delimiter
 * off the first line whether or not that line is blank, and has no reason to
 * know about tabs. A bank's "CSV" is frequently tab-separated and frequently
 * opens with several blank or title rows. Web keeps two parsers for exactly
 * these reasons; so do the ports.
 */
internal fun parseStatementRows(text: String): List<List<String>> {
    val src = text.removePrefix("﻿").replace("\r\n", "\n")
    val firstLine = src.split("\n").firstOrNull { it.isNotBlank() } ?: ""
    val delim: Char = when {
        firstLine.contains('\t') -> '\t'
        firstLine.count { it == ';' } > firstLine.count { it == ',' } -> ';'
        else -> ','
    }
    val rows = mutableListOf<List<String>>()
    var row = mutableListOf<String>()
    val field = StringBuilder()
    var inQuotes = false
    var i = 0
    while (i < src.length) {
        val ch = src[i]
        if (inQuotes) {
            if (ch == '"') {
                if (i + 1 < src.length && src[i + 1] == '"') {
                    field.append('"'); i++
                } else {
                    inQuotes = false
                }
            } else {
                field.append(ch)
            }
        } else when (ch) {
            '"' -> inQuotes = true
            delim -> { row.add(field.toString()); field.clear() }
            '\n' -> { row.add(field.toString()); rows.add(row); row = mutableListOf(); field.clear() }
            else -> field.append(ch)
        }
        i++
    }
    if (field.isNotEmpty() || row.isNotEmpty()) {
        row.add(field.toString())
        rows.add(row)
    }
    return rows
}

private val RX_DATE = Regex("(^|\\b)(date|txn date|value date|transaction date|posting date|tran date)\\b", RegexOption.IGNORE_CASE)
private val RX_DESC = Regex("(narration|description|particular|remarks|details|transaction remarks|merchant|transaction detail)", RegexOption.IGNORE_CASE)
private val RX_DEBIT = Regex("(debit|withdrawal|withdrawl|paid out|dr amount|amount\\s*\\(dr\\)|withdrawal amt)", RegexOption.IGNORE_CASE)
private val RX_CREDIT = Regex("(credit|deposit|paid in|cr amount|amount\\s*\\(cr\\)|deposit amt)", RegexOption.IGNORE_CASE)
private val RX_AMOUNT = Regex("^(amount|txn amount|transaction amount|amount\\s*\\(inr\\))$", RegexOption.IGNORE_CASE)
private val RX_BALANCE = Regex("(balance|closing balance|running balance|available balance)", RegexOption.IGNORE_CASE)
private val RX_DRCR = Regex("^(dr/?cr|type|transaction type|debit/credit|indicator)$", RegexOption.IGNORE_CASE)

/**
 * Tolerant number: strips symbols and thousands separators, keeps sign and
 * decimal point.
 *
 * **This reproduces a web bug on purpose.** `"1.234,56"` — one thousand two
 * hundred and thirty-four — comes back as `1.23456`, because the
 * thousands-comma strip only fires when three digits follow, the decimal comma
 * therefore survives, and the final blanket comma-strip deletes it. It is the
 * SAME defect as `data/adapters.ts`'s `num()` (PARITY_AUDIT web bug #4), in a
 * second parser.
 *
 * It is reproduced rather than fixed for the reason recorded against #4: a
 * silent divergence on an amount — the browser importing €1.23 and the phone
 * €1,234.56 from the same file — is worse than a shared bug, and the vector
 * pinning it here fails loudly the day web is fixed.
 */
internal fun statementNum(v: String?): Double {
    if (v.isNullOrEmpty()) return 0.0
    val cleaned = v.replace(Regex("[^0-9.,\\-]"), "").replace(Regex(",(?=\\d{3}(\\D|$))"), "")
    val norm = if (cleaned.contains(",") && !cleaned.contains(".")) {
        cleaned.replaceFirst(",", ".")
    } else {
        cleaned.replace(",", "")
    }
    val n = jsParseFloatLocal(norm)
    return if (n != null && n.isFinite()) n else 0.0
}

/**
 * `Number.parseFloat` semantics: a leading numeric prefix wins and the rest is
 * ignored. Kotlin's `toDoubleOrNull` requires the whole string, and a bank cell
 * really does contain things like "1,234.56 Cr".
 */
private fun jsParseFloatLocal(s: String): Double? {
    val m = Regex("^[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?").find(s) ?: return null
    return m.value.toDoubleOrNull()
}

private val MONTHS = mapOf(
    "jan" to 1, "feb" to 2, "mar" to 3, "apr" to 4, "may" to 5, "jun" to 6,
    "jul" to 7, "aug" to 8, "sep" to 9, "oct" to 10, "nov" to 11, "dec" to 12,
)

private fun iso(y: Int, mo: Int, d: Int): String =
    "%04d-%02d-%02d".format(java.util.Locale.ROOT, y, mo, d)

/**
 * Parse the many date formats a bank prints → ISO `YYYY-MM-DD`, or null.
 *
 * **Day-first**, deliberately: `03/04/2026` is the 3rd of April on every Indian
 * statement this parser exists for. There is no way to tell it from March 4th
 * without knowing the issuer, and guessing month-first would silently move a
 * third of every statement's rows.
 */
fun parseStatementDate(s: String?): String? {
    if (s.isNullOrEmpty()) return null
    val v = s.trim()

    Regex("^(\\d{4})-(\\d{2})-(\\d{2})").find(v)?.let { m ->
        return "${m.groupValues[1]}-${m.groupValues[2]}-${m.groupValues[3]}"
    }
    Regex("^(\\d{1,2})[/\\-.](\\d{1,2})[/\\-.](\\d{2,4})").find(v)?.let { m ->
        val d = m.groupValues[1].toInt()
        val mo = m.groupValues[2].toInt()
        val yRaw = m.groupValues[3]
        val y = if (yRaw.length == 2) 2000 + yRaw.toInt() else yRaw.toInt()
        if (mo in 1..12 && d in 1..31) return iso(y, mo, d)
    }
    Regex("^(\\d{1,2})[-\\s]([A-Za-z]{3})[A-Za-z]*[-\\s'](\\d{2,4})").find(v)?.let { m ->
        val d = m.groupValues[1].toInt()
        val mo = MONTHS[m.groupValues[2].lowercase()]
        val yRaw = m.groupValues[3]
        val y = if (yRaw.length == 2) 2000 + yRaw.toInt() else yRaw.toInt()
        if (mo != null && d in 1..31) return iso(y, mo, d)
    }
    return null
}

private data class Detected(val headerRow: Int, val mapping: ColumnMapping, val drcrCol: Int?)

/**
 * Find the header row — the one in the first 25 with the most keyword hits —
 * and map its columns.
 *
 * The 25-row scan is not arbitrary: bank exports routinely open with a title,
 * an address block, an account summary and a blank line or six before the
 * table starts.
 */
private fun detectMapping(rows: List<List<String>>): Detected {
    var best = -1
    var bestScore = 0
    var bestMap: ColumnMapping? = null
    var bestDrcr: Int? = null
    rows.take(25).forEachIndexed { i, row ->
        var map = ColumnMapping()
        var drcr: Int? = null
        var score = 0
        row.forEachIndexed { ci, cell ->
            val c = cell.trim()
            val idx = ci.toString()
            // else-if throughout, matching web: one cell claims at most one
            // role, and "Debit Amount" must not also register as an amount
            // column.
            if (map.date == null && RX_DATE.containsMatchIn(c)) { map = map.copy(date = idx); score++ }
            else if (map.description == null && RX_DESC.containsMatchIn(c)) { map = map.copy(description = idx); score++ }
            else if (map.debit == null && RX_DEBIT.containsMatchIn(c)) { map = map.copy(debit = idx); score++ }
            else if (map.credit == null && RX_CREDIT.containsMatchIn(c)) { map = map.copy(credit = idx); score++ }
            else if (map.balance == null && RX_BALANCE.containsMatchIn(c)) { map = map.copy(balance = idx); score++ }
            else if (map.amount == null && RX_AMOUNT.containsMatchIn(c)) { map = map.copy(amount = idx); score++ }
            else if (drcr == null && RX_DRCR.containsMatchIn(c)) { drcr = ci }
        }
        if (score > bestScore) {
            bestScore = score
            best = i
            bestMap = map
            bestDrcr = drcr
        }
    }
    return Detected(best, bestMap ?: ColumnMapping(), bestDrcr)
}

internal const val WARN_NO_TABLE =
    "Couldn't find a transaction table — check the file has a header row with Date, Description and amount columns."
internal const val WARN_NO_AMOUNT_COLUMN = "No amount column detected — pick one in the mapping."
internal const val WARN_NO_ROWS = "No dated transactions found under the detected header."
internal const val DEFAULT_DESCRIPTION = "Transaction"

fun parseStatementCsv(text: String, currency: String, kind: String): ParsedStatement {
    val rows = parseStatementRows(text).filter { r -> r.any { it.trim().isNotEmpty() } }
    val warnings = mutableListOf<String>()
    val (headerRow, mapping, drcrCol) = detectMapping(rows)
    if (headerRow < 0 || mapping.date == null) {
        return ParsedStatement(
            kind = kind, label = LABEL_GENERIC, currency = currency,
            period = StatementPeriod(), txns = emptyList(),
            warnings = listOf(WARN_NO_TABLE), mapping = mapping,
        )
    }
    val di = mapping.date!!.toInt()
    val desci = mapping.description?.toInt() ?: -1
    val dbi = mapping.debit?.toInt() ?: -1
    val cri = mapping.credit?.toInt() ?: -1
    val ami = mapping.amount?.toInt() ?: -1
    val bali = mapping.balance?.toInt() ?: -1
    if (dbi < 0 && cri < 0 && ami < 0) warnings.add(WARN_NO_AMOUNT_COLUMN)

    val txns = mutableListOf<StatementTxn>()
    for (row in rows.drop(headerRow + 1)) {
        val date = parseStatementDate(row.getOrNull(di)) ?: continue // skip preamble / totals / blanks
        var amount = 0.0
        if (dbi >= 0 || cri >= 0) {
            val debit = if (dbi >= 0) statementNum(row.getOrNull(dbi)) else 0.0
            val credit = if (cri >= 0) statementNum(row.getOrNull(cri)) else 0.0
            amount = credit - debit
        } else if (ami >= 0) {
            var a = statementNum(row.getOrNull(ami))
            val drcrCell = if (drcrCol != null) row.getOrNull(drcrCol).orEmpty().lowercase() else null
            if (drcrCell != null) {
                if (Regex("dr|debit|w").containsMatchIn(drcrCell)) a = -kotlin.math.abs(a)
                else if (Regex("cr|credit|d(?!r)").containsMatchIn(drcrCell)) a = kotlin.math.abs(a)
            } else if (Regex("dr\\b", RegexOption.IGNORE_CASE).containsMatchIn(row.getOrNull(ami).orEmpty())) {
                a = -kotlin.math.abs(a)
            }
            amount = a
        }
        if (amount == 0.0) continue
        val balanceCell = if (bali >= 0) row.getOrNull(bali) else null
        txns.add(
            StatementTxn(
                date = date,
                description = (if (desci >= 0) row.getOrNull(desci).orEmpty() else "")
                    .trim().ifEmpty { DEFAULT_DESCRIPTION },
                // fromMajor, NOT `* 100`. Web hardcodes the divisor here and in
                // the balance below -- the third and fourth sites of the same
                // constant (PARITY_AUDIT web bug #8) -- which lands a ¥500 row
                // as ¥5. fromMajor uses the currency's own minor-unit count and
                // is byte-identical for INR, USD and EUR.
                amount = fromMajor(amount, currency).amount,
                balance = if (balanceCell != null && balanceCell.trim().isNotEmpty()) {
                    fromMajor(statementNum(balanceCell), currency).amount
                } else {
                    null
                },
            ),
        )
    }

    val dates = txns.map { it.date }.filter { it.isNotEmpty() }.sorted()
    if (txns.isEmpty()) warnings.add(WARN_NO_ROWS)
    return ParsedStatement(
        kind = kind,
        label = if (kind == "card") LABEL_CARD else LABEL_BANK,
        currency = currency,
        period = StatementPeriod(dates.firstOrNull(), dates.lastOrNull()),
        openingBalance = txns.firstOrNull { it.balance != null }?.balance,
        closingBalance = txns.lastOrNull { it.balance != null }?.balance,
        txns = txns,
        warnings = warnings,
        mapping = mapping,
    )
}

internal const val LABEL_GENERIC = "Statement"
internal const val LABEL_BANK = "Bank statement"
internal const val LABEL_CARD = "Card statement"
