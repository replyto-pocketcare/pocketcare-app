package com.sanvya.app.domain.reconcile

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

// P1.6a: wires the real Reconcile.kt port into FunctionRegistry so
// reconcile.json's vectors un-skip. Row is a fully dynamic
// `Record<string, unknown>` in the TS source (unlike every earlier
// domain's fixed-shape inputs), so unlike receipts/splits/etc this
// adapter has to do real dynamic JSON->RowValue conversion rather than
// pull named fields off a known shape.

/** Dynamic JsonElement -> RowValue conversion. None of reconcile.json's
 * vectors exercise Obj/Arr/DoubleNum/Bool row values (every field is a
 * string id/note or an integer amount), but these branches are kept
 * faithful to RowValue's full shape rather than narrowed to just what's
 * tested, mirroring Reconcile.kt's own "kept reasonably faithful, not
 * vector-verified" stance on its own unexercised branches. */
private fun JsonElement.asRowValue(): RowValue = when (this) {
    is JsonNull -> RowValue.Null
    is JsonObject -> RowValue.Obj(this.mapValues { (_, v) -> v.asRowValue() })
    is JsonArray -> RowValue.Arr(this.map { it.asRowValue() })
    is JsonPrimitive -> when {
        this.isString -> RowValue.Str(this.content)
        this.booleanOrNull != null -> RowValue.Bool(this.booleanOrNull!!)
        this.longOrNull != null -> RowValue.IntNum(this.longOrNull!!)
        this.doubleOrNull != null -> RowValue.DoubleNum(this.doubleOrNull!!)
        else -> RowValue.Str(this.content)
    }
}

private fun JsonElement.asRow(): Row = this.jsonObject.mapValues { (_, v) -> v.asRowValue() }

private fun JsonElement.asChecksumOptions(): ChecksumOptions {
    val ignore = this.jsonObject["ignore"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList()
    return ChecksumOptions(ignore)
}

private fun optsFrom(o: JsonObject): ChecksumOptions =
    o["opts"]?.takeIf { it !is JsonNull }?.asChecksumOptions() ?: ChecksumOptions()

private fun DriftReport.toJson(): JsonElement = JsonObject(
    mapOf(
        "inSync" to JsonPrimitive(inSync),
        "missingRemote" to JsonArray(missingRemote.map { JsonPrimitive(it) }),
        "missingLocal" to JsonArray(missingLocal.map { JsonPrimitive(it) }),
        "mismatched" to JsonArray(mismatched.map { JsonPrimitive(it) }),
    )
)

fun registerReconcileVectors() {
    val domain = "reconcile"

    FunctionRegistry.register(domain, "rowChecksum") { input ->
        val o = input.jsonObject
        val row = o.getValue("row").asRow()
        JsonPrimitive(rowChecksum(row, optsFrom(o)))
    }

    FunctionRegistry.register(domain, "checksum") { input ->
        val o = input.jsonObject
        val rows = o.getValue("rows").jsonArray.map { it.asRow() }
        JsonPrimitive(checksum(rows, optsFrom(o)))
    }

    FunctionRegistry.register(domain, "reconcile") { input ->
        val o = input.jsonObject
        val local = o.getValue("local").jsonArray.map { it.asRow() }
        val remote = o.getValue("remote").jsonArray.map { it.asRow() }
        reconcile(local, remote, optsFrom(o)).toJson()
    }
}
