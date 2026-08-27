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

    var body: some Scene {
        WindowGroup {
            // The auth gate. `authState` is driven by the repository's stream
            // off `client.auth.authStateChanges`, so every way in -- password,
            // OTP, Google, guest -- moves the app on by itself. LoginView used
            // to take two closures for this; one was empty and the other
            // created a guest that LoginView had already created.
            if authViewModel.authState == .signedOut {
                if onboardingSeen {
                    LoginView()
                } else {
                    // The deck's "try as guest" exit creates the session
                    // itself, so `authState` moves the app on and this branch
                    // is never reached again. The other two exits fall through
                    // to LoginView.
                    OnboardingDeckView(onDone: {
                        OnboardingSeen.mark()
                        onboardingSeen = true
                    })
                }
            } else {
                ContentView()
            }
        }
    }
}
