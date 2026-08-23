import SwiftUI
import Factory
import Data

@main
struct SanvyaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authViewModel = Container.shared.authViewModel()
    
    var body: some Scene {
        WindowGroup {
            if authViewModel.authState == .signedOut {
                LoginView(
                    onLoginSuccess: { /* AuthState will update automatically */ },
                    onContinueAsGuest: {
                        Task {
                            await authViewModel.continueAsGuest()
                        }
                    }
                )
            } else {
                ContentView()
            }
        }
    }
}
