import Foundation
import Domain

/// Hand-rolled JSON encode/decode for `ReceiptDraft` (task #62). Mirrors
/// Android's ReceiptDraftJson.kt and web's `JSON.stringify(draft)` /
/// `JSON.parse(raw) as ReceiptDraft` shape field-for-field --
/// `receipt_scans.parsed_json` is read/written as plain JSON on every
/// platform, so the wire shape must agree even though nothing here is
/// shared code. Uses `JSONSerialization` rather than `Codable`: the ported
/// `ReceiptDraft`/`ReceiptLine` domain structs (golden-vector-tested) are
/// deliberately not `Codable`, and this file keeps that boundary intact
/// instead of retrofitting conformance onto tested code.
enum ReceiptDraftJson {
    static func encode(_ draft: ReceiptDraft) -> String {
        var root: [String: Any] = [
            "merchant": draft.merchant as Any? ?? NSNull(),
            "occurredAt": draft.occurredAt as Any? ?? NSNull(),
            "currency": draft.currency,
            "total": draft.total as Any? ?? NSNull(),
            "confidence": draft.confidence,
            "engine": draft.engine,
            "rawText": draft.rawText as Any? ?? NSNull(),
        ]
        root["lines"] = draft.lines.map { line -> [String: Any] in
            [
                "id": line.id,
                "kind": line.kind,
                "description": line.description,
                "quantity": line.quantity as Any? ?? NSNull(),
                "unit": line.unit as Any? ?? NSNull(),
                "unitPrice": line.unitPrice as Any? ?? NSNull(),
                "amount": line.amount,
                "confidence": line.confidence,
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func decode(_ text: String) -> ReceiptDraft? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let linesRaw = root["lines"] as? [[String: Any]] ?? []
        let lines = linesRaw.compactMap { l -> ReceiptLine? in
            guard let id = l["id"] as? String, let kind = l["kind"] as? String, let amount = (l["amount"] as? NSNumber)?.int64Value else { return nil }
            return ReceiptLine(
                id: id,
                kind: kind,
                description: l["description"] as? String ?? "",
                quantity: (l["quantity"] as? NSNumber)?.int64Value,
                unit: l["unit"] as? String,
                unitPrice: (l["unitPrice"] as? NSNumber)?.int64Value,
                amount: amount,
                confidence: (l["confidence"] as? NSNumber)?.intValue ?? 0
            )
        }
        return ReceiptDraft(
            merchant: root["merchant"] as? String,
            occurredAt: root["occurredAt"] as? String,
            currency: root["currency"] as? String ?? FormOptions.defaultCurrency,
            lines: lines,
            total: (root["total"] as? NSNumber)?.int64Value,
            confidence: (root["confidence"] as? NSNumber)?.intValue ?? 0,
            engine: root["engine"] as? String ?? "manual",
            rawText: root["rawText"] as? String
        )
    }
}
