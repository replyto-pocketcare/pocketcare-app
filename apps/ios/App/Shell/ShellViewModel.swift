import Foundation
import Observation
import Factory
import Data
import Domain

/**
 The state the app shell needs on every screen: the bell badge, the two banners,
 and who is signed in.

 Kept apart from any screen's view model because it outlives all of them — the
 shell is built once and the screens come and go inside it.
 */
@MainActor
@Observable
final class ShellViewModel {
    @ObservationIgnored @Injected(\.notificationsRepository) private var notificationsRepository
    @ObservationIgnored @Injected(\.repairRepository) private var repairRepository
    @ObservationIgnored @Injected(\.prefsRepository) private var prefsRepository
    @ObservationIgnored @Injected(\.authRepository) private var authRepository

    var unreadCount: Int = 0
    var failedWriteCount: Int = 0
    var isGuest: Bool = false
    var guestDaysLeft: Int?

    /// Whether receipt scanning is available — Lite, Pro, or an active trial.
    /// Gates the lock badge on the default add menu's second item, matching
    /// web's own `canScan` in AppShell.tsx.
    var canScan: Bool = false

    private var tasks: [Task<Void, Never>] = []

    func start() {
        guard tasks.isEmpty else { return }

        tasks.append(Task { [weak self] in
            guard let self else { return }
            // `AuthRepositoryImpl.currentUserId` still always returns nil
            // (tracked as P3.2c). `ensureUser()` is the fallback every other
            // write path already uses.
            guard let userId = try? await self.authRepository.ensureUser() else { return }
            do {
                for try await rows in try await self.notificationsRepository.watchUnreadCount(userId: userId) {
                    self.unreadCount = Int(rows.first ?? 0)
                }
            } catch {
                self.unreadCount = 0
            }
        })

        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                for try await row in try await self.prefsRepository.watchEntitlement() {
                    self.canScan = isPaid(
                        row?.tier,
                        row?.premiumTrialStartDate,
                        row?.compTier,
                        row?.compUntil,
                        Int64(Date().timeIntervalSince1970 * 1000)
                    )
                }
            } catch {
                /* offline — keep the last known tier */
            }
        })

        Task { await refreshFailedWrites() }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /**
     Polled by the shell, not observed.

     `failed_writes` is a LOCAL-ONLY table, so there is no sync event to hang a
     watch off, and quarantining is rare enough that a periodic check costs
     nothing. Web polls it every 30s for exactly this reason; do not "improve"
     it into a watch that would never fire.
     */
    func refreshFailedWrites() async {
        failedWriteCount = (try? await repairRepository.listFailedWrites(limit: 50).count) ?? 0
    }
}
