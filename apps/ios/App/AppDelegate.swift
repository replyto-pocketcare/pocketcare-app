import UIKit
import Factory
import Domain

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    @Injected(\.pushRepository) private var pushRepo
    @Injected(\.authRepository) private var authRepo
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        
        // Request authorization for notifications
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
        
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        Task {
            do {
                let userId: String
                if let existing = authRepo.currentUserId {
                    userId = existing
                } else {
                    userId = try await authRepo.ensureUser()
                }
                try await pushRepo.registerToken(token: tokenString, platform: "ios", userId: userId)
                print("Successfully registered push token with Supabase")
            } catch {
                print("Failed to register push token: \(error)")
            }
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}
