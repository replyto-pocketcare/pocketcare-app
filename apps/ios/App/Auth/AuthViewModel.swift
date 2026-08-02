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
    public var otp: String = ""
    public var otpSent: Bool = false
    
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
