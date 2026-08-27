import UIKit
import UserNotifications
import Factory
import Domain
import Data

/// APNs plumbing only.
///
/// This file used to call `requestAuthorization` in
/// `didFinishLaunchingWithOptions` — the system permission alert in the first
/// frame of the first launch, before the user had seen a single screen. On iOS
/// that is worse than impolite: the prompt can be shown exactly once, a "Don't
/// Allow" is permanent, and asking with no context is on App Review's own list
/// of rejection reasons. Permission is asked from Settings now, when the switch
/// is turned on (see `PushController`).
///
/// What launch still does is the half that asks for nothing: if permission is
/// ALREADY granted and the user has ALREADY opted in, start APNs so a rotated
/// token can be re-registered. That rule is `shouldRegisterAtLaunch` in Domain,
/// shared with Android and vector-pinned.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    @Injected(\.pushRepository) private var pushRepo
    @Injected(\.authRepository) private var authRepo
    @Injected(\.prefsRepository) private var prefsRepo

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let permission: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: permission = "granted"
            case .denied: permission = "denied"
            default: permission = "notDetermined"
            }
            // Cheap exit before touching the database at all: the overwhelming
            // majority of launches are by someone who never turned this on.
            guard permission == "granted" else { return }

            var prefEnabled = false
            if let userId = self.authRepo.currentUserId,
               let prefs = try? await self.prefsRepo.getNotificationPrefs(userId: userId) {
                prefEnabled = prefs.push_enabled == 1
            }
            guard shouldRegisterAtLaunch(permission: permission, prefEnabled: prefEnabled) else { return }
            application.registerForRemoteNotifications()
        }

        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        PushController.setDeviceToken(tokenString)

        // Re-upsert on every successful registration. It is idempotent (the
        // unique constraint is on `token`) and it is what refreshes
        // `last_seen`, which is the dispatcher's only way to tell a live
        // device from a wiped one.
        Task { @MainActor in
            guard let userId = self.authRepo.currentUserId,
                  let prefs = try? await self.prefsRepo.getNotificationPrefs(userId: userId),
                  prefs.push_enabled == 1 else { return }
            // Swallowed on purpose, and ONLY here: this is a background refresh
            // the user did not ask for, and it retries next launch. The
            // repository itself no longer swallows anything, so the path the
            // user DID ask for reports its failures.
            try? await self.pushRepo.registerToken(
                token: tokenString, platform: PushController.platform, userId: userId, lastSeenIso: nowIso()
            )
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushController.setDeviceToken(nil)
    }

    /// Show the banner even when Sanvya is foregrounded.
    ///
    /// Without this iOS suppresses it, and the "send test notification" button
    /// — whose entire job is to prove delivery works — would appear to do
    /// nothing on the one screen you are looking at when you tap it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
