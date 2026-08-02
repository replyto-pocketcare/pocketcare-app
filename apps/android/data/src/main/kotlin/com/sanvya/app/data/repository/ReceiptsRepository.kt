package com.sanvya.app.data.repository

/**
 * Read/write facade for receipt scans (P2.5): receipt_scans table.
 * Mirrors apps/web/src/receipts/scan.ts (saveScan, updateScanDraft, linkScan).
 *
 * Table columns confirmed against PocketCareSchema.kt (P2.1) and
 * supabase/migrations/0001_init.sql.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import java.time.Instant
import java.util.UUID

data class ReceiptScanRow(
    val id: String,
    val userId: String,
    val source: String,
    val engine: String,
    val merchant: String?,
    val occurredAt: String?,
    val currency: String?,
    val subtotal: Long?,
    val tax: Long?,
    val serviceCharge: Long?,
    val tip: Long?,
    val discount: Long?,
    val total: Long?,
    val confidence: Long?,
    val rawText: String?,
    val parsedJson: String?,
    val transactionId: String?,
    val expenseId: String?,
    val imagePath: String?,
    val createdAt: String,
    val updatedAt: String,
)

data class SaveScanInput(
    val source: String,
    val engine: String,
    val merchant: String? = null,
    val occurredAt: String? = null,
    val currency: String? = null,
    val subtotal: Long? = null,
    val tax: Long? = null,
    val serviceCharge: Long? = null,
    val tip: Long? = null,
    val discount: Long? = null,
    val total: Long? = null,
    val confidence: Long? = null,
    val rawText: String? = null,
    val parsedJson: String? = null,
)

data class UpdateScanDraftInput(
    val engine: String,
    val merchant: String? = null,
    val occurredAt: String? = null,
    val currency: String? = null,
    val subtotal: Long? = null,
    val tax: Long? = null,
    val serviceCharge: Long? = null,
    val tip: Long? = null,
    val discount: Long? = null,
    val total: Long? = null,
    val confidence: Long? = null,
    val parsedJson: String? = null,
)

class ReceiptsRepository(
    private val db: PowerSyncDatabase,
    private val getUserId: () -> String,
) {
    suspend fun saveScan(input: SaveScanInput): String {
        val id = UUID.randomUUID().toString()
        val ts = Instant.now().toString()
        val userId = getUserId()
        val rawTextCapped = input.rawText?.take(8000)

        db.execute(
            """INSERT INTO receipt_scans (
                id, user_id, source, engine, merchant, occurred_at, currency,
                subtotal, tax, service_charge, tip, discount, total, confidence,
                raw_text, parsed_json, transaction_id, expense_id, image_path,
                created_at, updated_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            listOf(
                id, userId, input.source, input.engine, input.merchant, input.occurredAt, input.currency,
                input.subtotal, input.tax, input.serviceCharge, input.tip, input.discount, input.total, input.confidence,
                rawTextCapped, input.parsedJson, null, null, null,
                ts, ts
            )
        )
        return id
    }

    suspend fun updateScanDraft(scanId: String, input: UpdateScanDraftInput) {
        val ts = Instant.now().toString()
        db.execute(
            """UPDATE receipt_scans SET
                engine = ?, merchant = ?, occurred_at = ?, currency = ?,
                subtotal = ?, tax = ?, service_charge = ?, tip = ?, discount = ?,
                total = ?, confidence = ?, parsed_json = ?, updated_at = ?
               WHERE id = ? AND deleted_at IS NULL""",
            listOf(
                input.engine, input.merchant, input.occurredAt, input.currency,
                input.subtotal, input.tax, input.serviceCharge, input.tip, input.discount,
                input.total, input.confidence, input.parsedJson, ts,
                scanId
            )
        )
    }

    suspend fun linkScan(scanId: String, transactionId: String? = null, expenseId: String? = null) {
        val ts = Instant.now().toString()
        val sets = mutableListOf<String>()
        val params = mutableListOf<Any?>()

        if (transactionId != null) {
            sets.add("transaction_id = ?")
            params.add(transactionId)
        }
        if (expenseId != null) {
            sets.add("expense_id = ?")
            params.add(expenseId)
        }
        if (sets.isEmpty()) return

        sets.add("updated_at = ?")
        params.add(ts)
        params.add(scanId)

        db.execute(
            "UPDATE receipt_scans SET ${sets.joinToString(", ")} WHERE id = ? AND deleted_at IS NULL",
            params
        )
    }

    suspend fun get(scanId: String): ReceiptScanRow? = db.getOptional(
        sql = "SELECT * FROM receipt_scans WHERE id = ? AND deleted_at IS NULL",
        parameters = listOf(scanId),
        mapper = { cursor ->
            ReceiptScanRow(
                id = cursor.getString("id"),
                userId = cursor.getString("user_id"),
                source = cursor.getString("source"),
                engine = cursor.getString("engine"),
                merchant = cursor.getStringOptional("merchant"),
                occurredAt = cursor.getStringOptional("occurred_at"),
                currency = cursor.getStringOptional("currency"),
                subtotal = cursor.getLongOptional("subtotal"),
                tax = cursor.getLongOptional("tax"),
                serviceCharge = cursor.getLongOptional("service_charge"),
                tip = cursor.getLongOptional("tip"),
                discount = cursor.getLongOptional("discount"),
                total = cursor.getLongOptional("total"),
                confidence = cursor.getLongOptional("confidence"),
                rawText = cursor.getStringOptional("raw_text"),
                parsedJson = cursor.getStringOptional("parsed_json"),
                transactionId = cursor.getStringOptional("transaction_id"),
                expenseId = cursor.getStringOptional("expense_id"),
                imagePath = cursor.getStringOptional("image_path"),
                createdAt = cursor.getString("created_at"),
                updatedAt = cursor.getString("updated_at")
            )
        }
    )

    suspend fun list(limit: Int = 50): List<ReceiptScanRow> = db.getAll(
        sql = "SELECT * FROM receipt_scans WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT ?",
        parameters = listOf(limit),
        mapper = { cursor ->
            ReceiptScanRow(
                id = cursor.getString("id"),
                userId = cursor.getString("user_id"),
                source = cursor.getString("source"),
                engine = cursor.getString("engine"),
                merchant = cursor.getStringOptional("merchant"),
                occurredAt = cursor.getStringOptional("occurred_at"),
                currency = cursor.getStringOptional("currency"),
                subtotal = cursor.getLongOptional("subtotal"),
                tax = cursor.getLongOptional("tax"),
                serviceCharge = cursor.getLongOptional("service_charge"),
                tip = cursor.getLongOptional("tip"),
                discount = cursor.getLongOptional("discount"),
                total = cursor.getLongOptional("total"),
                confidence = cursor.getLongOptional("confidence"),
                rawText = cursor.getStringOptional("raw_text"),
                parsedJson = cursor.getStringOptional("parsed_json"),
                transactionId = cursor.getStringOptional("transaction_id"),
                expenseId = cursor.getStringOptional("expense_id"),
                imagePath = cursor.getStringOptional("image_path"),
                createdAt = cursor.getString("created_at"),
                updatedAt = cursor.getString("updated_at")
            )
        }
    )

    suspend fun delete(scanId: String) {
        val ts = Instant.now().toString()
        db.execute(
            "UPDATE receipt_scans SET deleted_at = ?, updated_at = ? WHERE id = ?",
            listOf(ts, ts, scanId)
        )
    }
}
