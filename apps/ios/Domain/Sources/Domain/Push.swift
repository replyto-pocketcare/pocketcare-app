import Foundation

public protocol PushRepository {
    func registerToken(token: String, platform: String, userId: String) async throws
}
