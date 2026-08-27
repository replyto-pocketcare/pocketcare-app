import Foundation
import UIKit
import UserNotifications
import Factory
import Domain
import Data

/// Everything the app does with the OS notification system, in one place.
///
/// Ported from `apps/web/src/notifications/push.ts`, whose four exported
/// functions this mirrors: read the permission, subscribe, send a local test,
/// and unsubscribe. Mirrors Android's PushController.kt.
///
/// **Permission is NOT asked at launch any more.** `AppDelegate` used to call
/// `requestAuthorization` in `didFinishLaunchingWithOptions` — the system alert
/// arriving before the user had seen a single screen. On iOS that is worse than
/// impolite: the prompt can be shown exactly once, a "Don't Allow" is
/// permanent, and asking without context is on App Review's own list of
/// rejection reasons. Web asks only when the toggle is turned on; so does this
/// now.
@MainActor
public final class PushController {
    @Injected(\.pushRepository) private var pushRepository

    public init() {}

    /// The APNs token from the most recent successful registration.
    ///
    /// A `static` on purpose: `didRegisterForRemoteNotificationsWithDeviceToken`
    /// is an `AppDelegate` callback and there is no way to hand it an instance.
    /// Written there, read here.
    public private(set) nonisolated(unsafe) static var deviceToken: String?

    static func setDeviceToken(_ token: String?) { deviceToken = token }

    /// "granted" | "denied" | "notDetermined", as `pushState()` expects.
    ///
    /// `.provisional` counts as granted: it IS a working delivery channel (a
    /// quiet one), and reporting it as "not asked" would put the app back into
    /// prompting a user who is already receiving alerts.
    public func permission() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "granted"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        @unknown default: return "notDetermined"
        }
    }

    public let supported = true

    /// Ask for permission, and on a yes, start APNs registration.
    ///
    /// Returns what the user chose. The TOKEN does not arrive here — it comes
    /// back asynchronously through the app delegate — which is why `register`
    /// below waits for it rather than assuming one exists.
    public func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    /// Register this device against `userId`.
    ///
    /// Assumes permission is already granted.
    @discardableResult
    public func register(userId: String) async throws -> String {
        UIApplication.shared.registerForRemoteNotifications()
        guard let token = await waitForToken() else {
            throw PushError(message: "Couldn't get a notification token from Apple. Check the network and try again.")
        }
        try await pushRepository.registerToken(
            token: token, platform: Self.platform, userId: userId, lastSeenIso: nowIso()
        )
        return token
    }

    /// Drop this device's token. The OS permission is deliberately left alone.
    public func unregister() async throws {
        guard let token = Self.deviceToken else { return }
        try await pushRepository.unregisterToken(token: token)
    }

    /// APNs answers on its own schedule, and on a cold launch the token is not
    /// there yet. Poll briefly rather than fail instantly — a hard failure here
    /// would make "turn push on" flaky on exactly the launch where the user
    /// first tries it.
    private func waitForToken() async -> String? {
        for _ in 0..<Self.tokenWaitAttempts {
            if let token = Self.deviceToken { return token }
            try? await Task.sleep(for: .milliseconds(Self.tokenWaitStepMs))
        }
        return Self.deviceToken
    }

    /// Fire a notification locally — no server, no APNs.
    ///
    /// Web's `sendTestNotification` explains why this earns its place: it proves
    /// permission and the delivery path work on THIS device, so when it shows
    /// and real alerts do not, the gap is the server dispatch and not the phone.
    /// That is the single most useful thing a support conversation can
    /// establish.
    public func sendTest() async -> Bool {
        guard await permission() == "granted" else { return false }
        let content = UNMutableNotificationContent()
        content.title = Self.testTitle
        content.body = Self.testBody
        // A 1-second trigger, not nil. A nil trigger fires immediately, and a
        // notification that fires while its own app is foregrounded is
        // suppressed unless the delegate says otherwise -- so the user taps
        // "send test" and sees nothing at all, which is the exact opposite of
        // what the button is for.
        let request = UNNotificationRequest(
            identifier: Self.testIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    public struct PushError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    static let platform = "ios"
    private static let testIdentifier = "sanvya-test"
    private static let tokenWaitAttempts = 20
    private static let tokenWaitStepMs = 150

    // English on all three platforms, because it is English on web —
    // `sendTestNotification` writes these as literals too. See PARITY_AUDIT's
    // i18n row.
    static let testTitle = "Sanvya"
    static let testBody = "Test notification — you're all set to receive alerts."
}
