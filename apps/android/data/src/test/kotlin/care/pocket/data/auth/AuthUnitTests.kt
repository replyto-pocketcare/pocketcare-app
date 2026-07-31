package care.pocket.data.auth

import kotlin.test.Test
import kotlin.test.assertEquals

class AuthUnitTests {

    @Test
    fun testAuthStateNames() {
        // Ensure enum values compile and have the expected names.
        assertEquals("SIGNED_OUT", AuthState.SIGNED_OUT.name)
        assertEquals("SIGNED_IN_OFFLINE", AuthState.SIGNED_IN_OFFLINE.name)
        assertEquals("SIGNED_IN_ONLINE", AuthState.SIGNED_IN_ONLINE.name)
    }
}
