package care.pocket.data.auth

/**
 * Auth helpers — one identity from first launch.
 *
 * Ported from packages/db/src/auth.ts (P2.4a).
 *
 * A guest is a real Supabase user with is_anonymous = true. Registering
 * upgrades the SAME UID in place — no data is ever re-keyed or copied.
 *
 * Platform storage on Android: EncryptedSharedPreferences adapter passed into
 * SupabaseClient at construction time (wired at the App level, not here).
 *
 * Offline marker: the ConnectivityManager + PowerSync's own sync-status Flow
 * tell us "signed in but offline" vs "signed out". We persist a minimal
 * marker in DataStore so the UI can distinguish these cases without a
 * network round-trip on cold start.
 */

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.OTP

/**
 * Ensure there is a session; sign in anonymously (guest) if none exists.
 *
 * Identical semantics to ensureUser(client) in auth.ts.
 */
suspend fun ensureUser(client: SupabaseClient): String {
    val session = client.auth.currentSessionOrNull()
    if (session?.user != null) return session.user!!.id

    client.auth.signInAnonymously()
    val anon = client.auth.currentUserOrNull()
        ?: throw IllegalStateException("Anonymous sign-in failed")
    return anon.id
}

/**
 * True if the current user is a guest (anonymous).
 *
 * Mirrors isGuest(client) in auth.ts. The TS source calls getUser() (a network
 * round-trip) to get the authoritative is_anonymous claim from Supabase.
 * Here we use retrieveCurrentUser() which is the supabase-kt equivalent.
 */
suspend fun isGuest(client: SupabaseClient): Boolean {
    val user = try {
        val token = client.auth.currentAccessTokenOrNull() ?: return false
        client.auth.retrieveUser(token)
    } catch (_: Exception) {
        return false
    }
    // isAnonymous was removed/moved in newer supabase-kt. Check appMetadata provider.
    return user.appMetadata?.get("provider")?.let { it as? kotlinx.serialization.json.JsonPrimitive }?.content == "anonymous"
}

/**
 * Upgrade the current anonymous user to a registered account IN PLACE via
 * email + password. The UID is unchanged, so every existing row stays owned
 * by this user.
 *
 * After email confirmation the same user is now non-anonymous.
 *
 * Mirrors upgradeGuestWithEmail in auth.ts.
 */
suspend fun upgradeGuestWithEmail(
    client: SupabaseClient,
    email: String,
    password: String,
) {
    client.auth.updateUser {
        this.email = email
        this.password = password
    }
}

/**
 * Send an OTP to the given email (magic link / OTP sign-in).
 * Used for the non-guest sign-in flow (no anonymous precursor).
 */
suspend fun sendOtp(client: SupabaseClient, email: String) {
    client.auth.signInWith(OTP) {
        this.email = email
        // createUser: if no account exists, create one. Mirrors the web's
        // behavior of treating OTP as both sign-up and sign-in.
        createUser = true
    }
}

/**
 * Verify an OTP token received by the user (completes the OTP sign-in flow
 * started by sendOtp, above — NOT specifically a magic-link flow).
 */
suspend fun verifyOtp(client: SupabaseClient, email: String, token: String) {
    // OtpType.Email.EMAIL is the generic email-OTP case, matching sendOtp's
    // generic createUser=true flow (not .MAGIC_LINK, a distinct, more specific
    // OTP type for a dedicated magic-link flow this app doesn't use). Verified
    // against Supabase's own Kotlin reference example (supabase.com/docs/
    // reference/kotlin/auth-verifyotp), which uses exactly this case; also
    // matches Auth.swift's `.email` case on iOS — cross-platform consistent.
    client.auth.verifyEmailOtp(
        type = io.github.jan.supabase.auth.OtpType.Email.EMAIL,
        email = email,
        token = token,
    )
}

/**
 * Initiate Google sign-in. The [idToken] is the credential returned by
 * Google's Credential Manager on Android (Credential Manager API, not the
 * deprecated Activity-based flow).
 *
 * The caller is responsible for invoking Credential Manager and passing the
 * token here — this function is intentionally platform-agnostic about HOW
 * the token is obtained, only about how it's exchanged with Supabase.
 */
suspend fun signInWithGoogle(client: SupabaseClient, idToken: String) {
    client.auth.signInWith(io.github.jan.supabase.auth.providers.builtin.IDToken) {
        provider = Google
        this.idToken = idToken
    }
}

/**
 * Sign out the current user, clearing the local session.
 *
 * After this call, ensureUser() will create a new anonymous guest — so
 * calling this should be paired with clearing the offline marker in DataStore
 * and (for a "switch account" flow) triggering a PowerSync schema reset.
 */
suspend fun signOut(client: SupabaseClient) {
    client.auth.signOut()
}

/**
 * Offline authentication marker.
 *
 * When the device is offline, PowerSync stops syncing but the user remains
 * "logged in" from their perspective. Without a marker, the UI would have to
 * guess whether the user is signed out or just offline. This enum is the
 * explicit answer.
 *
 * Persisted to DataStore (at the App layer, not here) so the marker survives
 * cold starts. The App layer writes it on every auth state change from the
 * Supabase auth Flow.
 *
 * Mirrors the intent of auth.ts's comment: "offline marker so the UI can
 * tell 'signed out' from 'signed in but offline'".
 */
enum class AuthState {
    /** No session — the user is genuinely signed out. */
    SIGNED_OUT,
    /** A session exists (guest or registered) but the device is offline. */
    SIGNED_IN_OFFLINE,
    /** A session exists and PowerSync is actively syncing. */
    SIGNED_IN_ONLINE,
}

/**
 * Derive the current AuthState from the Supabase session + network/sync status.
 *
 * [isOnline]: true if the device has a working network connection (determined
 *             by the caller — e.g. ConnectivityManager or PowerSync status).
 */
suspend fun currentAuthState(client: SupabaseClient, isOnline: Boolean): AuthState {
    val session = client.auth.currentSessionOrNull()
    return when {
        session == null -> AuthState.SIGNED_OUT
        isOnline -> AuthState.SIGNED_IN_ONLINE
        else -> AuthState.SIGNED_IN_OFFLINE
    }
}
