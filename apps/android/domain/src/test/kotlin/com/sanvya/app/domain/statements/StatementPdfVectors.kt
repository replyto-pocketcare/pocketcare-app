package com.sanvya.app.domain.statements

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires StatementPdf.kt into FunctionRegistry.
//
// Every `expected` was produced by RUNNING web's real parsePdf.ts -- its
// `parseStatementRows` and `parseStatementText` -- against hand-built row
// fixtures, so the layouts are ours but every output is web's.
//
// Shape details that are load-bearing, and all come from JSON.stringify
// dropping `undefined`:
//   * parseStatementRows/Text never assign `card` or `mapping`, so neither key
//     exists on a PDF result. parseStatementCsv's results DO carry `mapping`,
//     which is why this file has its own serialiser rather than reusing
//     StatementVectors.kt's.
//   * their txn literals never set `category`/`ref` either.
//
// `groupPdfGlyphs` is the exception: web has NO equivalent (pdf.js hands back
// text runs, PDFBox and PDFKit hand back glyphs), so its fixtures come from a
// JS reference written alongside the ports rather than from web. They cannot
// prove fidelity to web -- there is nothing to be faithful to. What they do
// prove is that Android and iOS split cells at exactly the same points, which
// is the only thing that could differ.
//
// The `jpy` pair is the ONE expectation edited by hand, for the same reason the
// CSV fixtures' is: the ports deliberately fix web bug #8 (a hardcoded *100)
// with fromMajor(), and JPY has zero minor units.

private const val DOMAIN = "statements-pdf"

private fun JsonElement.toPdfRows(): List<PdfRow> = jsonArray.map { row ->
    row.jsonArray.map { cell ->
        val o = cell.jsonObject
        PdfCell(
            x = o.getValue("x").jsonPrimitive.double,
            str = o.getValue("str").jsonPrimitive.content,
        )
    }
}

private fun JsonElement.toPdfGlyphs(): List<PdfGlyph> = jsonArray.map { g ->
    val o = g.jsonObject
    PdfGlyph(
        x = o.getValue("x").jsonPrimitive.double,
        y = o.getValue("y").jsonPrimitive.double,
        width = o.getValue("width").jsonPrimitive.double,
        text = o.getValue("text").jsonPrimitive.content,
    )
}

private fun PdfCell.toJson(): JsonElement =
    JsonObject(mapOf("x" to JsonPrimitive(x), "str" to JsonPrimitive(str)))

private fun StatementTxn.toPdfJson(): JsonElement = JsonObject(
    mapOf(
        "date" to JsonPrimitive(date),
        "description" to JsonPrimitive(description),
        "amount" to JsonPrimitive(amount),
        "balance" to (balance?.let { JsonPrimitive(it) } ?: JsonNull),
    ),
)

private fun ParsedStatement.toPdfJson(): JsonElement = JsonObject(
    mapOf(
        "kind" to JsonPrimitive(kind),
        "label" to JsonPrimitive(label),
        "currency" to JsonPrimitive(currency),
        "period" to JsonObject(
            mapOf(
                "from" to (period.from?.let { JsonPrimitive(it) } ?: JsonNull),
                "to" to (period.to?.let { JsonPrimitive(it) } ?: JsonNull),
            ),
        ),
        "openingBalance" to (openingBalance?.let { JsonPrimitive(it) } ?: JsonNull),
        "closingBalance" to (closingBalance?.let { JsonPrimitive(it) } ?: JsonNull),
        "txns" to JsonArray(txns.map { it.toPdfJson() }),
        "warnings" to JsonArray(warnings.map { JsonPrimitive(it) }),
    ),
)

fun registerStatementPdfVectors() {
    FunctionRegistry.register(DOMAIN, "parseStatementPdfRows") { input ->
        val o = input.jsonObject
        parseStatementPdfRows(
            rows = o.getValue("rows").toPdfRows(),
            currency = o.getValue("currency").jsonPrimitive.content,
            kind = o.getValue("kind").jsonPrimitive.content,
        )?.toPdfJson() ?: JsonNull
    }

    FunctionRegistry.register(DOMAIN, "parseStatementPdfText") { input ->
        val o = input.jsonObject
        parseStatementPdfText(
            text = o.getValue("text").jsonPrimitive.content,
            currency = o.getValue("currency").jsonPrimitive.content,
            kind = o.getValue("kind").jsonPrimitive.content,
        ).toPdfJson()
    }

    FunctionRegistry.register(DOMAIN, "pdfRowsToText") { input ->
        JsonPrimitive(pdfRowsToText(input.jsonObject.getValue("rows").toPdfRows()))
    }

    FunctionRegistry.register(DOMAIN, "groupPdfGlyphs") { input ->
        JsonArray(
            groupPdfGlyphs(input.jsonObject.getValue("glyphs").toPdfGlyphs())
                .map { row -> JsonArray(row.map { it.toJson() }) },
        )
    }

    FunctionRegistry.register(DOMAIN, "parsePdfStatementFromGlyphs") { input ->
        val o = input.jsonObject
        parsePdfStatementFromGlyphs(
            glyphs = o.getValue("glyphs").toPdfGlyphs(),
            currency = o.getValue("currency").jsonPrimitive.content,
            kind = o.getValue("kind").jsonPrimitive.content,
        ).toPdfJson()
    }

    FunctionRegistry.register(DOMAIN, "parsePdfStatement") { input ->
        val o = input.jsonObject
        parsePdfStatement(
            rows = o.getValue("rows").toPdfRows(),
            currency = o.getValue("currency").jsonPrimitive.content,
            kind = o.getValue("kind").jsonPrimitive.content,
        ).toPdfJson()
    }
}
