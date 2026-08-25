package com.sanvya.app.data.auth

import android.content.Intent
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.handleDeeplinks
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

interface AuthRepository {
    val currentUserId: StateFlow<String?>
    val authState: Flow<AuthState>
    
    suspend fun ensureGuest(): String

    /**
     * True when the signed-in user is anonymous.
     *
     * Auth.kt has had `isGuest(client)` since P2.4a but nothing exposed it, so
     * no caller above :data could ask. Google sign-in has to: a guest gets a
     * LINK (same UID, data preserved), everyone else a sign-in. iOS's
     * AuthRepository already had this method.
     */
    suspend fun isGuest(): Boolean

    /** Link-or-sign-in with Google. See Auth.kt's `continueWithGoogle`. */
    suspend fun continueWithGoogle()

    /**
     * Feed an OAuth callback Intent back to Supabase, completing a sign-in that
     * `continueWithGoogle()` started in the browser.
     *
     * This exists so `:app` never names `SupabaseClient`. MainActivity used to
     * inject the client and call `handleDeeplinks(intent)` on it directly,
     * which does not compile: supabase-kt is an `implementation` dependency of
     * `:data`, so it is deliberately absent from `:app`'s compile classpath.
     * (Same shape of mistake as the `androidx.window` one in W1.5 — an
     * `implementation` dep is invisible to consumers by design, and reaching
     * for it is the compiler telling you the layering is wrong, not that the
     * dependency is missing.)
     *
     * Not suspending: supabase-kt parses the URI and hands the session to its
     * own scope, and MainActivity has no coroutine scope at that point in
     * `onCreate`/`onNewIntent`.
     */
    fun handleAuthCallback(intent: Intent)

    suspend fun signInWithGoogle(idToken: String)
    suspend fun sendOtp(email: String)
    suspend fun verifyOtp(email: String, token: String)
    suspend fun signUp(email: String, password: String, username: String)
    suspend fun signInWithPassword(email: String, password: String)

    /** Password reset, step 1 — send a 6-digit code. See Auth.kt. */
    suspend fun sendPasswordReset(email: String)

    /** Step 2 — verify it. Uses the RECOVERY OTP type, not the generic one. */
    suspend fun verifyPasswordResetCode(email: String, token: String)

    /** Step 3 — set the new password on the recovery session. */
    suspend fun setPassword(password: String)
    suspend fun signOut()
}

class AuthRepositoryImpl(
    private val client: SupabaseClient
) : AuthRepository {

    private val _currentUserId = MutableStateFlow<String?>(null)
    override val currentUserId: StateFlow<String?> = _currentUserId.asStateFlow()

    override val authState: Flow<AuthState> = client.auth.sessionStatus.map { status ->
        when (status) {
            is SessionStatus.Authenticated -> AuthState.SIGNED_IN_ONLINE // Simplified for now
            else -> AuthState.SIGNED_OUT
        }
    }

    // Was GlobalScope.launch. GlobalScope is a delicate API for exactly this
    // reason: the coroutine it starts cannot be cancelled by anything, so a
    // second instance of this class (a test, an instrumentation run) leaves the
    // first one collecting forever. A scope the object owns is cancellable, and
    // SupervisorJob keeps a failure in this collector from taking down siblings
    // if more are ever added here.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    init {
        scope.launch {
            client.auth.sessionStatus.collect { status ->
                _currentUserId.value = when (status) {
                    is SessionStatus.Authenticated -> status.session.user?.id
                    else -> null
                }
            }
        }
    }

    override suspend fun ensureGuest(): String {
        return ensureUser(client)
    }

    override suspend fun isGuest(): Boolean =
        com.sanvya.app.data.auth.isGuest(client)

    override suspend fun continueWithGoogle() {
        com.sanvya.app.data.auth.continueWithGoogle(client)
    }

    override fun handleAuthCallback(intent: Intent) {
        client.handleDeeplinks(intent)
    }

    override suspend fun signInWithGoogle(idToken: String) {
        com.sanvya.app.data.auth.signInWithGoogle(client, idToken)
    }

    override suspend fun sendOtp(email: String) {
        com.sanvya.app.data.auth.sendOtp(client, email)
    }

    override suspend fun verifyOtp(email: String, token: String) {
        com.sanvya.app.data.auth.verifyOtp(client, email, token)
    }

    override suspend fun signUp(email: String, password: String, username: String) {
        client.auth.signUpWith(io.github.jan.supabase.auth.providers.builtin.Email) {
            this.email = email
            this.password = password
            // Web sends `options: { data: { username } }` (login/page.tsx), which
            // lands in raw_user_meta_data and is what the app reads back as the
            // display name. The old comment here said "username could be sent in
            // data if needed" and then did not send it -- so an Android sign-up
            // produced an account with no name, and the parameter was accepted
            // and discarded. Blank usernames are omitted rather than written as
            // "", matching web's trim().
            if (username.isNotBlank()) {
                data = kotlinx.serialization.json.buildJsonObject {
                    put("username", kotlinx.serialization.json.JsonPrimitive(username.trim()))
                }
            }
        }
    }

    override suspend fun signInWithPassword(email: String, password: String) {
        client.auth.signInWith(io.github.jan.supabase.auth.providers.builtin.Email) {
            this.email = email
            this.password = password
        }
    }

    override suspend fun sendPasswordReset(email: String) {
        com.sanvya.app.data.auth.sendPasswordReset(client, email)
    }

    override suspend fun verifyPasswordResetCode(email: String, token: String) {
        com.sanvya.app.data.auth.verifyPasswordResetCode(client, email, token)
    }

    override suspend fun setPassword(password: String) {
        com.sanvya.app.data.auth.setPassword(client, password)
    }

    override suspend fun signOut() {
        com.sanvya.app.data.auth.signOut(client)
    }
}
