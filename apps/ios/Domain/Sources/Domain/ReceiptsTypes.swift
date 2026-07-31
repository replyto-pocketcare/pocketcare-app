import Foundation

// Ported from packages/core/receipts/src/types.ts (P1.5b). Mirrors
// apps/android/domain/.../receipts/ReceiptsTypes.kt (P1.5a) field-for-field.
// Correctness is judged against tools/golden-vectors/vectors/receipts-*.json
// -- see docs/plans/native-mobile-apps.md section 5 and CLAUDE.md golden
// rule 8 ("web is the spec"). Unlike money/finance/budget, this domain's
// exported vectors never wrap amounts with amt()/mny() -- every money/
// quantity field here is a PLAIN JSON number (same convention as
// splits-insights/splits-math, P1.4).
//
// Every plain-data struct here is marked Sendable up front (not added
// reactively after a compiler error) -- P1.4 established that any public
// Domain-package struct a *Vectors.swift file puts in a global `let`
// fixture needs it, since Swift's automatic Sendable synthesis only
// applies within the same module.

/// Quantities are milli-units: 1000 === one unit.
public let RECEIPT_QTY_SCALE = 1000

/// True for the non-goods lines (tax / service charge / tip / discount).
public func isCharge(_ kind: String) -> Bool { kind != "item" }

/// One printed line on a receipt. `item` lines are goods; the rest are charges.
public struct ReceiptLine: Sendable {
    public let id: String
    public let kind: String // "item" | "tax" | "service_charge" | "tip" | "discount"
    public let description: String
    /// Milli-units. Nil when the receipt didn't print a quantity.
    public let quantity: Int64?
    /// Free-text unit as printed ("kg", "pcs", "L"). Nil when absent.
    public let unit: String?
    /// Minor units per single unit. Nil when the receipt didn't print one.
    public let unitPrice: Int64?
    /// Minor units. The authoritative line total. Negative for `discount`.
    public let amount: Int64
    /// 0-100. How sure the parser is about THIS line.
    public let confidence: Int

    public init(id: String, kind: String, description: String, quantity: Int64?, unit: String?, unitPrice: Int64?, amount: Int64, confidence: Int) {
        self.id = id
        self.kind = kind
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.amount = amount
        self.confidence = confidence
    }
}

public struct ReceiptDraft: Sendable {
    public let merchant: String?
    /// ISO-8601 date (YYYY-MM-DD) as printed. Nil when unreadable.
    public let occurredAt: String?
    /// ISO 4217. Falls back to the user's base currency when unreadable.
    public let currency: String
    public let lines: [ReceiptLine]
    /// Minor units, as PRINTED on the receipt. Nil when unreadable.
    public let total: Int64?
    /// 0-100 overall parse confidence.
    public let confidence: Int
    public let engine: String // "tesseract" | "claude" | "pdf_text" | "manual"
    /// Raw OCR text, kept for re-parsing and debugging. Never contains an image.
    public let rawText: String?

    public init(merchant: String?, occurredAt: String?, currency: String, lines: [ReceiptLine], total: Int64?, confidence: Int, engine: String, rawText: String? = nil) {
        self.merchant = merchant
        self.occurredAt = occurredAt
        self.currency = currency
        self.lines = lines
        self.total = total
        self.confidence = confidence
        self.engine = engine
        self.rawText = rawText
    }
}

// ---------------------------------------------------------------------------
// Split modes
// ---------------------------------------------------------------------------

/// Percent weights are stored x100 so "33.33%" is the integer 3333.
public let RECEIPT_PERCENT_SCALE = 100

/// A participant's claim on one line. The meaning of `weight` depends on the
/// line's mode: milli-quantity, percent x100, exact minor units, or ignored
/// (`equal`). `proportional` derives its weights and ignores this field.
public struct ShareInput: Sendable {
    public let userId: String
    public let weight: Double?
    public init(userId: String, weight: Double? = nil) {
        self.userId = userId
        self.weight = weight
    }
}

/// Resolved allocation: minor units this user owes for this line.
public struct ShareResult: Sendable {
    public let userId: String
    public let amount: Int64
    public init(userId: String, amount: Int64) {
        self.userId = userId
        self.amount = amount
    }
}

/// One line plus who is on it and how it's divided.
public struct LineAssignment: Sendable {
    public let lineId: String
    public let mode: String
    public let shares: [ShareInput]
    public init(lineId: String, mode: String, shares: [ShareInput]) {
        self.lineId = lineId
        self.mode = mode
        self.shares = shares
    }
}
