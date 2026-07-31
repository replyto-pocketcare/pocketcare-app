import Foundation
@testable import Domain

// P1.5b: wires the real Receipts*.swift ports into FunctionRegistry so
// receipts-allocate.json / receipts-reconcile.json / receipts-money-text.json
// / receipts-parse.json's vectors un-skip. Four domains registered from
// this one file (mirrors the TS source's four sibling files under one npm
// package, and Android's ReceiptsVectors.kt). Every field here is a plain
// JSON number/string/bool -- this domain's exporter calls never wrap
// results with amt()/mny() (same convention as splits-insights/splits-math,
// P1.4).

// ---------------------------------------------------------------------------
// Shared (de)serializers
// ---------------------------------------------------------------------------

private func asReceiptLine(_ any: Any) -> ReceiptLine {
    let d = any as! [String: Any]
    return ReceiptLine(
        id: d["id"] as! String,
        kind: d["kind"] as! String,
        description: d["description"] as! String,
        quantity: (d["quantity"] as? NSNumber)?.int64Value,
        unit: d["unit"] as? String,
        unitPrice: (d["unitPrice"] as? NSNumber)?.int64Value,
        amount: (d["amount"] as! NSNumber).int64Value,
        confidence: (d["confidence"] as! NSNumber).intValue
    )
}

private func receiptLineToJson(_ l: ReceiptLine) -> [String: Any] {
    [
        "id": l.id,
        "kind": l.kind,
        "description": l.description,
        "quantity": l.quantity.map { $0 as Any } ?? NSNull(),
        "unit": l.unit.map { $0 as Any } ?? NSNull(),
        "unitPrice": l.unitPrice.map { $0 as Any } ?? NSNull(),
        "amount": l.amount,
        "confidence": l.confidence,
    ]
}

private func asReceiptDraft(_ any: Any) -> ReceiptDraft {
    let d = any as! [String: Any]
    return ReceiptDraft(
        merchant: d["merchant"] as? String,
        occurredAt: d["occurredAt"] as? String,
        currency: d["currency"] as! String,
        lines: (d["lines"] as! [Any]).map(asReceiptLine),
        total: (d["total"] as? NSNumber)?.int64Value,
        confidence: (d["confidence"] as! NSNumber).intValue,
        engine: d["engine"] as! String,
        rawText: d["rawText"] as? String
    )
}

/// rawText is an OPTIONAL TS field (`rawText?: string`) -- omitted from the
/// JSON entirely when absent, not emitted as null, so vectors whose drafts
/// never carry raw OCR text (receipts-reconcile's fixtures) have no
/// "rawText" key at all. jsonValueEqual's dictionary comparison requires
/// exact key-set equality, so emitting an extra "rawText": NSNull() here
/// would fail a vector that doesn't expect the key to exist -- mirrors
/// ReceiptsVectors.kt's identical reasoning.
private func receiptDraftToJson(_ d: ReceiptDraft) -> [String: Any] {
    var out: [String: Any] = [
        "merchant": d.merchant.map { $0 as Any } ?? NSNull(),
        "occurredAt": d.occurredAt.map { $0 as Any } ?? NSNull(),
        "currency": d.currency,
        "lines": d.lines.map(receiptLineToJson),
        "total": d.total.map { $0 as Any } ?? NSNull(),
        "confidence": d.confidence,
        "engine": d.engine,
    ]
    if let rawText = d.rawText { out["rawText"] = rawText }
    return out
}

private func asShareInput(_ any: Any) -> ShareInput {
    let d = any as! [String: Any]
    return ShareInput(userId: d["userId"] as! String, weight: (d["weight"] as? NSNumber)?.doubleValue)
}

private func shareResultToJson(_ r: ShareResult) -> [String: Any] {
    ["userId": r.userId, "amount": r.amount]
}

private func asShareResult(_ any: Any) -> ShareResult {
    let d = any as! [String: Any]
    return ShareResult(userId: d["userId"] as! String, amount: (d["amount"] as! NSNumber).int64Value)
}

private func asLineAssignment(_ any: Any) -> LineAssignment {
    let d = any as! [String: Any]
    return LineAssignment(
        lineId: d["lineId"] as! String,
        mode: d["mode"] as! String,
        shares: (d["shares"] as! [Any]).map(asShareInput)
    )
}

private func asLongMap(_ any: Any) -> [String: Int64] {
    let d = any as! [String: Any]
    return d.mapValues { ($0 as! NSNumber).int64Value }
}

private func asPerLineMap(_ any: Any) -> [String: [ShareResult]] {
    let d = any as! [String: Any]
    return d.mapValues { ($0 as! [Any]).map(asShareResult) }
}

// ---------------------------------------------------------------------------
// receipts-allocate
// ---------------------------------------------------------------------------

func registerReceiptsAllocateVectors() {
    let domain = "receipts-allocate"

    FunctionRegistry.register(domain: domain, fn: "splitByWeights") { input in
        let d = input as! [String: Any]
        let total = (d["total"] as! NSNumber).int64Value
        let weights = (d["weights"] as! [Any]).map { ($0 as! NSNumber).doubleValue }
        return splitByWeights(total, weights)
    }

    FunctionRegistry.register(domain: domain, fn: "splitEqual") { input in
        let d = input as! [String: Any]
        let total = (d["total"] as! NSNumber).int64Value
        let n = (d["n"] as! NSNumber).intValue
        return splitEqual(total, n)
    }

    FunctionRegistry.register(domain: domain, fn: "allocateItem") { input in
        let d = input as! [String: Any]
        let amount = (d["amount"] as! NSNumber).int64Value
        let shares = (d["shares"] as! [Any]).map(asShareInput)
        let mode = d["mode"] as! String
        return try allocateItem(amount, shares, mode).map(shareResultToJson)
    }

    FunctionRegistry.register(domain: domain, fn: "allocateProportional") { input in
        let d = input as! [String: Any]
        let amount = (d["amount"] as! NSNumber).int64Value
        let participants = (d["participants"] as! [Any]).map { $0 as! String }
        let subtotalByUser = asLongMap(d["subtotalByUser"]!)
        return allocateProportional(amount, participants, subtotalByUser).map(shareResultToJson)
    }

    FunctionRegistry.register(domain: domain, fn: "rollUp") { input in
        let d = input as! [String: Any]
        let perLine = asPerLineMap(d["perLine"]!)
        return rollUp(perLine)
    }

    FunctionRegistry.register(domain: domain, fn: "allocateReceipt") { input in
        let d = input as! [String: Any]
        let lines = (d["lines"] as! [Any]).map(asReceiptLine)
        let assignments = (d["assignments"] as! [Any]).map(asLineAssignment)
        let r = try allocateReceipt(lines, assignments)
        return [
            "perLine": r.perLine.mapValues { $0.map(shareResultToJson) },
            "byUser": r.byUser,
            "total": r.total,
            "itemSubtotalByUser": r.itemSubtotalByUser,
        ]
    }
}

// ---------------------------------------------------------------------------
// receipts-reconcile
// ---------------------------------------------------------------------------

private func subtotalsToJson(_ s: Subtotals) -> [String: Any] {
    [
        "items": s.items,
        "tax": s.tax,
        "serviceCharge": s.serviceCharge,
        "tip": s.tip,
        "discount": s.discount,
        "computed": s.computed,
    ]
}

private func reconcileResultToJson(_ r: ReconcileResult) -> [String: Any] {
    [
        "ok": r.ok,
        "reason": r.reason,
        "computed": r.computed,
        "stated": r.stated.map { $0 as Any } ?? NSNull(),
        "delta": r.delta,
        "subtotals": subtotalsToJson(r.subtotals),
    ]
}

func registerReceiptsReconcileVectors() {
    let domain = "receipts-reconcile"

    FunctionRegistry.register(domain: domain, fn: "subtotals") { input in
        let d = input as! [String: Any]
        let lines = (d["lines"] as! [Any]).map(asReceiptLine)
        return subtotalsToJson(subtotals(lines))
    }
    FunctionRegistry.register(domain: domain, fn: "reconcile") { input in
        let d = input as! [String: Any]
        let draft = asReceiptDraft(d["draft"]!)
        return reconcileResultToJson(reconcile(draft))
    }
    FunctionRegistry.register(domain: domain, fn: "shouldEscalate") { input in
        let d = input as! [String: Any]
        let draft = asReceiptDraft(d["draft"]!)
        return shouldEscalate(draft)
    }
    FunctionRegistry.register(domain: domain, fn: "balanceWithLine") { input in
        let d = input as! [String: Any]
        let draft = asReceiptDraft(d["draft"]!)
        let id = d["id"] as! String
        let description = d["description"] as! String
        return receiptDraftToJson(balanceWithLine(draft, id, description))
    }
}

// ---------------------------------------------------------------------------
// receipts-money-text
// ---------------------------------------------------------------------------

private func numberMatchToJson(_ m: NumberMatch) -> [String: Any] {
    ["raw": m.raw, "start": m.start, "end": m.end, "value": m.value]
}

func registerReceiptsMoneyTextVectors() {
    let domain = "receipts-money-text"

    FunctionRegistry.register(domain: domain, fn: "detectCurrency") { input in
        let d = input as! [String: Any]
        return detectCurrency(d["text"] as! String).map { $0 as Any } ?? NSNull()
    }
    FunctionRegistry.register(domain: domain, fn: "parseMoney") { input in
        let d = input as! [String: Any]
        let raw = d["raw"] as! String
        let minorDigits = (d["minorDigits"] as? NSNumber)?.intValue ?? 2
        return parseMoney(raw, minorDigits).map { $0 as Any } ?? NSNull()
    }
    FunctionRegistry.register(domain: domain, fn: "findNumbers") { input in
        let d = input as! [String: Any]
        let line = d["line"] as! String
        let minorDigits = (d["minorDigits"] as? NSNumber)?.intValue ?? 2
        return findNumbers(line, minorDigits).map(numberMatchToJson)
    }
    FunctionRegistry.register(domain: domain, fn: "findDate") { input in
        let d = input as! [String: Any]
        let text = d["text"] as! String
        let today = d["today"] as? String
        return findDate(text, today).map { $0 as Any } ?? NSNull()
    }
    FunctionRegistry.register(domain: domain, fn: "findUnit") { input in
        let d = input as! [String: Any]
        return findUnit(d["text"] as! String).map { $0 as Any } ?? NSNull()
    }
    FunctionRegistry.register(domain: domain, fn: "tidyDescription") { input in
        let d = input as! [String: Any]
        return tidyDescription(d["text"] as! String)
    }
}

// ---------------------------------------------------------------------------
// receipts-parse
// ---------------------------------------------------------------------------

private func asOcrToken(_ any: Any) -> OcrToken {
    let d = any as! [String: Any]
    return OcrToken(
        text: d["text"] as! String,
        x0: (d["x0"] as! NSNumber).doubleValue,
        x1: (d["x1"] as! NSNumber).doubleValue,
        y0: (d["y0"] as! NSNumber).doubleValue,
        y1: (d["y1"] as! NSNumber).doubleValue,
        confidence: (d["confidence"] as! NSNumber).intValue
    )
}

private func ocrTokenToJson(_ t: OcrToken) -> [String: Any] {
    ["text": t.text, "x0": jsonNumber(t.x0), "x1": jsonNumber(t.x1), "y0": jsonNumber(t.y0), "y1": jsonNumber(t.y1), "confidence": t.confidence]
}

private func textLineToJson(_ l: TextLine) -> [String: Any] {
    ["text": l.text, "tokens": l.tokens.map(ocrTokenToJson), "y": jsonNumber(l.y), "confidence": l.confidence]
}

func registerReceiptsParseVectors() {
    let domain = "receipts-parse"

    FunctionRegistry.register(domain: domain, fn: "groupIntoLines") { input in
        let d = input as! [String: Any]
        let tokens = (d["tokens"] as! [Any]).map(asOcrToken)
        return groupIntoLines(tokens).map(textLineToJson)
    }

    FunctionRegistry.register(domain: domain, fn: "linesFromText") { input in
        let d = input as! [String: Any]
        let text = d["text"] as! String
        let confidence = (d["confidence"] as? NSNumber)?.intValue ?? 100
        return linesFromText(text, confidence).map(textLineToJson)
    }

    FunctionRegistry.register(domain: domain, fn: "parseReceiptText") { input in
        let d = input as! [String: Any]
        let text = d["text"] as! String
        let currency = d["currency"] as! String
        let today = d["today"] as? String
        return receiptDraftToJson(parseReceiptText(text, ParseOptions(currency: currency, today: today)))
    }

    // export.ts reuses the exact RECEIPT_FIXTURES[0] fixture -- this
    // vector's input.lines field is a literal descriptive placeholder
    // string ("linesFromText(fixture.text)"), not real data, exactly like
    // P1.4's pickFriendInsights placeholder-input vector. Reconstruct the
    // real input from RECEIPT_FIXTURES by name rather than trying to parse
    // the placeholder, mirroring ReceiptsVectors.kt.
    FunctionRegistry.register(domain: domain, fn: "parseReceipt") { input in
        let d = input as! [String: Any]
        let fixtureName = d["fixture"] as! String
        guard let fixture = RECEIPT_FIXTURES.first(where: { $0.name == fixtureName }) else {
            fatalError("unknown receipt fixture: \(fixtureName)")
        }
        let optsJson = d["opts"] as! [String: Any]
        let opts = ParseOptions(
            currency: (optsJson["currency"] as? String) ?? fixture.currency,
            today: optsJson["today"] as? String,
            idPrefix: (optsJson["idPrefix"] as? String) ?? "l"
        )
        return receiptDraftToJson(parseReceipt(linesFromText(fixture.text), opts))
    }
}
