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
import com.sanvya.app.domain.receipts.AiLine
import com.sanvya.app.domain.receipts.AiReceipt
import com.sanvya.app.domain.receipts.ReceiptDraft
import com.sanvya.app.domain.receipts.aiReceiptDraft
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.functions.functions
import io.ktor.client.statement.bodyAsText
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
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
    /**
     * Only the AI fallback needs the network. Everything else on this
     * repository is local -- which is the point of the feature, and is why the
     * client arrives as a dependency rather than being reached for globally.
     */
    private val client: SupabaseClient,
) {
    /**
     * Send the photo to the `receipt-scan` edge function and map its reply.
     *
     * **The only code path in this feature where the image leaves the device**,
     * and it is reached only from an explicit "Improve with AI" tap. The scan
     * pipeline never calls it.
     *
     * The MAPPING is not here -- `aiReceiptDraft` in Domain does that under 18
     * vectors, because it decides money from untrusted input. This does the two
     * things a repository should: the call, and turning a failure into
     * something the UI can act on. `quotaExceeded` is separated from every
     * other error because it is the one failure with a next step: web shows the
     * upgrade path for it and only for it.
     */
    suspend fun aiParseReceipt(
        base64: String,
        mediaType: String,
        currencyHint: String,
        today: String,
        rawText: String? = null,
    ): ReceiptDraft {
        val body = buildJsonObject {
            put("image", base64)
            put("mediaType", mediaType)
            put("currencyHint", currencyHint)
            put("today", today)
        }
        val json = try {
            val response = client.functions.invoke(
                function = "receipt-scan",
                body = body,
                headers = Headers.build { append(HttpHeaders.ContentType, "application/json") },
            )
            Json.parseToJsonElement(response.bodyAsText()).jsonObject
        } catch (e: RestException) {
            // supabase-kt collapses a non-2xx into an exception whose message is
            // the raw body, and the function always answers with `{ error }` --
            // the same unwrapping web's `edgeFnMessage()` does, for the same
            // reason. The code matters as much as the message here.
            val parsed = runCatching { Json.parseToJsonElement(e.message.orEmpty()).jsonObject }.getOrNull()
            throw AiScanError(
                message = parsed?.get("error")?.jsonPrimitive?.contentOrNull ?: AI_SCAN_FAILURE,
                quotaExceeded = parsed?.get("code")?.jsonPrimitive?.contentOrNull == "quota_exceeded",
            )
        } catch (e: Exception) {
            throw AiScanError(e.message ?: AI_SCAN_FAILURE)
        }

        json["error"]?.jsonPrimitive?.contentOrNull?.let { message ->
            throw AiScanError(
                message = message,
                quotaExceeded = json["code"]?.jsonPrimitive?.contentOrNull == "quota_exceeded",
            )
        }
        val receipt = json["receipt"]?.takeIf { it !is JsonNull }?.jsonObject
            ?: throw AiScanError(AI_SCAN_EMPTY)

        return aiReceiptDraft(
            receipt = receipt.toAiReceipt(),
            currencyHint = currencyHint,
            rawText = rawText,
        )
    }

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

/**
 * A failed AI read.
 *
 * [quotaExceeded] is separate because it is the only failure the user can do
 * something about: web shows the upgrade path for it and a plain message for
 * everything else.
 */
class AiScanError(message: String, val quotaExceeded: Boolean = false) : Exception(message)

private const val AI_SCAN_FAILURE = "Couldn't reach the scanner. Check your connection."
private const val AI_SCAN_EMPTY = "The scan came back empty. Try a clearer photo."

/**
 * The edge function's `receipt` object, as Domain's input type.
 *
 * Deliberately tolerant: every field is optional and a wrong TYPE reads as
 * absent rather than throwing. A model reply is untrusted input, and a strict
 * decoder here would turn one odd field into a total failure where web would
 * have shown the user a partial draft they could fix.
 */
private fun JsonObject.aiText(key: String): String? =
    this[key]?.let { if (it is JsonPrimitive && it !is JsonNull) it.content else null }

/**
 * A JSON NUMBER, or null.
 *
 * `isString` is checked because web's guard is `typeof raw.amount !== "number"`
 * -- a model that returns `"12.50"` as a string is REJECTED there, and the line
 * dropped. Accepting it here would make the two clients disagree about whether
 * a bill has that line on it at all.
 */
private fun JsonObject.aiNumber(key: String): Double? =
    this[key]?.let { if (it is JsonPrimitive && !it.isString) it.doubleOrNull else null }

private fun JsonObject.toAiReceipt(): AiReceipt = AiReceipt(
    merchant = aiText("merchant"),
    date = aiText("date"),
    currency = aiText("currency"),
    total = aiNumber("total"),
    confidence = aiNumber("confidence"),
    lines = this["lines"]?.let { element ->
        runCatching { element.jsonArray }.getOrNull()?.mapNotNull { line ->
            runCatching { line.jsonObject }.getOrNull()?.let { o ->
                AiLine(
                    kind = o.aiText("kind"),
                    description = o.aiText("description"),
                    quantity = o.aiNumber("quantity"),
                    unit = o.aiText("unit"),
                    // The wire name is snake_case; Domain's field is not.
                    // `receipts-ai.json` carries the WIRE name so the corpus
                    // pins it and both platforms' registrations must agree.
                    unitPrice = o.aiNumber("unit_price"),
                    amount = o.aiNumber("amount"),
                )
            }
        }
    } ?: emptyList(),
)
