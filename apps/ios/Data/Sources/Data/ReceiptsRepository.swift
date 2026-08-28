import Foundation
import PowerSync
import Supabase
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
    /// Only the AI fallback needs the network. Everything else on this
    /// repository is local — which is the point of the feature, and is why the
    /// client arrives as a dependency rather than being reached for globally.
    private let client: SupabaseClient

    public init(
        db: PowerSyncDatabaseProtocol,
        getUserId: @escaping @Sendable () -> String,
        client: SupabaseClient
    ) {
        self.db = db
        self.getUserId = getUserId
        self.client = client
    }

    /**
     Send the photo to the `receipt-scan` edge function and map its reply.

     **The only code path in this feature where the image leaves the device**,
     and it is reached only from an explicit "Improve with AI" tap. The scan
     pipeline never calls it.

     The MAPPING is not here — `aiReceiptDraft` in Domain does that under 18
     vectors, because it decides money from untrusted input. This does the two
     things a repository should: the call, and turning a failure into something
     the UI can act on. `quotaExceeded` is separated from every other error
     because it is the one failure with a next step: web shows the upgrade path
     for it and only for it.
     */
    public func aiParseReceipt(
        base64: String,
        mediaType: String,
        currencyHint: String,
        today: String,
        rawText: String? = nil
    ) async throws -> ReceiptDraft {
        let body: [String: String] = [
            "image": base64,
            "mediaType": mediaType,
            "currencyHint": currencyHint,
            "today": today,
        ]
        let data: Foundation.Data
        do {
            // The raw-bytes overload, matching AssistantRepository: the reply is
            // a dynamic receipt shape, and a Decodable struct here would turn
            // one unexpected field into a total failure.
            data = try await client.functions.invoke(
                "receipt-scan",
                options: FunctionInvokeOptions(body: body)
            ) { raw, _ in raw }
        } catch let error as FunctionsError {
            // A non-2xx carries the real reason in its body, and the function
            // always answers with `{ error, code }` — the same unwrapping web's
            // `edgeFnMessage()` does, for the same reason. The code matters as
            // much as the message here.
            if case let .httpError(code, body) = error {
                let parsed = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                throw AiScanError(
                    message: (parsed?["error"] as? String) ?? aiScanStatusMessage(code),
                    quotaExceeded: (parsed?["code"] as? String) == "quota_exceeded"
                )
            }
            throw AiScanError(message: error.localizedDescription)
        } catch {
            throw AiScanError(message: error.localizedDescription)
        }

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AiScanError(message: aiScanEmpty)
        }
        if let message = json["error"] as? String {
            throw AiScanError(
                message: message,
                quotaExceeded: (json["code"] as? String) == "quota_exceeded"
            )
        }
        guard let receipt = json["receipt"] as? [String: Any] else {
            throw AiScanError(message: aiScanEmpty)
        }
        return aiReceiptDraft(
            receipt: aiReceipt(from: receipt),
            currencyHint: currencyHint,
            rawText: rawText
        )
    }

    public func saveScan(_ input: SaveScanInput) async throws -> String {
        let id = UUID().canonicalString
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

    /**
     Transaction ids that came from a receipt photo, live.

     Web's `useScannedTransactionIds()` (apps/web/src/splits/hooks.ts) reads
     exactly this and the Transactions list uses it to draw the "Scanned" pill.
     Neither phone ever queried `receipt_scans.transaction_id`, so a scanned
     transaction looked like any other hand-typed one.

     A whole-column watch rather than a per-row lookup: the list needs the
     answer for up to 200 rows at once, and this table has one row per scan —
     two orders of magnitude smaller than the ledger it annotates.
     */
    public func watchScannedTransactionIds() throws -> AsyncThrowingStream<Set<String>, Error> {
        let rows: AsyncThrowingStream<[String], Error> = try db.watch(
            sql: "SELECT transaction_id FROM receipt_scans WHERE transaction_id IS NOT NULL AND deleted_at IS NULL",
            parameters: [],
            mapper: { cursor in try cursor.getString(name: "transaction_id") }
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await batch in rows { continuation.yield(Set(batch)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
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

/**
 A failed AI read.

 `quotaExceeded` is separate because it is the only failure the user can do
 something about: web shows the upgrade path for it and a plain message for
 everything else.
 */
public struct AiScanError: LocalizedError {
    public let message: String
    public let quotaExceeded: Bool
    public init(message: String, quotaExceeded: Bool = false) {
        self.message = message
        self.quotaExceeded = quotaExceeded
    }
    public var errorDescription: String? { message }
}

private let aiScanFailure = "Couldn't reach the scanner. Check your connection."
private let aiScanEmpty = "The scan came back empty. Try a clearer photo."

private func aiScanStatusMessage(_ code: Int) -> String {
    code == 401 ? "Please sign in to use AI receipt reading." : aiScanFailure
}

/**
 The edge function's `receipt` object, as Domain's input type.

 Deliberately tolerant: every field is optional and a wrong TYPE reads as absent
 rather than throwing. A model reply is untrusted input, and a strict decoder
 here would turn one odd field into a total failure where web would have shown
 the user a partial draft they could fix.

 `as? NSNumber` is the `typeof x === "number"` guard: a model that returns
 `"12.50"` as a STRING is rejected, and the line dropped, exactly as on web.
 */
private func aiText(_ d: [String: Any], _ key: String) -> String? {
    if let s = d[key] as? String { return s }
    if let n = d[key] as? NSNumber { return n.stringValue }
    return nil
}

private func aiNumber(_ d: [String: Any], _ key: String) -> Double? {
    (d[key] as? NSNumber)?.doubleValue
}

private func aiReceipt(from d: [String: Any]) -> AiReceipt {
    AiReceipt(
        merchant: aiText(d, "merchant"),
        date: aiText(d, "date"),
        currency: aiText(d, "currency"),
        total: aiNumber(d, "total"),
        confidence: aiNumber(d, "confidence"),
        lines: ((d["lines"] as? [Any]) ?? []).compactMap { raw in
            guard let o = raw as? [String: Any] else { return nil }
            return AiLine(
                kind: aiText(o, "kind"),
                description: aiText(o, "description"),
                quantity: aiNumber(o, "quantity"),
                unit: aiText(o, "unit"),
                // The wire name is snake_case; Domain's field is not.
                // `receipts-ai.json` carries the WIRE name so the corpus pins
                // it and both platforms' registrations must agree.
                unitPrice: aiNumber(o, "unit_price"),
                amount: aiNumber(o, "amount")
            )
        }
    )
}
