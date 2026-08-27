package com.sanvya.app.domain.csv

/**
 * Minimal, dependency-free CSV (RFC-4180-ish): quotes, escaped quotes, CRLF.
 * Ported from apps/web/src/data/csv.ts, character for character.
 *
 * No CSV library on either platform, deliberately. Web hand-wrote this because
 * a dependency was not worth it; adopting a different parser on each phone
 * would give three implementations that disagree about the interesting cases --
 * an escaped quote inside a quoted cell, a bare CR, a trailing newline -- which
 * are exactly the cases a real bank export contains.
 *
 * `downloadText` is NOT ported: saving a file is a platform concern, and there
 * is nothing shared about a browser anchor click, an Android SAF intent and a
 * UIActivityViewController.
 *
 * Mirrors apps/ios/Domain/Sources/Domain/Csv.swift.
 */

/** Parse CSV text into rows of string cells. Auto-detects `,` vs `;`. */
fun parseCsv(text: String, delimiter: String? = null): List<List<String>> {
    val src = text.removePrefix("﻿") // strip BOM
    val delim = (delimiter ?: detectDelimiter(src)).first()
    val rows = mutableListOf<List<String>>()
    var row = mutableListOf<String>()
    val cell = StringBuilder()
    var inQuotes = false
    var i = 0
    while (i < src.length) {
        val ch = src[i]
        when {
            inQuotes -> when {
                ch == '"' && i + 1 < src.length && src[i + 1] == '"' -> {
                    cell.append('"'); i++
                }
                ch == '"' -> inQuotes = false
                else -> cell.append(ch)
            }
            ch == '"' -> inQuotes = true
            ch == delim -> { row.add(cell.toString()); cell.setLength(0) }
            ch == '\n' -> {
                row.add(cell.toString()); rows.add(row); row = mutableListOf(); cell.setLength(0)
            }
            // A bare CR is dropped; the LF branch above ends the row. Web's
            // comment says "handled by the \n branch", which is only true for
            // CRLF -- a lone CR line ending produces one very long row on all
            // three platforms. Preserved, because a file that old would import
            // identically wrong everywhere rather than differently.
            ch == '\r' -> Unit
            else -> cell.append(ch)
        }
        i++
    }
    if (cell.isNotEmpty() || row.isNotEmpty()) { row.add(cell.toString()); rows.add(row) }
    return rows.filter { r -> r.any { it.trim().isNotEmpty() } }
}

private fun detectDelimiter(text: String): String {
    val newline = text.indexOf('\n')
    val firstLine = if (newline >= 0) text.substring(0, newline) else text
    val commas = firstLine.count { it == ',' }
    val semis = firstLine.count { it == ';' }
    return if (semis > commas) ";" else ","
}

/** Parse into header-keyed records (headers lowercased + trimmed). */
fun parseRecords(text: String, delimiter: String? = null): List<Map<String, String>> {
    val rows = parseCsv(text, delimiter)
    if (rows.isEmpty()) return emptyList()
    val headers = rows[0].map { it.trim().lowercase() }
    return rows.drop(1).map { r ->
        // A LinkedHashMap so the record's iteration order is the file's column
        // order -- nothing depends on it today, but a vector compares JSON.
        val rec = LinkedHashMap<String, String>()
        headers.forEachIndexed { index, h -> rec[h] = (r.getOrNull(index) ?: "").trim() }
        rec
    }
}

/** Serialize rows (first row = header) to CSV text. */
fun toCsv(rows: List<List<String?>>): String =
    rows.joinToString("\r\n") { r -> r.joinToString(",") { escapeCell(it) } }

private fun escapeCell(v: String?): String {
    val s = v ?: ""
    return if (s.any { it == '"' || it == ',' || it == '\r' || it == '\n' }) {
        "\"" + s.replace("\"", "\"\"") + "\""
    } else {
        s
    }
}

/**
 * A minor-unit amount as the plain major-unit number a CSV cell holds:
 * `49900` INR -> `"499.00"`, `500` JPY -> `"500"`.
 *
 * Web writes `(amount / 100).toFixed(2)` and its importer reads that straight
 * back, so a JPY 500 charge exports as "5.00" and re-imports as JPY 5 -- a
 * round trip that loses money for every currency that is not two-decimal. Using
 * the currency's own minor-unit count in both directions makes the round trip
 * lossless, and for INR, USD and EUR produces byte-identical output to web's.
 *
 * Deliberately NOT `formatMoney`: this is a machine-readable cell. A grouped,
 * symbol-prefixed, locale-formatted number is what the importer's amount parser
 * has to fight its way back out of.
 */
fun majorText(minor: Long, currency: String): String {
    val decimals = com.sanvya.app.domain.money.minorUnits(currency)
    val major = com.sanvya.app.domain.money.toMajor(
        com.sanvya.app.domain.money.money(minor, currency)
    )
    return String.format(java.util.Locale.ROOT, "%.${decimals}f", major)
}
