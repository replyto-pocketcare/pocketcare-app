import SwiftUI
import Factory
import Data

@main
struct SanvyaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authViewModel = Container.shared.authViewModel()
    
    var body: some Scene {
        WindowGroup {
            // The auth gate. `authState` is driven by the repository's stream
            // off `client.auth.authStateChanges`, so every way in -- password,
            // OTP, Google, guest -- moves the app on by itself. LoginView used
            // to take two closures for this; one was empty and the other
            // created a guest that LoginView had already created.
            if authViewModel.authState == .signedOut {
                LoginView()
            } else {
                ContentView()
            }
        }
    }
}
