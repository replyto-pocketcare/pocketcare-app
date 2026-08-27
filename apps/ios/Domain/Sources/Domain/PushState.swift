import Foundation

/**
 What the push row in Settings should say, and whether the app should quietly
 re-register at launch.

 Ported from the reasoning in `apps/web/src/notifications/push.ts` and
 `NotificationPanel.tsx`. Web's version is spread across a `pushSupported()`, a
 `pushPermission()` and a chain of ternaries in the component; the three inputs
 and the five outcomes are the same, and putting them here means the two phones
 cannot disagree about what "blocked" looks like.

 The distinction that matters is **`blocked` vs `off`**. Both render an off
 switch, but only one of them can be fixed by tapping it: once the OS permission
 is denied, neither platform will show the prompt again, and the only way back
 is the system settings screen. A row that says "off" when it means "you turned
 this off at the OS level and I cannot ask again" is a switch the user will flip
 forever.

 Mirrors Android's PushState.kt.
 */
public enum PushState: String, Equatable, Sendable {
    /// No notification support at all — no OS-level channel to deliver to.
    case unsupported
    /// Permission was denied. The switch cannot fix this; system settings can.
    case blocked
    /// Available and off. Tapping asks for permission if it has not been asked.
    case off
    /// Registered and delivering.
    case on
}

/// - Parameters:
///   - supported: whether this device can show notifications at all.
///   - permission: "granted" | "denied" | "notDetermined". iOS reports all three
///     natively; Android maps a never-asked runtime permission to
///     "notDetermined" and a refused one to "denied". Below API 33 there is no
///     runtime permission, so it is always "granted".
///   - prefEnabled: the synced `notification_prefs.push_enabled` flag.
public func pushState(supported: Bool, permission: String, prefEnabled: Bool) -> PushState {
    if !supported { return .unsupported }
    if permission == "denied" { return .blocked }
    // A granted permission with the pref off is a deliberate off, not a
    // half-configured state: the user turned the switch off inside the app and
    // the OS permission simply survives that.
    if permission == "granted" && prefEnabled { return .on }
    return .off
}

/**
 Whether launch should silently re-register this device's token.

 Both platforms used to ask for notification permission in the first frame of
 the first launch, before the user had seen a single screen — the classic way to
 get a permanent "Don't Allow" and, on iOS, a review rejection. Permission is now
 asked only when the user turns the switch on.

 Launch still has a job, though: a token can be rotated by the OS at any time, so
 a user who enabled push last week and has a new token today would silently stop
 receiving anything. Re-registering is safe precisely because it asks for
 nothing — it only runs when permission is ALREADY granted and the user has
 ALREADY opted in.
 */
public func shouldRegisterAtLaunch(permission: String, prefEnabled: Bool) -> Bool {
    permission == "granted" && prefEnabled
}
