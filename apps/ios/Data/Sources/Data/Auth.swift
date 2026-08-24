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
        return session.user.id.canonicalString
    }
    try await client.auth.signInAnonymously()
    let session = try await client.auth.session
    return session.user.id.canonicalString
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

// MARK: - signUp / signInWithPassword

/// Register a fresh account with email + password.
///
/// Missing on iOS entirely until now, while Android's repository has had it
/// since P2.4a — so a user who registered on web could sign in on Android and
/// not on their iPhone (PARITY_AUDIT §6c).
///
/// `username` goes into user metadata exactly as web does
/// (`options: { data: { username } }` in login/page.tsx); it is what the app
/// reads back as the display name. Blank is omitted rather than written as an
/// empty string, matching web's `trim()`.
public func authSignUp(
    client: SupabaseClient,
    email: String,
    password: String,
    username: String
) async throws {
    let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
    try await client.auth.signUp(
        email: email,
        password: password,
        data: trimmed.isEmpty ? nil : ["username": .string(trimmed)]
    )
}

/// Sign in an existing account with email + password.
public func authSignInWithPassword(
    client: SupabaseClient,
    email: String,
    password: String
) async throws {
    try await client.auth.signIn(email: email, password: password)
}

// MARK: - continueWithGoogle
//
// authSignInWithGoogle above is the ID-token exchange: the app obtains a Google
// ID token itself (the Sign in with Google SDK) and posts it to GoTrue. It is
// the slicker flow and it is kept, because the non-guest case can use it.
//
// It cannot be the ONLY flow, because of what web actually does. login/page.tsx
// branches:
//
//     const isGuest = session?.user?.is_anonymous
//     isGuest ? supabase.auth.linkIdentity({ provider: "google", options })
//             : supabase.auth.signInWithOAuth({ provider: "google", options })
//
// The guest branch LINKS Google to the existing anonymous user, so the UID is
// unchanged and every row the guest already entered stays theirs. Sign-in
// creates or switches to a different user. On web the difference is a nicety;
// in a native app it is the difference between an upgrade and silently
// abandoning everything the user typed before they registered — the local
// PowerSync database is keyed by user id, so a UID change orphans the lot.
//
// GoTrue has no ID-token equivalent of linkIdentity: linking is defined as a
// browser redirect to the provider and back. So the guest path has to be a
// browser flow, and once one path is a browser flow, making both browser flows
// is what keeps the two from behaving differently in ways nobody notices until
// a user loses data. Android takes the same decision, for the same reason.
//
// ASWebAuthenticationSession (which supabase-swift drives here) is also the
// flow Apple sanctions for third-party sign-in, and it needs no additional SDK.

/// Continue with Google, choosing link-vs-sign-in exactly as web does.
///
/// Presents `ASWebAuthenticationSession` and returns once the session has been
/// established or the user has cancelled — unlike Android, where the browser is
/// a separate task and the result arrives back through a deep link.
@MainActor
public func authContinueWithGoogle(client: SupabaseClient, redirectURL: URL) async throws {
    if await authIsGuest(client: client) {
        try await client.auth.linkIdentity(provider: .google, redirectTo: redirectURL)
    } else {
        try await client.auth.signInWithOAuth(provider: .google, redirectTo: redirectURL)
    }
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
