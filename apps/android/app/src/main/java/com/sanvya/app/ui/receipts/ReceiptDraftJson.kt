package com.sanvya.app.ui.receipts

import com.sanvya.app.domain.receipts.ReceiptDraft
import com.sanvya.app.domain.receipts.ReceiptLine
import org.json.JSONArray
import org.json.JSONObject
import com.sanvya.app.ui.FormOptions

/**
 * Hand-rolled JSON encode/decode for [ReceiptDraft] (task #62). Mirrors
 * web's `JSON.stringify(draft)` / `JSON.parse(raw) as ReceiptDraft` shape
 * field-for-field -- `receipt_scans.parsed_json` is written and read as
 * plain JSON on every platform (web, Android, iOS), so the wire shape must
 * agree even though nothing here is shared code.
 *
 * Uses `org.json` (built into the Android SDK, no dependency) rather than
 * kotlinx.serialization: the version catalog's own comment on
 * `kotlinxSerializationJson` says it's "test-scope only, does not ship in
 * the app", and the ported `ReceiptDraft`/`ReceiptLine` domain structs
 * (golden-vector-tested) are deliberately not annotated `@Serializable` --
 * this file keeps that boundary intact instead of reaching across it.
 */
fun ReceiptDraft.toJsonString(): String {
    val root = JSONObject()
    root.put("merchant", merchant)
    root.put("occurredAt", occurredAt)
    root.put("currency", currency)
    root.put("total", total)
    root.put("confidence", confidence)
    root.put("engine", engine)
    root.put("rawText", rawText)
    val arr = JSONArray()
    for (line in lines) {
        val l = JSONObject()
        l.put("id", line.id)
        l.put("kind", line.kind)
        l.put("description", line.description)
        l.put("quantity", line.quantity)
        l.put("unit", line.unit)
        l.put("unitPrice", line.unitPrice)
        l.put("amount", line.amount)
        l.put("confidence", line.confidence)
        arr.put(l)
    }
    root.put("lines", arr)
    return root.toString()
}

fun receiptDraftFromJsonString(text: String): ReceiptDraft {
    val root = JSONObject(text)
    val arr = root.optJSONArray("lines") ?: JSONArray()
    val lines = (0 until arr.length()).map { i ->
        val l = arr.getJSONObject(i)
        ReceiptLine(
            id = l.getString("id"),
            kind = l.getString("kind"),
            description = l.optString("description", ""),
            quantity = if (l.isNull("quantity")) null else l.getLong("quantity"),
            unit = if (l.isNull("unit")) null else l.getString("unit"),
            unitPrice = if (l.isNull("unitPrice")) null else l.getLong("unitPrice"),
            amount = l.getLong("amount"),
            confidence = l.optInt("confidence", 0),
        )
    }
    return ReceiptDraft(
        merchant = if (root.isNull("merchant")) null else root.optString("merchant"),
        occurredAt = if (root.isNull("occurredAt")) null else root.optString("occurredAt"),
        currency = root.optString("currency", FormOptions.DEFAULT_CURRENCY),
        lines = lines,
        total = if (root.isNull("total")) null else root.getLong("total"),
        confidence = root.optInt("confidence", 0),
        engine = root.optString("engine", "manual"),
        rawText = if (root.isNull("rawText")) null else root.optString("rawText"),
    )
}
