import Foundation
@testable import Domain

// Wires StatementPdf.swift into FunctionRegistry.
//
// Every `expected` was produced by RUNNING web's real parsePdf.ts — its
// `parseStatementRows` and `parseStatementText` — against hand-built row
// fixtures, so the layouts are ours but every output is web's.
//
// Shape details that are load-bearing, and all come from JSON.stringify
// dropping `undefined`:
//   * parseStatementRows/Text never assign `card` or `mapping`, so neither key
//     exists on a PDF result. parseStatementCsv's results DO carry `mapping`,
//     which is why this file has its own serialiser rather than reusing
//     StatementVectors.swift's.
//   * their txn literals never set `category`/`ref` either.
//
// `groupPdfGlyphs` is the exception: web has NO equivalent (pdf.js hands back
// text runs, PDFBox and PDFKit hand back glyphs), so its fixtures come from a
// JS reference written alongside the ports rather than from web. They cannot
// prove fidelity to web — there is nothing to be faithful to. What they do
// prove is that Android and iOS split cells at exactly the same points, which
// is the only thing that could differ.
//
// The `jpy` pair is the ONE expectation edited by hand, for the same reason the
// CSV fixtures' is: the ports deliberately fix web bug #8 (a hardcoded *100)
// with fromMajor(), and JPY has zero minor units.

private func asPdfRows(_ any: Any) -> [PdfRow] {
    (any as! [Any]).map { row in
        (row as! [Any]).map { cell -> PdfCell in
            let d = cell as! [String: Any]
            return PdfCell(x: (d["x"] as! NSNumber).doubleValue, str: d["str"] as! String)
        }
    }
}

private func asPdfGlyphs(_ any: Any) -> [PdfGlyph] {
    (any as! [Any]).map { g in
        let d = g as! [String: Any]
        return PdfGlyph(
            x: (d["x"] as! NSNumber).doubleValue,
            y: (d["y"] as! NSNumber).doubleValue,
            width: (d["width"] as! NSNumber).doubleValue,
            text: d["text"] as! String
        )
    }
}

private func pdfCellToJson(_ c: PdfCell) -> [String: Any] {
    ["x": c.x, "str": c.str]
}

private func pdfTxnToJson(_ t: StatementTxn) -> [String: Any] {
    [
        "date": t.date,
        "description": t.description,
        "amount": t.amount,
        "balance": t.balance as Any? ?? NSNull(),
    ]
}

private func pdfParsedToJson(_ p: ParsedStatement) -> [String: Any] {
    [
        "kind": p.kind,
        "label": p.label,
        "currency": p.currency,
        "period": ["from": p.period.from as Any? ?? NSNull(), "to": p.period.to as Any? ?? NSNull()],
        "openingBalance": p.openingBalance as Any? ?? NSNull(),
        "closingBalance": p.closingBalance as Any? ?? NSNull(),
        "txns": p.txns.map(pdfTxnToJson),
        "warnings": p.warnings,
    ]
}

func registerStatementPdfVectors() {
    let domain = "statements-pdf"

    FunctionRegistry.register(domain: domain, fn: "parseStatementPdfRows") { input in
        let d = input as! [String: Any]
        guard let out = parseStatementPdfRows(
            asPdfRows(d["rows"]!),
            currency: d["currency"] as! String,
            kind: d["kind"] as! String
        ) else { return NSNull() }
        return pdfParsedToJson(out)
    }

    FunctionRegistry.register(domain: domain, fn: "parseStatementPdfText") { input in
        let d = input as! [String: Any]
        return pdfParsedToJson(parseStatementPdfText(
            d["text"] as! String,
            currency: d["currency"] as! String,
            kind: d["kind"] as! String
        ))
    }

    FunctionRegistry.register(domain: domain, fn: "pdfRowsToText") { input in
        let d = input as! [String: Any]
        return pdfRowsToText(asPdfRows(d["rows"]!))
    }

    FunctionRegistry.register(domain: domain, fn: "groupPdfGlyphs") { input in
        let d = input as! [String: Any]
        return groupPdfGlyphs(asPdfGlyphs(d["glyphs"]!)).map { $0.map(pdfCellToJson) }
    }

    FunctionRegistry.register(domain: domain, fn: "parsePdfStatementFromGlyphs") { input in
        let d = input as! [String: Any]
        return pdfParsedToJson(parsePdfStatementFromGlyphs(
            asPdfGlyphs(d["glyphs"]!),
            currency: d["currency"] as! String,
            kind: d["kind"] as! String
        ))
    }

    FunctionRegistry.register(domain: domain, fn: "parsePdfStatement") { input in
        let d = input as! [String: Any]
        return pdfParsedToJson(parsePdfStatement(
            asPdfRows(d["rows"]!),
            currency: d["currency"] as! String,
            kind: d["kind"] as! String
        ))
    }
}
