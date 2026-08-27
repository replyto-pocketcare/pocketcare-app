import SwiftUI
import Factory
import Data

@main
struct SanvyaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authViewModel = Container.shared.authViewModel()

    /// Web's auth gate replaces to `/onboarding` before `/login`, and this app
    /// skipped that step entirely -- the seven-slide deck existed on the web
    /// client only. Read once here at launch, not observed: it changes exactly
    /// once in a lifetime.
    @State private var onboardingSeen = OnboardingSeen.read()

    /// An invite waiting to be accepted.
    ///
    /// Seeded from the stash at launch, on purpose: a user who tapped an invite
    /// while signed out was sent to sign in, and the whole point of stashing the
    /// token was to pick the invite back up on the other side. Web's AppShell
    /// does the same thing by redirecting to `/join` once a session exists.
    @State private var inviteToken: String? = PendingInvite.read()

    var body: some Scene {
        WindowGroup {
            // The auth gate. `authState` is driven by the repository's stream
            // off `client.auth.authStateChanges`, so every way in -- password,
            // OTP, Google, guest -- moves the app on by itself. LoginView used
            // to take two closures for this; one was empty and the other
            // created a guest that LoginView had already created.
            gated
                .onOpenURL { url in
                    guard let token = inviteTokenFromURL(url) else { return }
                    // Stash BEFORE showing anything: if there is no session the
                    // user is about to leave for the auth provider, and on a
                    // phone that trip can outlive the process.
                    if authViewModel.authState == .signedOut { PendingInvite.write(token) }
                    inviteToken = token
                }
        }
    }

    /// The auth gate, extracted so `.onOpenURL` can sit above BOTH branches —
    /// an invite link can arrive while signed out just as easily as signed in.
    @ViewBuilder
    private var gated: some View {
        if authViewModel.authState == .signedOut {
            if onboardingSeen {
                LoginView()
            } else {
                // The deck's "try as guest" exit creates the session itself, so
                // `authState` moves the app on and this branch is never reached
                // again. The other two exits fall through to LoginView.
                OnboardingDeckView(onDone: {
                    OnboardingSeen.mark()
                    onboardingSeen = true
                })
            }
        } else {
            ContentView(inviteToken: $inviteToken)
        }
    }
}
