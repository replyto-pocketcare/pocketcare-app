import Foundation
import Supabase
import Domain

/// `push_subscriptions`, written straight to Postgres rather than through
/// PowerSync — the dispatcher reads it server-side and nothing on the phone
/// ever queries it back, so syncing a copy down would be pure cost.
public final class SupabasePushRepository: PushRepository, @unchecked Sendable {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func registerToken(token: String, platform: String, userId: String, lastSeenIso: String) async throws {
        struct PushSub: Encodable {
            let user_id: String
            let platform: String
            let token: String
            let last_seen: String
        }

        let sub = PushSub(user_id: userId, platform: platform, token: token, last_seen: lastSeenIso)

        // `onConflict: "token"`, NOT "user_id, token".
        //
        // Migration 0048 adds exactly one unique constraint for native
        // devices -- `push_subscriptions_native_token_unique unique (token)`.
        // Postgres requires the ON CONFLICT target to MATCH a unique index, so
        // the composite target this used to send failed every single time with
        // "there is no unique or exclusion constraint matching the ON CONFLICT
        // specification". No device token has ever been stored by either
        // native app. Android swallowed the error into printStackTrace() and
        // iOS printed "Failed to register push token" to a console nobody
        // reads, which is why it survived.
        //
        // A token identifying one device also has no business being
        // per-user-unique: if the same phone signs in as somebody else, the
        // row must MOVE, not duplicate, or the previous account keeps
        // receiving that device's alerts.
        try await client
            .schema("pocketcare")
            .from("push_subscriptions")
            .upsert(sub, onConflict: "token")
            .execute()
    }

    public func unregisterToken(token: String) async throws {
        try await client
            .schema("pocketcare")
            .from("push_subscriptions")
            .delete()
            .eq("token", value: token)
            .execute()
    }
}
