import Foundation
import Supabase
import Domain

public final class SupabasePushRepository: PushRepository, @unchecked Sendable {
    private let client: SupabaseClient
    
    public init(client: SupabaseClient) {
        self.client = client
    }
    
    public func registerToken(token: String, platform: String, userId: String) async throws {
        struct PushSub: Encodable {
            let user_id: String
            let platform: String
            let token: String
        }
        
        let sub = PushSub(user_id: userId, platform: platform, token: token)
        
        try await client.database
            .schema("pocketcare")
            .from("push_subscriptions")
            .upsert(sub, onConflict: "user_id, token")
            .execute()
    }
}
