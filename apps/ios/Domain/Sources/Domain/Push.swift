import Foundation

/**
 The device's push registration, as the server sees it.

 `unregisterToken` was missing and its absence was not harmless: turning push
 off on either phone only flipped a local pref, so the token stayed in
 `push_subscriptions` and the dispatcher kept delivering to a device whose owner
 had just said no. Web's `disablePush()` deletes the row; this is the same
 contract.
 */
public protocol PushRepository: Sendable {
    /// Upsert this device's token.
    ///
    /// `lastSeenIso` mirrors what web writes on every subscribe: a token that
    /// has not been seen in months is a reinstalled or wiped device, and the
    /// dispatcher needs a way to tell that from a live one.
    func registerToken(token: String, platform: String, userId: String, lastSeenIso: String) async throws

    /// Remove this device's token. Idempotent — a token that is not there is fine.
    func unregisterToken(token: String) async throws
}
