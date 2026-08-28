import Foundation

/**
 The AI fallback's reply, turned into a `ReceiptDraft`.

 Ported from `mapLine` and the draft assembly in
 `apps/web/src/receipts/aiParse.ts`. The NETWORK call is not here — only the
 mapping, which is the part that decides money and therefore the part that
 belongs under vectors. A model's reply is untrusted input: every field is
 optional, every number can be absent or non-finite, and the difference between
 handling that correctly and not is a bill that silently inflates.

 **One deliberate divergence from web, and it is the ×100 again.** Web's
 `toMinor` is `Math.round(value * 10 ** minorDigits)` with `minorDigits`
 defaulting to 2, and no caller ever passes anything else — so a JPY receipt
 comes back a hundred times too large. This uses `fromMajor(major, currency)`.
 For INR, USD and EUR the two are byte-identical; a vector pins the JPY case.

 Mirrors Android's AiReceipt.kt.
 */

/// One line as the edge function's `emit_receipt` tool emits it.
public struct AiLine: Equatable, Sendable {
    public let kind: String?
    public let description: String?
    public let quantity: Double?
    public let unit: String?
    public let unitPrice: Double?
    public let amount: Double?

    public init(
        kind: String? = nil,
        description: String? = nil,
        quantity: Double? = nil,
        unit: String? = nil,
        unitPrice: Double? = nil,
        amount: Double? = nil
    ) {
        self.kind = kind
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.amount = amount
    }
}

/// The `receipt` object in the edge function's reply.
public struct AiReceipt: Equatable, Sendable {
    public let merchant: String?
    public let date: String?
    public let currency: String?
    public let total: Double?
    public let confidence: Double?
    public let lines: [AiLine]

    public init(
        merchant: String? = nil,
        date: String? = nil,
        currency: String? = nil,
        total: Double? = nil,
        confidence: Double? = nil,
        lines: [AiLine] = []
    ) {
        self.merchant = merchant
        self.date = date
        self.currency = currency
        self.total = total
        self.confidence = confidence
        self.lines = lines
    }
}

/// The kinds the ledger understands. Anything else the model invents is read as
/// an ordinary item rather than dropped — an unrecognised kind on a real line
/// would otherwise remove money from the bill.
private let validKinds: Set<String> = ["item", "tax", "service_charge", "tip", "discount"]

private func isFinite(_ v: Double?) -> Bool {
    guard let v else { return false }
    return v.isFinite
}

/// Web's `/^\d{4}-\d{2}-\d{2}$/`.
private func isIsoDay(_ s: String) -> Bool {
    guard s.count == 10 else { return false }
    let parts = s.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
    return parts.allSatisfy { $0.allSatisfy(\.isNumber) }
}

/**
 One line, or nil when there is no usable amount.

 Web drops a line whose `amount` is not a finite number, and so does this: a
 line with no money on it is not a line, and inventing a zero would make the
 reconciliation pass on a bill that was never read.
 */
private func mapLine(_ raw: AiLine, _ index: Int, _ currency: String) -> ReceiptLine? {
    guard isFinite(raw.amount), let rawAmount = raw.amount else { return nil }
    let kind = validKinds.contains(raw.kind ?? "") ? raw.kind! : "item"
    let amount = fromMajor(rawAmount, currency).amount
    let trimmed = (raw.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return ReceiptLine(
        id: "ai\(index)",
        kind: kind,
        description: trimmed.isEmpty ? kind.replacingOccurrences(of: "_", with: " ") : trimmed,
        quantity: (isFinite(raw.quantity) && (raw.quantity ?? 0) > 0)
            ? Int64(jsRound(raw.quantity! * Double(RECEIPT_QTY_SCALE)))
            : nil,
        // Web's `raw.unit ? ... : null` — an EMPTY string is falsy and becomes
        // nil, but a whitespace-only one is truthy and trims to "". Faithful to
        // the quirk because a vector pins it either way.
        unit: (raw.unit?.isEmpty ?? true)
            ? nil
            : raw.unit!.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        unitPrice: isFinite(raw.unitPrice) ? fromMajor(raw.unitPrice!, currency).amount : nil,
        // Belt and braces, in web's own words: the prompt asks for negative
        // discounts, but a model that forgets must not silently inflate the bill.
        amount: kind == "discount" ? -abs(amount) : amount,
        confidence: 90
    )
}

/**
 The whole reply as a draft.

 `currencyHint` is the user's base currency, used when the model does not name
 one.
 */
public func aiReceiptDraft(
    receipt: AiReceipt,
    currencyHint: String,
    rawText: String? = nil
) -> ReceiptDraft {
    let currency = (receipt.currency ?? currencyHint).uppercased()
    let lines = receipt.lines.enumerated().compactMap { mapLine($1, $0, currency) }
    return ReceiptDraft(
        // Same falsy-empty quirk as `unit` above.
        merchant: (receipt.merchant?.isEmpty ?? true)
            ? nil
            : receipt.merchant!.trimmingCharacters(in: .whitespacesAndNewlines),
        occurredAt: receipt.date.flatMap { isIsoDay($0) ? $0 : nil },
        currency: currency,
        lines: lines,
        total: isFinite(receipt.total) ? fromMajor(receipt.total!, currency).amount : nil,
        // Web clamps to 0...100 and rounds. A model that returns 130 confidence
        // is not 130% sure of anything.
        confidence: isFinite(receipt.confidence)
            ? max(0, min(100, Int(jsRound(receipt.confidence!))))
            : 80,
        engine: "claude",
        rawText: rawText
    )
}
