package com.sanvya.app.domain.vectors

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

/**
 * Mirrors the shape tools/golden-vectors/export.ts writes: either
 * {fn, input, expected} for a normal case, or {fn, input, throws} for a
 * case that should throw. `expected`/`throws` are both nullable because
 * exactly one is present per vector, never both.
 */
@Serializable
data class ThrowsSpec(val name: String, val message: String)

@Serializable
data class Vector(
    val fn: String,
    val input: JsonElement,
    val expected: JsonElement? = null,
    val throws: ThrowsSpec? = null,
)

private val json = Json { ignoreUnknownKeys = true }

/**
 * Loads one domain's vectors from the test classpath. The resource comes
 * from tools/golden-vectors/vectors/<domain>.json via the resources
 * source set configured in domain/build.gradle.kts — not copied here, so
 * it can never drift from the file the iOS runner also reads.
 */
fun loadVectors(domain: String): List<Vector> {
    val resource = "/$domain.json"
    val stream = object {}.javaClass.getResourceAsStream(resource)
        ?: error(
            "vectors$resource not found on the test classpath. Check " +
                "domain/build.gradle.kts's sourceSets.test.resources.srcDir " +
                "points at tools/golden-vectors/vectors, and that the file exists there."
        )
    val text = stream.bufferedReader().use { it.readText() }
    return json.decodeFromString(text)
}

/**
 * Renders a Double the way JavaScript's JSON.stringify does: whole
 * numbers get no trailing decimal point ("500", not "500.0"). Every
 * porting task should use this for raw (non-money-string) numeric
 * results -- Money amounts always go through the domain's mny()-style
 * string encoding instead and never hit this, but plain numeric returns
 * (percentages, day counts, major-unit floats like Money.toMajor) are
 * compared by JsonElement equality against vectors exported straight
 * from V8, which never writes ".0" the way Kotlin's Double.toString()
 * does -- without this, a numerically-correct port fails on a
 * formatting technicality, not a real bug.
 */
fun jsonNumber(n: Double): JsonElement {
    // Not finite (Infinity/-Infinity/NaN) mirrors JS's JSON.stringify(Infinity)
    // === "null" -- P1.3's finance domain is the first port to actually
    // produce Infinity results (periodsToGoal/percentOfIncome/budgetProgress
    // pct on a zero limit or income), so this branch was previously untested
    // and just fell through to JsonPrimitive(Double.POSITIVE_INFINITY), which
    // is wrong.
    if (!n.isFinite()) return JsonNull
    return if (n == Math.floor(n)) JsonPrimitive(n.toLong()) else JsonPrimitive(n)
}

/**
 * Recursively compares two JsonElements the way the vector runner actually
 * needs: numeric JSON values compared by VALUE (parsed Double), not by
 * kotlinx.serialization's default JsonPrimitive equality, which compares the
 * raw `content` STRING -- so a genuinely fractional double (e.g.
 * periodicRateFromAnnual's 0.006666666666666667) would only match if
 * Kotlin's Double-to-string formatting happens to produce the exact same
 * digit sequence V8 wrote when the vector was exported, which is not
 * guaranteed. String content (money's decimal-string amounts, ids, ISO date
 * strings) still compares as plain text -- only unquoted JSON numbers get
 * the value-based treatment. Swift's NSNumber-based `isEqual` already does
 * this correctly by default (documented in Money's port), so this fix is
 * Kotlin-only; a real, not assumed, platform asymmetry.
 */
fun jsonElementsEqual(a: JsonElement, b: JsonElement): Boolean {
    return when {
        a is JsonNull || b is JsonNull -> a is JsonNull && b is JsonNull
        a is JsonArray && b is JsonArray ->
            a.size == b.size && a.indices.all { jsonElementsEqual(a[it], b[it]) }
        a is JsonObject && b is JsonObject ->
            a.keys == b.keys && a.keys.all { jsonElementsEqual(a.getValue(it), b.getValue(it)) }
        a is JsonPrimitive && b is JsonPrimitive -> {
            if (a.isString != b.isString) return false
            if (a.isString) return a.content == b.content
            val aBool = a.booleanOrNull
            val bBool = b.booleanOrNull
            if (aBool != null || bBool != null) return aBool == bBool
            val aNum = a.doubleOrNull
            val bNum = b.doubleOrNull
            if (aNum != null && bNum != null) return aNum == bNum
            a.content == b.content
        }
        else -> false
    }
}
