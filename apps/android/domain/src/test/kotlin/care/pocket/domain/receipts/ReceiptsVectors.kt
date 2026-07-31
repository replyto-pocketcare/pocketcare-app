package care.pocket.domain.receipts

import care.pocket.domain.vectors.FunctionRegistry
import care.pocket.domain.vectors.jsonNumber
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// P1.5a: wires the real Receipts*.kt ports into FunctionRegistry so
// receipts-allocate.json / receipts-reconcile.json / receipts-money-text.json
// / receipts-parse.json's vectors un-skip. Four domains registered from
// this one file (mirrors the TS source's four sibling files under one
// npm package). Every field here is a plain JSON number/string/bool --
// this domain's exporter calls never wrap results with amt()/mny(),
// confirmed by reading the actual generated vector files (same convention
// as splits-insights/splits-math, P1.4).

// ---------------------------------------------------------------------------
// Shared (de)serializers -- ReceiptLine/ReceiptDraft/ShareInput/etc. are used
// across all four domains' vectors.
// ---------------------------------------------------------------------------

private fun JsonElement.asReceiptLine(): ReceiptLine {
    val o = jsonObject
    return ReceiptLine(
        id = o.getValue("id").jsonPrimitive.content,
        kind = o.getValue("kind").jsonPrimitive.content,
        description = o.getValue("description").jsonPrimitive.content,
        quantity = o["quantity"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.long,
        unit = o["unit"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
        unitPrice = o["unitPrice"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.long,
        amount = o.getValue("amount").jsonPrimitive.long,
        confidence = o.getValue("confidence").jsonPrimitive.int,
    )
}

private fun ReceiptLine.toJson(): JsonElement = JsonObject(
    mapOf(
        "id" to JsonPrimitive(id),
        "kind" to JsonPrimitive(kind),
        "description" to JsonPrimitive(description),
        "quantity" to (quantity?.let { JsonPrimitive(it) } ?: JsonNull),
        "unit" to (unit?.let { JsonPrimitive(it) } ?: JsonNull),
        "unitPrice" to (unitPrice?.let { JsonPrimitive(it) } ?: JsonNull),
        "amount" to JsonPrimitive(amount),
        "confidence" to JsonPrimitive(confidence),
    )
)

private fun JsonElement.asReceiptDraft(): ReceiptDraft {
    val o = jsonObject
    return ReceiptDraft(
        merchant = o["merchant"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
        occurredAt = o["occurredAt"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
        currency = o.getValue("currency").jsonPrimitive.content,
        lines = o.getValue("lines").jsonArray.map { it.asReceiptLine() },
        total = o["total"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.long,
        confidence = o.getValue("confidence").jsonPrimitive.int,
        engine = o.getValue("engine").jsonPrimitive.content,
        rawText = o["rawText"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
    )
}

/** rawText is an OPTIONAL TS field (`rawText?: string`) -- omitted from the
 * JSON entirely when absent, not emitted as null, so vectors whose drafts
 * never carry raw OCR text (receipts-reconcile's fixtures) have no
 * "rawText" key at all. jsonElementsEqual's JsonObject comparison requires
 * exact key-set equality, so emitting an extra "rawText": null here would
 * fail a vector that doesn't expect the key to exist. */
private fun ReceiptDraft.toJson(): JsonElement = JsonObject(
    buildMap {
        put("merchant", merchant?.let { JsonPrimitive(it) } ?: JsonNull)
        put("occurredAt", occurredAt?.let { JsonPrimitive(it) } ?: JsonNull)
        put("currency", JsonPrimitive(currency))
        put("lines", JsonArray(lines.map { it.toJson() }))
        put("total", total?.let { JsonPrimitive(it) } ?: JsonNull)
        put("confidence", JsonPrimitive(confidence))
        put("engine", JsonPrimitive(engine))
        if (rawText != null) put("rawText", JsonPrimitive(rawText))
    }
)

private fun JsonElement.asShareInput(): ShareInput {
    val o = jsonObject
    return ShareInput(
        userId = o.getValue("userId").jsonPrimitive.content,
        weight = o["weight"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.double,
    )
}

private fun ShareResult.toJson(): JsonElement =
    JsonObject(mapOf("userId" to JsonPrimitive(userId), "amount" to JsonPrimitive(amount)))

private fun JsonElement.asShareResult(): ShareResult {
    val o = jsonObject
    return ShareResult(o.getValue("userId").jsonPrimitive.content, o.getValue("amount").jsonPrimitive.long)
}

private fun JsonElement.asLineAssignment(): LineAssignment {
    val o = jsonObject
    return LineAssignment(
        lineId = o.getValue("lineId").jsonPrimitive.content,
        mode = o.getValue("mode").jsonPrimitive.content,
        shares = o.getValue("shares").jsonArray.map { it.asShareInput() },
    )
}

private fun JsonElement.asLongMap(): Map<String, Long> = jsonObject.mapValues { (_, v) -> v.jsonPrimitive.long }

private fun JsonElement.asPerLineMap(): Map<String, List<ShareResult>> =
    jsonObject.mapValues { (_, v) -> v.jsonArray.map { it.asShareResult() } }

// ---------------------------------------------------------------------------
// receipts-allocate
// ---------------------------------------------------------------------------

fun registerReceiptsAllocateVectors() {
    val domain = "receipts-allocate"

    FunctionRegistry.register(domain, "splitByWeights") { input ->
        val o = input.jsonObject
        val total = o.getValue("total").jsonPrimitive.long
        val weights = o.getValue("weights").jsonArray.map { it.jsonPrimitive.double }
        JsonArray(splitByWeights(total, weights).map { JsonPrimitive(it) })
    }

    FunctionRegistry.register(domain, "splitEqual") { input ->
        val o = input.jsonObject
        val total = o.getValue("total").jsonPrimitive.long
        val n = o.getValue("n").jsonPrimitive.int
        JsonArray(splitEqual(total, n).map { JsonPrimitive(it) })
    }

    FunctionRegistry.register(domain, "allocateItem") { input ->
        val o = input.jsonObject
        val amount = o.getValue("amount").jsonPrimitive.long
        val shares = o.getValue("shares").jsonArray.map { it.asShareInput() }
        val mode = o.getValue("mode").jsonPrimitive.content
        JsonArray(allocateItem(amount, shares, mode).map { it.toJson() })
    }

    FunctionRegistry.register(domain, "allocateProportional") { input ->
        val o = input.jsonObject
        val amount = o.getValue("amount").jsonPrimitive.long
        val participants = o.getValue("participants").jsonArray.map { it.jsonPrimitive.content }
        val subtotalByUser = o.getValue("subtotalByUser").asLongMap()
        JsonArray(allocateProportional(amount, participants, subtotalByUser).map { it.toJson() })
    }

    FunctionRegistry.register(domain, "rollUp") { input ->
        val perLine = input.jsonObject.getValue("perLine").asPerLineMap()
        JsonObject(rollUp(perLine).mapValues { (_, v) -> JsonPrimitive(v) })
    }

    FunctionRegistry.register(domain, "allocateReceipt") { input ->
        val o = input.jsonObject
        val lines = o.getValue("lines").jsonArray.map { it.asReceiptLine() }
        val assignments = o.getValue("assignments").jsonArray.map { it.asLineAssignment() }
        val r = allocateReceipt(lines, assignments)
        JsonObject(
            mapOf(
                "perLine" to JsonObject(r.perLine.mapValues { (_, v) -> JsonArray(v.map { it.toJson() }) }),
                "byUser" to JsonObject(r.byUser.mapValues { (_, v) -> JsonPrimitive(v) }),
                "total" to JsonPrimitive(r.total),
                "itemSubtotalByUser" to JsonObject(r.itemSubtotalByUser.mapValues { (_, v) -> JsonPrimitive(v) }),
            )
        )
    }
}

// ---------------------------------------------------------------------------
// receipts-reconcile
// ---------------------------------------------------------------------------

private fun Subtotals.toJson(): JsonElement = JsonObject(
    mapOf(
        "items" to JsonPrimitive(items),
        "tax" to JsonPrimitive(tax),
        "serviceCharge" to JsonPrimitive(serviceCharge),
        "tip" to JsonPrimitive(tip),
        "discount" to JsonPrimitive(discount),
        "computed" to JsonPrimitive(computed),
    )
)

private fun ReconcileResult.toJson(): JsonElement = JsonObject(
    mapOf(
        "ok" to JsonPrimitive(ok),
        "reason" to JsonPrimitive(reason),
        "computed" to JsonPrimitive(computed),
        "stated" to (stated?.let { JsonPrimitive(it) } ?: JsonNull),
        "delta" to JsonPrimitive(delta),
        "subtotals" to subtotals.toJson(),
    )
)

fun registerReceiptsReconcileVectors() {
    val domain = "receipts-reconcile"

    FunctionRegistry.register(domain, "subtotals") { input ->
        val lines = input.jsonObject.getValue("lines").jsonArray.map { it.asReceiptLine() }
        subtotals(lines).toJson()
    }
    FunctionRegistry.register(domain, "reconcile") { input ->
        val draft = input.jsonObject.getValue("draft").asReceiptDraft()
        reconcile(draft).toJson()
    }
    FunctionRegistry.register(domain, "shouldEscalate") { input ->
        val draft = input.jsonObject.getValue("draft").asReceiptDraft()
        JsonPrimitive(shouldEscalate(draft))
    }
    FunctionRegistry.register(domain, "balanceWithLine") { input ->
        val o = input.jsonObject
        val draft = o.getValue("draft").asReceiptDraft()
        val id = o.getValue("id").jsonPrimitive.content
        val description = o.getValue("description").jsonPrimitive.content
        balanceWithLine(draft, id, description).toJson()
    }
}

// ---------------------------------------------------------------------------
// receipts-money-text
// ---------------------------------------------------------------------------

private fun NumberMatch.toJson(): JsonElement = JsonObject(
    mapOf(
        "raw" to JsonPrimitive(raw),
        "start" to JsonPrimitive(start),
        "end" to JsonPrimitive(end),
        "value" to JsonPrimitive(value),
    )
)

fun registerReceiptsMoneyTextVectors() {
    val domain = "receipts-money-text"

    FunctionRegistry.register(domain, "detectCurrency") { input ->
        val text = input.jsonObject.getValue("text").jsonPrimitive.content
        detectCurrency(text)?.let { JsonPrimitive(it) } ?: JsonNull
    }
    FunctionRegistry.register(domain, "parseMoney") { input ->
        val o = input.jsonObject
        val raw = o.getValue("raw").jsonPrimitive.content
        val minorDigits = o["minorDigits"]?.jsonPrimitive?.int ?: 2
        parseMoney(raw, minorDigits)?.let { JsonPrimitive(it) } ?: JsonNull
    }
    FunctionRegistry.register(domain, "findNumbers") { input ->
        val o = input.jsonObject
        val line = o.getValue("line").jsonPrimitive.content
        val minorDigits = o["minorDigits"]?.jsonPrimitive?.int ?: 2
        JsonArray(findNumbers(line, minorDigits).map { it.toJson() })
    }
    FunctionRegistry.register(domain, "findDate") { input ->
        val o = input.jsonObject
        val text = o.getValue("text").jsonPrimitive.content
        val today = o["today"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content
        findDate(text, today)?.let { JsonPrimitive(it) } ?: JsonNull
    }
    FunctionRegistry.register(domain, "findUnit") { input ->
        val text = input.jsonObject.getValue("text").jsonPrimitive.content
        findUnit(text)?.let { JsonPrimitive(it) } ?: JsonNull
    }
    FunctionRegistry.register(domain, "tidyDescription") { input ->
        val text = input.jsonObject.getValue("text").jsonPrimitive.content
        JsonPrimitive(tidyDescription(text))
    }
}

// ---------------------------------------------------------------------------
// receipts-parse
// ---------------------------------------------------------------------------

private fun JsonElement.asOcrToken(): OcrToken {
    val o = jsonObject
    return OcrToken(
        text = o.getValue("text").jsonPrimitive.content,
        x0 = o.getValue("x0").jsonPrimitive.double,
        x1 = o.getValue("x1").jsonPrimitive.double,
        y0 = o.getValue("y0").jsonPrimitive.double,
        y1 = o.getValue("y1").jsonPrimitive.double,
        confidence = o.getValue("confidence").jsonPrimitive.int,
    )
}

private fun OcrToken.toJson(): JsonElement = JsonObject(
    mapOf(
        "text" to JsonPrimitive(text),
        "x0" to jsonNumber(x0),
        "x1" to jsonNumber(x1),
        "y0" to jsonNumber(y0),
        "y1" to jsonNumber(y1),
        "confidence" to JsonPrimitive(confidence),
    )
)

private fun TextLine.toJson(): JsonElement = JsonObject(
    mapOf(
        "text" to JsonPrimitive(text),
        "tokens" to JsonArray(tokens.map { it.toJson() }),
        "y" to jsonNumber(y),
        "confidence" to JsonPrimitive(confidence),
    )
)

fun registerReceiptsParseVectors() {
    val domain = "receipts-parse"

    FunctionRegistry.register(domain, "groupIntoLines") { input ->
        val tokens = input.jsonObject.getValue("tokens").jsonArray.map { it.asOcrToken() }
        JsonArray(groupIntoLines(tokens).map { it.toJson() })
    }

    FunctionRegistry.register(domain, "linesFromText") { input ->
        val o = input.jsonObject
        val text = o.getValue("text").jsonPrimitive.content
        val confidence = o["confidence"]?.jsonPrimitive?.int ?: 100
        JsonArray(linesFromText(text, confidence).map { it.toJson() })
    }

    FunctionRegistry.register(domain, "parseReceiptText") { input ->
        val o = input.jsonObject
        val text = o.getValue("text").jsonPrimitive.content
        val currency = o.getValue("currency").jsonPrimitive.content
        val today = o["today"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content
        parseReceiptText(text, ParseOptions(currency = currency, today = today)).toJson()
    }

    // export.ts reuses the exact FIXTURES[0] fixture -- this vector's
    // input.lines field is a literal descriptive placeholder string
    // ("linesFromText(fixture.text)"), not real data, exactly like P1.4's
    // pickFriendInsights placeholder-input vector. Reconstruct the real
    // input from RECEIPT_FIXTURES by name rather than trying to parse the
    // placeholder.
    FunctionRegistry.register(domain, "parseReceipt") { input ->
        val o = input.jsonObject
        val fixtureName = o.getValue("fixture").jsonPrimitive.content
        val fixture = RECEIPT_FIXTURES.first { it.name == fixtureName }
        val optsJson = o.getValue("opts").jsonObject
        val opts = ParseOptions(
            currency = optsJson["currency"]?.jsonPrimitive?.content ?: fixture.currency,
            today = optsJson["today"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
            idPrefix = optsJson["idPrefix"]?.jsonPrimitive?.content ?: "l",
        )
        parseReceipt(linesFromText(fixture.text), opts).toJson()
    }
}
