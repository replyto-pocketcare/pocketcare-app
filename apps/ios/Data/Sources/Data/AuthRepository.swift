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
    func signInWithGoogle(idToken: String, nonce: String?) async throws
    func signInWithApple(idToken: String, nonce: String) async throws
    func signOut() async throws
}

public final class AuthRepositoryImpl: AuthRepository, @unchecked Sendable {
    private let client: SupabaseClient
    
    public init(client: SupabaseClient) {
        self.client = client
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
    
    public var currentUserId: String? {
        // Synchronous access is not directly possible via SupabaseClient in the latest versions
        // unless caching. We return a placeholder or need to await it. 
        // For synchronous UI needs, the ViewModel should cache it.
        // In Supabase Swift SDK 2.x, `client.auth.session` is async.
        // We will return nil for sync access, users should rely on async state.
        nil 
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
    
    public func signInWithGoogle(idToken: String, nonce: String?) async throws {
        try await authSignInWithGoogle(client: client, idToken: idToken, nonce: nonce)
    }
    
    public func signInWithApple(idToken: String, nonce: String) async throws {
        try await authSignInWithApple(client: client, idToken: idToken, nonce: nonce)
    }
    
    public func signOut() async throws {
        try await authSignOut(client: client)
    }
}
