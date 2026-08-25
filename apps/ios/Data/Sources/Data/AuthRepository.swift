import Foundation
import Supabase

public protocol AuthRepository: Sendable {
    var authState: AsyncStream<AuthState> { get }
    var currentUserId: String? { get }
    
    func ensureUser() async throws -> String
    func isGuest() async -> Bool
    func upgradeGuestWithEmail(email: String, password: String) async throws
    func sendOtp(email: String) async throws
    func verifyOtp(email: String, token: String) async throws

    /// Register a fresh account. Missing on iOS until now — Android has had it
    /// since P2.4a, so a web-registered user could sign in there and not here.
    func signUp(email: String, password: String, username: String) async throws
    func signInWithPassword(email: String, password: String) async throws

    /// Password reset, step 1 — send a 6-digit code. See Auth.swift.
    func sendPasswordReset(email: String) async throws

    /// Step 2 — verify it. Uses the `.recovery` OTP type, not the generic one.
    func verifyPasswordResetCode(email: String, token: String) async throws

    /// Step 3 — set the new password on the recovery session.
    func setPassword(_ password: String) async throws

    /// Link-or-sign-in with Google. See Auth.swift's `authContinueWithGoogle`.
    func continueWithGoogle() async throws

    func signInWithGoogle(idToken: String, nonce: String?) async throws
    func signInWithApple(idToken: String, nonce: String) async throws
    func signOut() async throws
}

public final class AuthRepositoryImpl: AuthRepository, @unchecked Sendable {
    private let client: SupabaseClient
    private let config: SanvyaConfig

    public init(client: SupabaseClient, config: SanvyaConfig) {
        self.client = client
        self.config = config
    }
    
    public var authState: AsyncStream<AuthState> {
        AsyncStream { continuation in
            let task = Task {
                // Initial state
                let initial = await authCurrentAuthState(client: client, isOnline: true)
                continuation.yield(initial)
                
                // Observe Auth state changes from Supabase
                for await state in client.auth.authStateChanges {
                    // Re-calculate our custom AuthState based on session
                    let authState = await authCurrentAuthState(client: client, isOnline: true) // Assuming online for now, could be integrated with NWPathMonitor
                    continuation.yield(authState)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    /// The signed-in user's id, or nil when signed out.
    ///
    /// **This returned `nil` unconditionally** (P3.2c), with a comment claiming
    /// synchronous access was impossible. It is not: `auth.session` is async
    /// because it *refreshes*, but `auth.currentUser` is a `nonisolated` stored
    /// read off the local session store. Verified against supabase-swift
    /// v2.54.1 — the exact tag in Package.resolved — not from memory.
    ///
    /// The `nil` was not harmless. Most callers write
    /// `currentUserId ?? (try? await ensureUser())` and were fine, but four did
    /// not, and each silently did nothing:
    ///
    /// - `LoanDetailViewModel` — `if let userId = ...currentUserId` guarded the
    ///   EMI charge, so marking an EMI paid never posted it to the card.
    /// - `CreditCardsViewModel` (x2) — both settle paths returned
    ///   "Couldn't determine the current user."
    /// - `ReceiptReviewViewModel` — the save `guard` fell through silently.
    ///
    /// Worse, `RepairRepository` and `ReceiptsRepository` are constructed with
    /// `getUserId: { auth.currentUserId ?? "" }`, so they were writing rows with
    /// an EMPTY user_id.
    ///
    /// `.canonicalString`, not `.uuidString` — see Ids.swift.
    public var currentUserId: String? {
        client.auth.currentUser?.id.canonicalString
    }
    
    public func ensureUser() async throws -> String {
        try await authEnsureUser(client: client)
    }
    
    public func isGuest() async -> Bool {
        await authIsGuest(client: client)
    }
    
    public func upgradeGuestWithEmail(email: String, password: String) async throws {
        try await authUpgradeGuestWithEmail(client: client, email: email, password: password)
    }
    
    public func sendOtp(email: String) async throws {
        try await authSendOtp(client: client, email: email)
    }
    
    public func verifyOtp(email: String, token: String) async throws {
        try await authVerifyOtp(client: client, email: email, token: token)
    }
    
    public func signUp(email: String, password: String, username: String) async throws {
        try await authSignUp(client: client, email: email, password: password, username: username)
    }

    public func signInWithPassword(email: String, password: String) async throws {
        try await authSignInWithPassword(client: client, email: email, password: password)
    }

    public func continueWithGoogle() async throws {
        try await authContinueWithGoogle(client: client, redirectURL: config.authRedirectURL)
    }

    public func signInWithGoogle(idToken: String, nonce: String?) async throws {
        try await authSignInWithGoogle(client: client, idToken: idToken, nonce: nonce)
    }
    
    public func signInWithApple(idToken: String, nonce: String) async throws {
        try await authSignInWithApple(client: client, idToken: idToken, nonce: nonce)
    }
    
    public func sendPasswordReset(email: String) async throws {
        try await authSendPasswordReset(client: client, email: email)
    }

    public func verifyPasswordResetCode(email: String, token: String) async throws {
        try await authVerifyPasswordResetCode(client: client, email: email, token: token)
    }

    public func setPassword(_ password: String) async throws {
        try await authSetPassword(client: client, password: password)
    }

    public func signOut() async throws {
        try await authSignOut(client: client)
    }
}
