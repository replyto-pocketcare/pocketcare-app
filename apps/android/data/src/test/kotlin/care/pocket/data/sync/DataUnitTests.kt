package care.pocket.data.sync

import kotlin.test.Test
import kotlin.test.assertEquals

// DataTests — placeholder for P2.2a/P2.4a unit tests.
//
// The real gate for P2.2a/P2.4a is TP L3 (sync integration against a local
// Supabase + PowerSync project). Unit tests here cover the pure logic
// (opKey, AuthState, encodePayload) that doesn't need a real PowerSync DB.

class DataUnitTests {

    @Test
    fun testOpKeyFormat() {
        val key = opKey("transactions", "PUT", "abc-123")
        assertEquals("transactions|PUT|abc-123", key)
    }

    @Test
    fun testEncodePayloadNull() {
        assertEquals("{}", encodePayload(null))
    }

    @Test
    fun testEncodePayloadBasic() {
        val json = encodePayload(mapOf("note" to "test", "amount" to 1000))
        assert(json.contains("\"note\"")) { "Expected 'note' in payload JSON" }
        assert(json.contains("\"amount\"")) { "Expected 'amount' in payload JSON" }
    }
}
