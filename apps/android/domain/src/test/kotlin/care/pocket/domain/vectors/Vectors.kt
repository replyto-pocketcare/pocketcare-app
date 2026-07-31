package care.pocket.domain.vectors

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

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
