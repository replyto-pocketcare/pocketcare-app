package care.pocket.domain.vectors

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

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
    return if (n.isFinite() && n == Math.floor(n)) JsonPrimitive(n.toLong()) else JsonPrimitive(n)
}
