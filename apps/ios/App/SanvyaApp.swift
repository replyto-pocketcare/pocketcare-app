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

    /// The chosen language. Read here so the root can be KEYED on it.
    ///
    /// Every string in the app is read eagerly through `S`, so there is nothing
    /// to re-evaluate in place when the language changes -- the tree has to be
    /// rebuilt. `.id(code)` does exactly that, and it is the same thing Android
    /// gets for free from a configuration change. State loss is the cost, and it
    /// is the right cost: this happens once, deliberately, at the user's hand.
    /// `@State`, not a computed property returning the singleton. Observation
    /// only fires for reads inside a TRACKED body evaluation, and a
    /// `WindowGroup` content closure reached through a plain computed property
    /// is not reliably one -- the picker would highlight the new language while
    /// the rest of the app stayed in the old one. `@State` is the documented
    /// pairing for App-owned `@Observable` state.
    @State private var localePrefs = LocalePrefs.shared

    var body: some Scene {
        WindowGroup {
            // The auth gate. `authState` is driven by the repository's stream
            // off `client.auth.authStateChanges`, so every way in -- password,
            // OTP, Google, guest -- moves the app on by itself. LoginView used
            // to take two closures for this; one was empty and the other
            // created a guest that LoginView had already created.
            gated
                .id(localePrefs.code ?? "")
                // Connect PowerSync to the server, and keep that connection
                // matched to whoever is signed in. Web does this in
                // `initSystem()`; until this existed the app never called
                // `connect(connector:)` at all and was a purely local database
                // -- see SyncBootstrap.swift for the full story.
                //
                // `.task` rather than `.onAppear`: it gives an async context
                // without a detached Task, and it is cancelled with the scene.
                // The bootstrap itself is a singleton and `start()` is
                // idempotent, so a scene rebuild does not reconnect.
                .task { await Container.shared.syncBootstrap().start() }
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
