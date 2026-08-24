import SwiftUI
import Factory

/**
 Sign in, or continue as a guest.

 **This screen used to be a facade.** "Continue with Email" set a local
 `otpSent = true` and nothing else; "Verify & Sign In" called `onLoginSuccess()`
 directly. Neither ever reached `sendOtp` or `verifyOtp`, so any address and any
 code — or no code — "worked", and no session was ever created. `AuthViewModel`
 had the real implementations the whole time; the view simply kept its own
 `@State` mirrors and never called them.

 It now drives that view model, so the two states on screen are the two states
 authentication is actually in.

 Scope, matching web's `/login` minus what mobile does differently:
 - **Email OTP** and **guest** are here.
 - **Google** is not yet wired — the native flow needs an `idToken` from Google
   Sign-In, which is a dependency and a client-id decision, not a UI task. The
   button is therefore absent rather than present-and-dead, which is what
   created this bug in the first place.
 - **Email + password** exists on web and on neither native platform. Tracked in
   PARITY_AUDIT §6c; anyone who registered with a password cannot sign in here.
 */
struct LoginView: View {
    var onLoginSuccess: () -> Void
    var onContinueAsGuest: () -> Void

    @State private var viewModel = Container.shared.authViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 20) {
                SanvyaH1(S.Translation.appName, compact: false)
                    .foregroundStyle(Color.accent)

                SanvyaH2(viewModel.otpSent ? S.Login.verifyTitle : S.Login.signinTitle)

                Text(viewModel.otpSent
                     ? S.Login.sentCode(email: viewModel.email)
                     : S.Login.signinSub)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.otpSent { codeStep } else { emailStep }

                if let error = viewModel.error {
                    Text(error)
                        .sanvyaStyle(SanvyaType.statLabel)
                        .foregroundStyle(Color.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(S.Login.or)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text3)
                    .frame(maxWidth: .infinity)

                SanvyaButton(ghost: true) {
                    Task {
                        await viewModel.continueAsGuest()
                        if viewModel.error == nil { onContinueAsGuest() }
                    }
                } label: {
                    Text(S.Onboarding.tryGuest)
                }
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isLoading)
            }
            .padding(24)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg.ignoresSafeArea())
    }

    private var emailStep: some View {
        VStack(spacing: 12) {
            SanvyaInput(text: $viewModel.email, placeholder: S.Login.emailLabel)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SanvyaButton {
                Task { await viewModel.sendOtp() }
            } label: {
                Text(viewModel.isLoading ? S.Login.saving : S.Login.`continue`)
            }
            .frame(maxWidth: .infinity)
            // Guarding on the email being non-empty rather than validating it
            // here: Supabase is the authority on whether an address is real,
            // and a second opinion in the UI would only ever be wrong.
            .disabled(viewModel.isLoading || viewModel.email.isEmpty)
        }
    }

    private var codeStep: some View {
        VStack(spacing: 12) {
            SanvyaInput(text: $viewModel.otp, placeholder: S.Login.codePlaceholder)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)

            SanvyaButton {
                Task {
                    await viewModel.verifyOtpAndSignIn()
                    // Only on success. The old screen called this
                    // unconditionally, which is how a failed verify still let
                    // you in.
                    if viewModel.error == nil { onLoginSuccess() }
                }
            } label: {
                Text(viewModel.isLoading ? S.Login.verifying : S.Login.verifyCode)
            }
            .frame(maxWidth: .infinity)
            .disabled(viewModel.isLoading || viewModel.otp.isEmpty)

            HStack {
                SanvyaButton(ghost: true) {
                    Task { await viewModel.sendOtp() }
                } label: {
                    Text(S.Login.resend)
                }
                .disabled(viewModel.isLoading)

                Spacer()

                SanvyaButton(ghost: true) {
                    viewModel.otpSent = false
                    viewModel.otp = ""
                } label: {
                    Text(S.Login.backToSignin)
                }
            }
        }
    }
}
