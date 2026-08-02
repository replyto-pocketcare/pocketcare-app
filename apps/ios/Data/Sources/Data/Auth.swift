import Foundation

// Auth helpers — one identity from first launch.
//
// Ported from packages/db/src/auth.ts (P2.4b).
// Mirrors apps/android/data/.../auth/Auth.kt (P2.4a).
//
// A guest is a real Supabase user with is_anonymous = true. Registering
// upgrades the SAME UID in place — no data is ever re-keyed or copied.
//
// Platform storage on iOS: Keychain adapter (SecureStore) passed into
// SupabaseClient at construction time (wired at the App layer, not here).
//
// Offline marker: the NWPathMonitor + PowerSync's own sync-status publisher
// tell us "signed in but offline" vs "signed out". We expose AuthState
// so the UI can distinguish these cases without a network round-trip.

import Supabase

// MARK: - ensureUser

/// Ensure there is a session; sign in anonymously (guest) if none exists.
///
/// Mirrors ensureUser(client) in auth.ts.
public func authEnsureUser(client: SupabaseClient) async throws -> String {
    if let session = try? await client.auth.session {
        return session.user.id.uuidString
    }
    try await client.auth.signInAnonymously()
    let session = try await client.auth.session
    return session.user.id.uuidString
}

// MARK: - isGuest

/// True if the current user is a guest (anonymous).
///
/// Mirrors isGuest(client) in auth.ts.
/// Supabase exposes `isAnonymous` on the User object for anonymous sessions.
public func authIsGuest(client: SupabaseClient) async -> Bool {
    guard let session = try? await client.auth.session else { return false }
    return session.user.isAnonymous
}

// MARK: - upgradeGuestWithEmail

/// Upgrade the current anonymous user to a registered account IN PLACE via
/// email + password. The UID is unchanged, so every existing row stays owned
/// by this user. After email confirmation the same user is now non-anonymous.
///
/// Mirrors upgradeGuestWithEmail in auth.ts.
public func authUpgradeGuestWithEmail(
    client: SupabaseClient,
    email: String,
    password: String
) async throws {
    try await client.auth.update(user: UserAttributes(
        email: email,
        password: password
    ))
}

// MARK: - sendOtp / verifyOtp

/// Send an OTP to the given email (magic link / OTP sign-in).
public func authSendOtp(client: SupabaseClient, email: String) async throws {
    try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
}

/// Verify an OTP token received by the user (completes the magic-link / OTP flow).
public func authVerifyOtp(client: SupabaseClient, email: String, token: String) async throws {
    try await client.auth.verifyOTP(email: email, token: token, type: .email)
}

// MARK: - signInWithGoogle

/// Initiate Google sign-in with an ID token obtained from ASAuthorizationAppleIDProvider
/// or Google Sign-In SDK.
///
/// The caller is responsible for presenting the sign-in UI and passing the
/// resulting token here — this function is intentionally decoupled from the
/// presentation layer.
public func authSignInWithGoogle(client: SupabaseClient, idToken: String, nonce: String? = nil) async throws {
    try await client.auth.signInWithIdToken(
        credentials: .init(provider: .google, idToken: idToken, nonce: nonce)
    )
}

// MARK: - signInWithApple

/// Sign in with Apple (iOS-native, preferred for App Store compliance).
/// Pass the ID token and raw nonce from ASAuthorizationAppleIDCredential.
public func authSignInWithApple(
    client: SupabaseClient,
    idToken: String,
    nonce: String
) async throws {
    try await client.auth.signInWithIdToken(
        credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
    )
}

// MARK: - signOut

/// Sign out the current user, clearing the local session.
///
/// After this call, ensureUser() will create a new anonymous guest.
/// The caller is responsible for clearing the offline marker in UserDefaults/
/// the App layer and triggering a PowerSync schema reset for a "switch account"
/// flow.
public func authSignOut(client: SupabaseClient) async throws {
    try await client.auth.signOut()
}

// MARK: - AuthState (offline marker)

/// Offline authentication marker.
///
/// When the device is offline, PowerSync stops syncing but the user remains
/// "logged in" from their perspective. Without a marker, the UI would have to
/// guess whether the user is signed out or just offline. This enum is the
/// explicit answer.
///
/// Mirrors the intent of auth.ts's design note: "offline marker so the UI can
/// tell 'signed out' from 'signed in but offline'".
///
/// Persisted to UserDefaults at the App layer (not here) so the marker
/// survives cold starts. The App layer updates it on every Supabase auth state
/// change.
public enum AuthState: String, Sendable, Codable {
    /// No session — the user is genuinely signed out.
    case signedOut
    /// A session exists (guest or registered) but the device is offline.
    case signedInOffline
    /// A session exists and PowerSync is actively syncing.
    case signedInOnline
}

/// Derive the current AuthState from the Supabase session + network status.
///
/// - Parameter isOnline: true if the device has a working network connection
///   (determined by the caller — e.g. NWPathMonitor or PowerSync status).
public func authCurrentAuthState(
    client: SupabaseClient,
    isOnline: Bool
) async -> AuthState {
    let session = try? await client.auth.session
    guard session != nil else { return .signedOut }
    return isOnline ? .signedInOnline : .signedInOffline
}

// MARK: - Errors

public enum AuthError: LocalizedError {
    case anonymousSignInFailed

    public var errorDescription: String? {
        switch self {
        case .anonymousSignInFailed:
            return "Anonymous sign-in failed."
        }
    }
}
