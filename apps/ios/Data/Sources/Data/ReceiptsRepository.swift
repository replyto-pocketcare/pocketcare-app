import Foundation
import PowerSync
import Domain

// Read/write facade for receipt scans (P2.5): receipt_scans table.
// Mirrors apps/web/src/receipts/scan.ts (saveScan, updateScanDraft, linkScan).
// Mirrors apps/android/data/.../repository/ReceiptsRepository.kt.

public struct ReceiptScanRow: Sendable {
    public let id: String
    public let userId: String
    public let source: String
    public let engine: String
    public let merchant: String?
    public let occurredAt: String?
    public let currency: String?
    public let subtotal: Int64?
    public let tax: Int64?
    public let serviceCharge: Int64?
    public let tip: Int64?
    public let discount: Int64?
    public let total: Int64?
    public let confidence: Int64?
    public let rawText: String?
    public let parsedJson: String?
    public let transactionId: String?
    public let expenseId: String?
    public let imagePath: String?
    public let createdAt: String
    public let updatedAt: String
}

public struct SaveScanInput: Sendable {
    public let source: String
    public let engine: String
    public let merchant: String?
    public let occurredAt: String?
    public let currency: String?
    public let subtotal: Int64?
    public let tax: Int64?
    public let serviceCharge: Int64?
    public let tip: Int64?
    public let discount: Int64?
    public let total: Int64?
    public let confidence: Int64?
    public let rawText: String?
    public let parsedJson: String?

    public init(
        source: String,
        engine: String,
        merchant: String? = nil,
        occurredAt: String? = nil,
        currency: String? = nil,
        subtotal: Int64? = nil,
        tax: Int64? = nil,
        serviceCharge: Int64? = nil,
        tip: Int64? = nil,
        discount: Int64? = nil,
        total: Int64? = nil,
        confidence: Int64? = nil,
        rawText: String? = nil,
        parsedJson: String? = nil
    ) {
        self.source = source
        self.engine = engine
        self.merchant = merchant
        self.occurredAt = occurredAt
        self.currency = currency
        self.subtotal = subtotal
        self.tax = tax
        self.serviceCharge = serviceCharge
        self.tip = tip
        self.discount = discount
        self.total = total
        self.confidence = confidence
        self.rawText = rawText
        self.parsedJson = parsedJson
    }
}

public struct UpdateScanDraftInput: Sendable {
    public let engine: String
    public let merchant: String?
    public let occurredAt: String?
    public let currency: String?
    public let subtotal: Int64?
    public let tax: Int64?
    public let serviceCharge: Int64?
    public let tip: Int64?
    public let discount: Int64?
    public let total: Int64?
    public let confidence: Int64?
    public let parsedJson: String?

    public init(
        engine: String,
        merchant: String? = nil,
        occurredAt: String? = nil,
        currency: String? = nil,
        subtotal: Int64? = nil,
        tax: Int64? = nil,
        serviceCharge: Int64? = nil,
        tip: Int64? = nil,
        discount: Int64? = nil,
        total: Int64? = nil,
        confidence: Int64? = nil,
        parsedJson: String? = nil
    ) {
        self.engine = engine
        self.merchant = merchant
        self.occurredAt = occurredAt
        self.currency = currency
        self.subtotal = subtotal
        self.tax = tax
        self.serviceCharge = serviceCharge
        self.tip = tip
        self.discount = discount
        self.total = total
        self.confidence = confidence
        self.parsedJson = parsedJson
    }
}

private func currentIsoString() -> String {
    ISO8601DateFormatter().string(from: Date())
}

public final class ReceiptsRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol
    private let getUserId: @Sendable () -> String

    public init(db: PowerSyncDatabaseProtocol, getUserId: @escaping @Sendable () -> String) {
        self.db = db
        self.getUserId = getUserId
    }

    public func saveScan(_ input: SaveScanInput) async throws -> String {
        let id = UUID().uuidString
        let ts = currentIsoString()
        let userId = getUserId()
        let rawTextCapped = input.rawText.map { String($0.prefix(8000)) }

        try await db.execute(
            sql: """
            INSERT INTO receipt_scans (
                id, user_id, source, engine, merchant, occurred_at, currency,
                subtotal, tax, service_charge, tip, discount, total, confidence,
                raw_text, parsed_json, transaction_id, expense_id, image_path,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                id, userId, input.source, input.engine, input.merchant, input.occurredAt, input.currency,
                input.subtotal, input.tax, input.serviceCharge, input.tip, input.discount, input.total, input.confidence,
                rawTextCapped, input.parsedJson, nil, nil, nil,
                ts, ts
            ]
        )
        return id
    }

    public func updateScanDraft(scanId: String, input: UpdateScanDraftInput) async throws {
        let ts = currentIsoString()
        try await db.execute(
            sql: """
            UPDATE receipt_scans SET
                engine = ?, merchant = ?, occurred_at = ?, currency = ?,
                subtotal = ?, tax = ?, service_charge = ?, tip = ?, discount = ?,
                total = ?, confidence = ?, parsed_json = ?, updated_at = ?
            WHERE id = ? AND deleted_at IS NULL
            """,
            parameters: [
                input.engine, input.merchant, input.occurredAt, input.currency,
                input.subtotal, input.tax, input.serviceCharge, input.tip, input.discount,
                input.total, input.confidence, input.parsedJson, ts,
                scanId
            ]
        )
    }

    public func linkScan(scanId: String, transactionId: String? = nil, expenseId: String? = nil) async throws {
        let ts = currentIsoString()
        var sets: [String] = []
        var params: [Sendable?] = []

        if let tId = transactionId {
            sets.append("transaction_id = ?")
            params.append(tId)
        }
        if let eId = expenseId {
            sets.append("expense_id = ?")
            params.append(eId)
        }
        if sets.isEmpty { return }

        sets.append("updated_at = ?")
        params.append(ts)
        params.append(scanId)

        try await db.execute(
            sql: "UPDATE receipt_scans SET \(sets.joined(separator: ", ")) WHERE id = ? AND deleted_at IS NULL",
            parameters: params
        )
    }

    public func get(scanId: String) async throws -> ReceiptScanRow? {
        try await db.getOptional(
            sql: "SELECT * FROM receipt_scans WHERE id = ? AND deleted_at IS NULL",
            parameters: [scanId]
        ) { cursor in
            ReceiptScanRow(
                id: try cursor.getString(name: "id"),
                userId: try cursor.getString(name: "user_id"),
                source: try cursor.getString(name: "source"),
                engine: try cursor.getString(name: "engine"),
                merchant: try cursor.getStringOptional(name: "merchant"),
                occurredAt: try cursor.getStringOptional(name: "occurred_at"),
                currency: try cursor.getStringOptional(name: "currency"),
                subtotal: try cursor.getInt64Optional(name: "subtotal"),
                tax: try cursor.getInt64Optional(name: "tax"),
                serviceCharge: try cursor.getInt64Optional(name: "service_charge"),
                tip: try cursor.getInt64Optional(name: "tip"),
                discount: try cursor.getInt64Optional(name: "discount"),
                total: try cursor.getInt64Optional(name: "total"),
                confidence: try cursor.getInt64Optional(name: "confidence"),
                rawText: try cursor.getStringOptional(name: "raw_text"),
                parsedJson: try cursor.getStringOptional(name: "parsed_json"),
                transactionId: try cursor.getStringOptional(name: "transaction_id"),
                expenseId: try cursor.getStringOptional(name: "expense_id"),
                imagePath: try cursor.getStringOptional(name: "image_path"),
                createdAt: try cursor.getString(name: "created_at"),
                updatedAt: try cursor.getString(name: "updated_at")
            )
        }
    }

    public func list(limit: Int = 50) async throws -> [ReceiptScanRow] {
        try await db.getAll(
            sql: "SELECT * FROM receipt_scans WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT ?",
            parameters: [limit]
        ) { cursor in
            ReceiptScanRow(
                id: try cursor.getString(name: "id"),
                userId: try cursor.getString(name: "user_id"),
                source: try cursor.getString(name: "source"),
                engine: try cursor.getString(name: "engine"),
                merchant: try cursor.getStringOptional(name: "merchant"),
                occurredAt: try cursor.getStringOptional(name: "occurred_at"),
                currency: try cursor.getStringOptional(name: "currency"),
                subtotal: try cursor.getInt64Optional(name: "subtotal"),
                tax: try cursor.getInt64Optional(name: "tax"),
                serviceCharge: try cursor.getInt64Optional(name: "service_charge"),
                tip: try cursor.getInt64Optional(name: "tip"),
                discount: try cursor.getInt64Optional(name: "discount"),
                total: try cursor.getInt64Optional(name: "total"),
                confidence: try cursor.getInt64Optional(name: "confidence"),
                rawText: try cursor.getStringOptional(name: "raw_text"),
                parsedJson: try cursor.getStringOptional(name: "parsed_json"),
                transactionId: try cursor.getStringOptional(name: "transaction_id"),
                expenseId: try cursor.getStringOptional(name: "expense_id"),
                imagePath: try cursor.getStringOptional(name: "image_path"),
                createdAt: try cursor.getString(name: "created_at"),
                updatedAt: try cursor.getString(name: "updated_at")
            )
        }
    }

    public func delete(scanId: String) async throws {
        let ts = currentIsoString()
        try await db.execute(
            sql: "UPDATE receipt_scans SET deleted_at = ?, updated_at = ? WHERE id = ?",
            parameters: [ts, ts, scanId]
        )
    }
}
