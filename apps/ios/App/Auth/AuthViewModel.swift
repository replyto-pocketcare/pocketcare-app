import Foundation
import SwiftUI
import Factory
import Data

@Observable
@MainActor
public final class AuthViewModel {
    private let authRepository: AuthRepository
    
    public private(set) var authState: AuthState = .signedOut
    public private(set) var isLoading: Bool = false
    public private(set) var error: String? = nil
    public var email: String = ""
    public var password: String = ""
    public var otp: String = ""
    public var otpSent: Bool = false

    /// Which way in the user is currently using. Matches Android's
    /// `LoginScreen.Mode` so the two screens offer the same two doors.
    public enum Mode: Sendable { case password, otp }
    public var mode: Mode = .password
    
    public init(authRepository: AuthRepository) {
        self.authRepository = authRepository
        Task {
            for await state in authRepository.authState {
                await MainActor.run {
                    self.authState = state
                }
            }
        }
    }
    
    @MainActor
    public func continueAsGuest() async {
        isLoading = true
        error = nil
        do {
            _ = try await authRepository.ensureUser()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
    
    @MainActor
    public func sendOtp() async {
        guard !email.isEmpty else { return }
        isLoading = true
        error = nil
        do {
            try await authRepository.sendOtp(email: email)
            otpSent = true
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
    
    @MainActor
    public func verifyOtpAndSignIn() async {
        guard !email.isEmpty, !otp.isEmpty else { return }
        isLoading = true
        error = nil
        do {
            try await authRepository.verifyOtp(email: email, token: otp)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
    
    @MainActor
    public func signInWithPassword() async {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        error = nil
        do {
            try await authRepository.signInWithPassword(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Continue with Google.
    ///
    /// `isLoading` stays true across the whole call because
    /// `ASWebAuthenticationSession` is presented on top of this screen and the
    /// call does not return until it is dismissed — unlike Android, where the
    /// browser is a separate task and the result comes back through a deep
    /// link.
    ///
    /// A user cancellation arrives here as a thrown error like any other. It is
    /// reported rather than swallowed: silently returning to an unchanged
    /// screen after a browser flashed past reads as a broken button.
    @MainActor
    public func continueWithGoogle() async {
        isLoading = true
        error = nil
        do {
            try await authRepository.continueWithGoogle()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    public func signOut() async {
        isLoading = true
        do {
            try await authRepository.signOut()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
