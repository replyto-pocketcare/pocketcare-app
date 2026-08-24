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

 Scope, matching web's `/login` and Android's `LoginScreen`:
 - **Email + password**, **email OTP**, **Google**, and **guest**.
 - **Google** links to an existing guest rather than replacing them, which is
   what web does and what keeps a guest's data theirs — see
   `authContinueWithGoogle` in Data/Auth.swift for why that forces a browser
   flow rather than the Sign in with Google SDK's ID token.
 - Password sign-in was missing on iOS and present on Android and web, so
   anyone who registered with a password could not sign in here at all.
 */
struct LoginView: View {
    // No `onLoginSuccess` / `onContinueAsGuest` closures.
    //
    // They used to exist and do nothing: SanvyaApp passed an empty body with
    // the comment "AuthState will update automatically" — which is true, the
    // gate switches on `authState` — and a guest closure that called
    // `continueAsGuest()` a second time, after this view had already called it.
    // (Harmless only because `authEnsureUser` returns early when a session
    // exists.) A parameter every caller passes and nobody acts on is the same
    // facade this screen was rebuilt to remove, one layer up.
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

                // Google. Not gated on `mode`: from the user's side it is
                // neither a sign-in nor a sign-up, which is why web shows it in
                // both modes and only swaps the label.
                SanvyaButton(ghost: true) {
                    Task { await viewModel.continueWithGoogle() }
                } label: {
                    HStack(spacing: 10) {
                        GoogleMark()
                        Text(S.Login.continueGoogle)
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isLoading)

                SanvyaButton(ghost: true) {
                    Task { await viewModel.continueAsGuest() }
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

            if viewModel.mode == .password {
                SanvyaInput(
                    text: $viewModel.password,
                    placeholder: S.Login.passwordPlaceholder,
                    isSecure: true
                )
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            SanvyaButton {
                Task {
                    if viewModel.mode == .password {
                        await viewModel.signInWithPassword()
                    } else {
                        await viewModel.sendOtp()
                    }
                }
            } label: {
                Text(buttonLabel)
            }
            .frame(maxWidth: .infinity)
            // Guarding on the fields being non-empty rather than validating the
            // address here: Supabase is the authority on whether an address is
            // real, and a second opinion in the UI would only ever be wrong.
            .disabled(
                viewModel.isLoading || viewModel.email.isEmpty ||
                (viewModel.mode == .password && viewModel.password.isEmpty)
            )

            SanvyaButton(ghost: true) {
                viewModel.mode = viewModel.mode == .password ? .otp : .password
            } label: {
                Text(viewModel.mode == .password ? S.Login.`continue` : S.Login.signInBtn)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var buttonLabel: String {
        if viewModel.isLoading { return S.Login.saving }
        return viewModel.mode == .password ? S.Login.signInBtn : S.Login.`continue`
    }

    private var codeStep: some View {
        VStack(spacing: 12) {
            SanvyaInput(text: $viewModel.otp, placeholder: S.Login.codePlaceholder)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)

            SanvyaButton {
                // The gate in SanvyaApp watches `authState`, so a successful
                // verify moves the app on by itself. The old screen called an
                // `onLoginSuccess()` closure unconditionally here, which is how
                // a FAILED verify still let you in.
                Task { await viewModel.verifyOtpAndSignIn() }
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


/// Google "G" mark, official four-colour logo.
///
/// Path data is the same as web's `GoogleIcon()` (apps/web/app/login/page.tsx)
/// and Android's `res/drawable/ic_google.xml`, on the same 18x18 viewport, so
/// the glyph is identical on all three platforms rather than merely similar.
///
/// Deliberately not tinted: Google's branding rules for "Sign in with Google"
/// require the mark in its own colours, and a recoloured G is a common review
/// rejection.
private struct GoogleMark: View {
    var body: some View {
        ZStack {
            ForEach(GoogleSlice.Part.allCases, id: \.self) { part in
                GoogleSlice(part: part).fill(part.color)
            }
        }
        .frame(width: 18, height: 18)
        // Decorative: the label beside it already says "Continue with Google",
        // so announcing the mark as well would read the same thing twice.
        .accessibilityHidden(true)
    }
}

/// One coloured wedge of the Google mark.
///
/// A `Shape` rather than a `Canvas` drawing: `Shape` is handed the final rect,
/// so the 18-unit design coordinates scale to whatever size the button gives
/// it, and the whole thing stays a value type with no stored closures — which
/// is what keeps it Sendable under Swift 6 strict concurrency.
private struct GoogleSlice: Shape {
    enum Part: CaseIterable, Hashable {
        case blue, green, yellow, red

        var color: Color {
            switch self {
            case .blue:   Color(red: 0.259, green: 0.522, blue: 0.957)  // #4285F4
            case .green:  Color(red: 0.204, green: 0.659, blue: 0.325)  // #34A853
            case .yellow: Color(red: 0.984, green: 0.737, blue: 0.020)  // #FBBC05
            case .red:    Color(red: 0.918, green: 0.263, blue: 0.208)  // #EA4335
            }
        }
    }

    let part: Part

    /// The viewBox the path coordinates below are expressed in — the same one
    /// the SVG and the Android vector use.
    private static let designSize: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch part {
        case .blue:
            path.move(to: CGPoint(x: 17.64, y: 9.2))
            path.addCurve(to: CGPoint(x: 17.48, y: 7.36),
                          control1: CGPoint(x: 17.64, y: 8.56), control2: CGPoint(x: 17.58, y: 7.95))
            path.addLine(to: CGPoint(x: 9, y: 7.36))
            path.addLine(to: CGPoint(x: 9, y: 10.84))
            path.addLine(to: CGPoint(x: 13.84, y: 10.84))
            path.addCurve(to: CGPoint(x: 12.04, y: 13.56),
                          control1: CGPoint(x: 13.64, y: 11.92), control2: CGPoint(x: 13.03, y: 12.84))
            path.addLine(to: CGPoint(x: 12.04, y: 15.82))
            path.addLine(to: CGPoint(x: 14.96, y: 15.82))
            path.addCurve(to: CGPoint(x: 17.64, y: 9.2),
                          control1: CGPoint(x: 16.66, y: 14.25), control2: CGPoint(x: 17.64, y: 11.94))
        case .green:
            path.move(to: CGPoint(x: 9, y: 18))
            path.addCurve(to: CGPoint(x: 14.96, y: 15.82),
                          control1: CGPoint(x: 11.43, y: 18), control2: CGPoint(x: 13.47, y: 17.2))
            path.addLine(to: CGPoint(x: 12.04, y: 13.56))
            path.addCurve(to: CGPoint(x: 9, y: 14.42),
                          control1: CGPoint(x: 11.24, y: 14.1), control2: CGPoint(x: 10.2, y: 14.42))
            path.addCurve(to: CGPoint(x: 3.97, y: 10.72),
                          control1: CGPoint(x: 6.66, y: 14.42), control2: CGPoint(x: 4.68, y: 12.84))
            path.addLine(to: CGPoint(x: 0.96, y: 10.72))
            path.addLine(to: CGPoint(x: 0.96, y: 13.05))
            path.addCurve(to: CGPoint(x: 9, y: 18),
                          control1: CGPoint(x: 2.44, y: 16.02), control2: CGPoint(x: 5.48, y: 18))
        case .yellow:
            path.move(to: CGPoint(x: 3.97, y: 10.72))
            path.addCurve(to: CGPoint(x: 3.97, y: 7.28),
                          control1: CGPoint(x: 3.55, y: 9.64), control2: CGPoint(x: 3.55, y: 8.36))
            path.addLine(to: CGPoint(x: 3.97, y: 4.95))
            path.addLine(to: CGPoint(x: 0.96, y: 4.95))
            path.addCurve(to: CGPoint(x: 0.96, y: 13.05),
                          control1: CGPoint(x: -0.32, y: 7.5), control2: CGPoint(x: -0.32, y: 10.5))
            path.addLine(to: CGPoint(x: 3.97, y: 10.72))
        case .red:
            path.move(to: CGPoint(x: 9, y: 3.58))
            path.addCurve(to: CGPoint(x: 12.44, y: 4.93),
                          control1: CGPoint(x: 10.32, y: 3.58), control2: CGPoint(x: 11.5, y: 4.03))
            path.addLine(to: CGPoint(x: 15.02, y: 2.35))
            path.addCurve(to: CGPoint(x: 9, y: 0),
                          control1: CGPoint(x: 13.46, y: 0.9), control2: CGPoint(x: 11.43, y: 0))
            path.addCurve(to: CGPoint(x: 0.96, y: 4.95),
                          control1: CGPoint(x: 5.48, y: 0), control2: CGPoint(x: 2.44, y: 1.98))
            path.addLine(to: CGPoint(x: 3.97, y: 7.28))
            path.addCurve(to: CGPoint(x: 9, y: 3.58),
                          control1: CGPoint(x: 4.68, y: 5.16), control2: CGPoint(x: 6.66, y: 3.58))
        }
        path.closeSubpath()

        let scale = min(rect.width, rect.height) / Self.designSize
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}
