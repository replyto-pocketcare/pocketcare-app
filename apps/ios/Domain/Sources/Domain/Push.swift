import Foundation

public protocol PushRepository: Sendable {
    func registerToken(token: String, platform: String, userId: String) async throws
}
