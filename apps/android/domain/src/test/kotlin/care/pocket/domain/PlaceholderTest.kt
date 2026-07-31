package care.pocket.domain

import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Proves `./gradlew test` runs kotlin.test in :domain (P0.2 Done-when).
 * The real golden-vector runner is P0.4a — this stays a placeholder until
 * that task wires up JSON vector loading.
 */
class PlaceholderTest {
    @Test
    fun domainModuleIsWired() {
        assertTrue(DomainSkeleton.READY)
    }
}
