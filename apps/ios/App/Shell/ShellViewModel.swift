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
    @ObservationIgnored @Injected(\.recurringRepository) private var recurringRepository
    @ObservationIgnored @Injected(\.loanAutoPostRepository) private var loanAutoPostRepository

    var unreadCount: Int = 0
    var failedWriteCount: Int = 0
    var isGuest: Bool = false
    var guestDaysLeft: Int?

    /// Whether receipt scanning is available — Lite, Pro, or an active trial.
    /// Gates the lock badge on the default add menu's second item, matching
    /// web's own `canScan` in AppShell.tsx.
    var canScan: Bool = false

    private var tasks: [Task<Void, Never>] = []

    /// Guards the once-per-session catch-up. Web uses a `useRef` boolean set
    /// BEFORE the timer starts, so a re-render or an auth-state transition
    /// cannot begin a second one; this is the same latch. It is not persisted —
    /// a relaunch runs the catch-up again, which is correct, because both
    /// engines are idempotent by design (`next_due` for recurring, the ledger
    /// description lookup for EMIs).
    private var catchUpStarted = false

    /// Web's 2500 ms. See `startCatchUp` for why it exists.
    private static let catchUpDelay: Duration = .milliseconds(2500)

    func start() {
        guard tasks.isEmpty else { return }

        tasks.append(Task { [weak self] in
            guard let self else { return }
            // ensureUser() rather than currentUserId: this runs at launch and
            // must also CREATE the guest when there is no session at all, which
            // currentUserId (now implemented, P3.2c closed) cannot do.
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
                for try await row in try self.prefsRepository.watchEntitlement() {
                    // Labelled, and `now` is a Date: the Swift signature takes
                    // a Date where Kotlin's takes epoch millis.
                    self.canScan = isPaid(
                        tier: row?.tier,
                        premiumTrialStartDate: row?.premiumTrialStartDate,
                        compTier: row?.compTier,
                        compUntil: row?.compUntil,
                        now: Date()
                    )
                }
            } catch {
                /* offline — keep the last known tier */
            }
        })

        // `isGuest`/`guestDaysLeft` were DECLARED and never assigned (found
        // 2026-08-23 while mounting the walkthrough). AppShell drives its
        // sign-in cover off `isGuest` -- `.onChange(of: viewModel.isGuest)` is
        // "the only exit" per its own comment -- so with the value frozen at
        // `false` the cover could never close itself, and the guest chips it
        // gates were dead. Web reads the same two off its session.
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await _ in self.authRepository.authState {
                await self.refreshGuest()
            }
        })

        Task { await refreshFailedWrites() }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// Post anything that fell due while the app was closed.
    ///
    /// Mirrors AppShell.tsx's effect: **once per session, after a 2500 ms
    /// delay.** The delay is not cosmetic and must not be tuned away. Loan
    /// auto-post's dedupe is a lookup in the SYNCED ledger, so running it
    /// before the first sync has settled means asking "has another device
    /// already charged this EMI?" before that device's row has arrived — and
    /// getting "no". Web's own comment says the same. It is a proxy for "sync
    /// has settled" rather than a real signal, on both platforms, and replacing
    /// it with a real one is a genuine improvement someone could make.
    ///
    /// Both engines run and a failure in one must not stop the other.
    ///
    /// Failures are swallowed deliberately, again matching web (`.catch(() =>
    /// {})`). This is a background catch-up the user did not ask for;
    /// surfacing "could not post your rent" over the dashboard on every cold
    /// start would be worse than the silence. Anything it fails to post stays
    /// due and is retried next launch.
    ///
    /// - Parameters are read by the caller in the App target: `Data` cannot see
    ///   `Prefs`, and duplicating the UserDefaults read into the data layer
    ///   would create a second source of truth for a user-visible setting.
    func startCatchUp(todayIso: String, baseCurrency: String) {
        guard !catchUpStarted else { return }
        catchUpStarted = true

        tasks.append(Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: Self.catchUpDelay)
            if Task.isCancelled { return }
            // ensureUser(), same reasoning as start(): at launch there may be
            // no session yet, and this must not silently skip the catch-up.
            guard let userId = try? await self.authRepository.ensureUser() else { return }

            // Sequential, where web fires both without awaiting either. A
            // deliberate divergence: both engines write transactions into the
            // same local database, and nothing depends on them overlapping, so
            // serialising removes an interleaving for no cost. `try?` on each
            // keeps a failure in one from stopping the other, which is the part
            // of web's shape that actually matters.
            _ = try? await self.recurringRepository.runRecurring(
                userId: userId, todayIso: todayIso, baseCurrency: baseCurrency
            )
            _ = try? await self.loanAutoPostRepository.run(userId: userId, asOfIso: todayIso)
        })
    }

    /**
     Polled by the shell, not observed.

     `failed_writes` is a LOCAL-ONLY table, so there is no sync event to hang a
     watch off, and quarantining is rare enough that a periodic check costs
     nothing. Web polls it every 30s for exactly this reason; do not "improve"
     it into a watch that would never fire.
     */
    /// Web's guest trial is three days from sign-up (`created_at + 3 days`),
    /// rounded UP to whole days remaining -- the same arithmetic
    /// SettingsViewModel already does for the settings card.
    private func refreshGuest() async {
        let guest = await authRepository.isGuest()
        isGuest = guest
        guard guest, let createdAt = authRepository.currentUserCreatedAt else {
            guestDaysLeft = nil
            return
        }
        let remaining = createdAt.addingTimeInterval(3 * 86_400).timeIntervalSinceNow
        guestDaysLeft = max(0, Int(ceil(remaining / 86_400)))
    }

    func refreshFailedWrites() async {
        failedWriteCount = (try? await repairRepository.listFailedWrites(limit: 50).count) ?? 0
    }
}
