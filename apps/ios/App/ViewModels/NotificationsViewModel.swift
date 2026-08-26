import Foundation
import Observation
import Factory
import Data
import Domain

/// The notification inbox — ported from apps/web/app/notifications/page.tsx.
///
/// The repository and the bell badge already existed; this is the screen the
/// badge was pointing at, which was a placeholder on both platforms.
///
/// Mirrors apps/android/.../ui/notifications/NotificationsViewModel.kt.
@Observable
@MainActor
final class NotificationsViewModel {
    @ObservationIgnored
    @Injected(\.notificationsRepository) private var notificationsRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    private(set) var items: [NotificationRow] = []
    private(set) var unread = 0

    private var tasks: [Task<Void, Never>] = []
    private var userId: String?

    func start() {
        guard tasks.isEmpty else { return }
        tasks.append(Task { [weak self] in
            guard let self, let userId = await self.resolveUserId() else { return }
            self.userId = userId
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.watchInbox(userId) }
                group.addTask { await self.watchUnread(userId) }
            }
        })
    }

    private func watchInbox(_ userId: String) async {
        do {
            for try await rows in try await notificationsRepository.watchInbox(userId: userId) {
                items = rows
            }
        } catch { print("Error watching notifications: \(error)") }
    }

    private func watchUnread(_ userId: String) async {
        do {
            for try await counts in try await notificationsRepository.watchUnreadCount(userId: userId) {
                unread = Int(counts.first ?? 0)
            }
        } catch { print("Error watching unread count: \(error)") }
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func markRead(_ id: String) {
        Task { [weak self] in
            guard let self else { return }
            try? await self.notificationsRepository.markRead(id: id, at: nowIso())
        }
    }

    func markAllRead() {
        Task { [weak self] in
            guard let self, let userId = self.userId else { return }
            try? await self.notificationsRepository.markAllRead(userId: userId, at: nowIso())
        }
    }

    func dismiss(_ id: String) {
        Task { [weak self] in
            try? await self?.notificationsRepository.dismiss(id: id)
        }
    }

    /// Spelled out rather than `currentUserId ?? (try? await ensureUser())`:
    /// `??`'s right-hand side is `@autoclosure` and cannot hold an `await`.
    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }
}
