import SwiftUI
import Factory

/// The pre-auth slide deck — ported from `apps/web/app/onboarding/page.tsx`.
///
/// Web's auth gate replaces to `/onboarding` when there is no session, and this
/// deck is what a first-time visitor meets before the login form. **Neither
/// native app had it**: both gated straight to the login screen, so the seven
/// slides explaining what Sanvya is were reachable on the web client only.
///
/// Seven cards, each a glyph on a gradient plus a title and a paragraph, swiped
/// or stepped through; the last card offers the three ways in. `OnboardingSeen`
/// is written on the way out — from any of them — so it is a first-run screen
/// and not a wall.
///
/// **`InstallGuide` is deliberately absent.** Web's deck ends with an "Install
/// the app" chip that opens PWA instructions. On a phone the app IS installed.
/// Recorded in docs/mobile/ABSENT-BY-DECISION.md.
struct OnboardingDeckView: View {
    /// Called once the deck is done with, whichever exit was taken. The gate
    /// above shows the login screen next; a guest tap will already have created
    /// the session, so the gate moves on by itself.
    let onDone: () -> Void

    @State private var viewModel = Container.shared.authViewModel()
    @State private var index = 0
    @State private var dragOffset: CGFloat = 0

    private var slides: [OnboardingSlide] { OnboardingSlides.slides }
    private var isLast: Bool { index == slides.count - 1 }

    var body: some View {
        ZStack {
            // `radial-gradient(120% 90% at 50% 0%, accent-ghost, bg 60%)` — the
            // accent bloom behind the deck, from the top edge.
            Color.bg.ignoresSafeArea()
            RadialGradient(
                colors: [Color.accentGhost, Color.bg.opacity(0)],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    SanvyaH1(S.Translation.appName, compact: false)
                        .foregroundStyle(Color.accent)

                    card
                    dots
                    actions

                    if let error = viewModel.error {
                        SanvyaCard(padding: 12) {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.negative)
                        }
                    }

                    Text(S.Onboarding.footer)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.text2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 520)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - The card

    private var card: some View {
        VStack(spacing: 18) {
            graphic
            Text(OnboardingSlides.titles[index])
                .font(.system(size: 27, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.text)
            Text(OnboardingSlides.bodies[index])
                .font(.system(size: 16))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.text2)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        // A key on the index so SwiftUI treats each slide as its own view and
        // the transition actually runs — without it the text cross-fades in
        // place and the deck reads as one card whose words change.
        .id(index)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .offset(x: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation.width * 0.18 }
                .onEnded { value in
                    dragOffset = 0
                    // Web's own thresholds: 60pt either way, and it does not
                    // wrap around at either end.
                    if value.translation.width < -60, index < slides.count - 1 {
                        withAnimation(.easeOut(duration: 0.32)) { index += 1 }
                    } else if value.translation.width > 60, index > 0 {
                        withAnimation(.easeOut(duration: 0.32)) { index -= 1 }
                    }
                }
        )
        .animation(.easeOut(duration: 0.18), value: dragOffset)
    }

    private var graphic: some View {
        let slide = slides[index]
        return RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [slide.gradientStart, slide.gradientEnd],
                    // 150deg in CSS, measured clockwise from "up"; SwiftUI's
                    // unit points make that roughly top-trailing to
                    // bottom-leading.
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            )
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxWidth: 300)
            .overlay(
                Text(slide.glyph)
                    .font(.system(size: 68))
                    .foregroundStyle(Color(.sRGB, red: 0.965, green: 0.941, blue: 0.906))
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 4)
            )
            .shadow(color: slide.gradientStart.opacity(0.73), radius: 22, y: 20)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { k in
                Capsule()
                    .fill(k == index ? Color.accent : Color.border)
                    .frame(width: k == index ? 22 : 8, height: 8)
            }
        }
        .animation(.easeOut(duration: 0.2), value: index)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if !isLast {
                SanvyaButton { withAnimation(.easeOut(duration: 0.32)) { index += 1 } } label: {
                    Text(S.Onboarding.next).frame(maxWidth: .infinity)
                }
                SanvyaButton(ghost: true) {
                    withAnimation(.easeOut(duration: 0.32)) { index = slides.count - 1 }
                } label: {
                    Text(S.Onboarding.skip).frame(maxWidth: .infinity)
                }
            } else {
                // Both of web's first two buttons land on the same screen here.
                // Web splits them with `?mode=signin`, but this app's login is
                // a single OTP-first form with no register/sign-in modes at
                // all -- a pre-existing divergence, recorded in PARITY_AUDIT
                // rather than papered over with two buttons that do the same
                // thing invisibly.
                SanvyaButton(action: onDone) {
                    Text(S.Onboarding.createAccount).frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isLoading)
                SanvyaButton(ghost: true, action: onDone) {
                    Text(S.Onboarding.signIn).frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isLoading)
                SanvyaButton(ghost: true) {
                    Task {
                        await viewModel.continueAsGuest()
                        // Only on success: a failed anonymous sign-in leaves
                        // the deck up with its error, exactly as web does,
                        // rather than dropping the user on a login screen with
                        // no explanation of what just went wrong.
                        if viewModel.error == nil { onDone() }
                    }
                } label: {
                    Text(viewModel.isLoading ? S.Onboarding.starting : S.Onboarding.tryGuest)
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isLoading)
            }
        }
    }
}

/// Web's `localStorage.setItem("onboardingSeen", "1")`, under the same key.
///
/// Deliberately not a `@Published` anything: it is read once by the auth gate
/// at launch and written once on the way out, and making it observable would
/// re-render the whole app for a value that changes exactly once in a
/// lifetime.
enum OnboardingSeen {
    private static let key = "onboardingSeen"

    static func read(_ defaults: UserDefaults = .standard) -> Bool {
        // "1", matching web's stored value rather than a native bool, so the
        // three clients agree on what the key means.
        defaults.string(forKey: key) == "1"
    }

    static func mark(_ defaults: UserDefaults = .standard) {
        defaults.set("1", forKey: key)
    }
}
