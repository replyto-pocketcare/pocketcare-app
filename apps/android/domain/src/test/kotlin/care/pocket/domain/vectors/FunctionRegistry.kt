package care.pocket.domain.vectors

import kotlinx.serialization.json.JsonElement

/**
 * fn implementations, empty until each Phase 1 porting task (plan §5)
 * registers its own. Keyed by (domain, fn) rather than fn alone since the
 * vector JSON's "fn" field is a bare function name (e.g. "convert") that
 * isn't unique across domains — money.json and finance.json could both
 * have a "convert", and a flat map would let one silently clobber the
 * other.
 *
 * A porting task un-skips its vectors by calling [register] from an
 * @BeforeClass / companion-object init in its own test file — this file
 * stays untouched by every Phase 1 task.
 */
object FunctionRegistry {
    private val impls = mutableMapOf<Pair<String, String>, (JsonElement) -> JsonElement>()

    fun register(domain: String, fn: String, impl: (JsonElement) -> JsonElement) {
        impls[domain to fn] = impl
    }

    fun lookup(domain: String, fn: String): ((JsonElement) -> JsonElement)? = impls[domain to fn]
}
