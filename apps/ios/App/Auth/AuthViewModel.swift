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

    /// The three steps of a password reset, plus "not resetting".
    ///
    /// A separate axis from `otpSent`, not a fifth value of it: sign-in-by-OTP
    /// and reset-by-OTP both show a 6-digit field, but they verify with
    /// DIFFERENT OTP types and end somewhere different. Collapsing them into
    /// one flag is how the wrong type gets used.
    public enum ResetStage: Sendable { case none, email, code, newPassword }
    public var resetStage: ResetStage = .none
    public var confirmPassword: String = ""
    
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

    /// Enter the reset flow from the sign-in screen.
    @MainActor
    public func startPasswordReset() {
        resetStage = .email
        error = nil
    }

    /// Leave it — back to ordinary sign-in.
    @MainActor
    public func cancelPasswordReset() {
        resetStage = .none
        error = nil
    }

    /// Step 1 — send the code. Advances even though the call cannot tell us
    /// whether the account exists; see Auth.swift on why it must not.
    @MainActor
    public func sendPasswordReset() async {
        guard !email.isEmpty else { return }
        await run { try await self.authRepository.sendPasswordReset(email: self.email) } onSuccess: {
            self.resetStage = .code
        }
    }

    /// Step 2 — verify. Success leaves a short-lived recovery session.
    @MainActor
    public func verifyPasswordResetCode() async {
        guard !otp.isEmpty else { return }
        await run {
            try await self.authRepository.verifyPasswordResetCode(email: self.email, token: self.otp)
        } onSuccess: {
            self.resetStage = .newPassword
        }
    }

    /// Step 3 — set it. The auth gate takes over once the session is live.
    @MainActor
    public func setNewPassword() async {
        guard password.count >= Self.minPasswordLength, password == confirmPassword else { return }
        await run { try await self.authRepository.setPassword(self.password) } onSuccess: {
            self.resetStage = .none
        }
    }

    /// Web's `password.length < 8` check, named rather than inline.
    public static let minPasswordLength = 8

    /// One place that sets `isLoading`, clears the error, and reports failure.
    ///
    /// The four reset methods would otherwise repeat the same six lines each,
    /// which is how one of them ends up not clearing `error` and showing a
    /// stale message on the next step.
    @MainActor
    private func run(
        _ block: () async throws -> Void,
        onSuccess: () -> Void
    ) async {
        isLoading = true
        error = nil
        do {
            try await block()
            onSuccess()
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
