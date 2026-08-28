import Foundation
@testable import Domain

// Wires AiReceipt.swift into FunctionRegistry.
//
// A SPEC, not a capture: `mapLine` and the draft assembly live in a client
// module that imports supabase-js, so the fixtures were produced by
// transcribing the rules and running the transcription.
//
// ONE fixture deliberately does NOT match what a browser would produce, and it
// is the JPY one: web's `toMinor` is `Math.round(value * 10 ** minorDigits)`
// with `minorDigits` defaulting to 2 and no caller ever passing anything else,
// so a 3000-yen bill comes back as 300000 minor units. This uses
// `fromMajor(major, currency)`. INR, USD and EUR agree byte for byte; JPY and
// KWD are where they part.
//
// Money travels as STRINGS, per the corpus rule — including `quantity`, which
// is milli-units and therefore also a scaled integer. `confidence` does not: it
// is a 0-100 score, not an amount.
//
// The two whitespace fixtures look pedantic and are not. Web's `x ? f(x) : null`
// treats "" as absent but "  " as present-then-trimmed-to-"", so those two
// inputs produce DIFFERENT outputs. A port that "cleaned that up" would diverge
// silently on a field the review screen displays.

private func str(_ d: [String: Any], _ key: String) -> String? {
    d[key] as? String
}

private func num(_ d: [String: Any], _ key: String) -> Double? {
    (d[key] as? NSNumber)?.doubleValue
}

private func aiLine(_ d: [String: Any]) -> AiLine {
    AiLine(
        kind: str(d, "kind"),
        description: str(d, "description"),
        quantity: num(d, "quantity"),
        unit: str(d, "unit"),
        unitPrice: num(d, "unit_price"),
        amount: num(d, "amount")
    )
}

private func minorOrNull(_ v: Int64?) -> Any {
    v.map { String($0) as Any } ?? NSNull()
}

private func textOrNull(_ v: String?) -> Any {
    v.map { $0 as Any } ?? NSNull()
}

func registerAiReceiptVectors() {
    FunctionRegistry.register(domain: "receipts-ai", fn: "aiReceiptDraft") { input in
        let d = input as! [String: Any]
        let r = d["receipt"] as! [String: Any]
        let receipt = AiReceipt(
            merchant: str(r, "merchant"),
            date: str(r, "date"),
            currency: str(r, "currency"),
            total: num(r, "total"),
            confidence: num(r, "confidence"),
            lines: ((r["lines"] as? [Any]) ?? []).map { aiLine($0 as! [String: Any]) }
        )
        let draft = aiReceiptDraft(
            receipt: receipt,
            currencyHint: d["currencyHint"] as! String,
            rawText: str(d, "rawText")
        )
        return [
            "merchant": textOrNull(draft.merchant),
            "occurredAt": textOrNull(draft.occurredAt),
            "currency": draft.currency,
            "lines": draft.lines.map { l in
                [
                    "id": l.id,
                    "kind": l.kind,
                    "description": l.description,
                    "quantity": minorOrNull(l.quantity),
                    "unit": textOrNull(l.unit),
                    "unitPrice": minorOrNull(l.unitPrice),
                    "amount": String(l.amount),
                    "confidence": l.confidence,
                ] as [String: Any]
            },
            "total": minorOrNull(draft.total),
            "confidence": draft.confidence,
            "engine": draft.engine,
            "rawText": textOrNull(draft.rawText),
        ] as [String: Any]
    }
}
