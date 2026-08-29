import Combine
import Factory
import Foundation
import Network
import PowerSync

/// Online / connected / synced, as one value.
///
/// The same four fields web's `SyncInfo` carries, minus `uploading` /
/// `downloading` (the corner write indicator already covers "something is being
/// written").
///
/// Mirrors `SyncStatus` in apps/android/data/.../sync/SyncStatusRepository.kt.
public struct SyncStatusSnapshot: Equatable, Sendable {
    /// True network state. The source of truth for "offline".
    public var online: Bool
    /// PowerSync's own connection state — connected to the sync service.
    public var connected: Bool
    /// At least one full sync has completed on this device.
    public var hasSynced: Bool
    /// Nil when nothing has synced yet.
    public var lastSyncedAt: Date?
    /// A sync failure, in the SDK's own words. Nil when fine.
    public var error: String?

    public init(
        online: Bool = true,
        connected: Bool = false,
        hasSynced: Bool = false,
        lastSyncedAt: Date? = nil,
        error: String? = nil
    ) {
        self.online = online
        self.connected = connected
        self.hasSynced = hasSynced
        self.lastSyncedAt = lastSyncedAt
        self.error = error
    }
}

/**
 Everything the app knows about syncing, in one place.

 A port of `apps/web/src/sync.ts`, which is one hook returning one object. Before
 this file the same three facts were scattered across three layers and nobody
 could see all of them at once:

  * `hasSynced` was read straight off `db.currentStatus` by whoever needed it,
  * `connected` / `lastSyncedAt` came from `SettingsViewModel`'s own read,
  * real connectivity was trapped in `ConnectivityMonitor`, a `private` property
    of `AppShell`, where no view model could reach it.

 The cost of that was measurable: FOUR independent 400 ms polls were running
 against the same `hasSynced` field — one per `awaitInitialSync` caller
 (Dashboard, Transactions, Accounts) plus `WalkthroughGate`'s own copy. They
 could also disagree, which is worse than the waste: two screens answering "has
 the data arrived?" differently is a bug the user sees as flicker.

 There is now no poll at all on this platform. `SyncStatus.asFlow()` is a real
 change stream in the Swift SDK (`PowerSync/Protocol/sync/SyncStatusData.swift`,
 vendored in this repo, so this is checked rather than assumed) and
 `NWPathMonitor` is one for connectivity.

 `ObservableObject` rather than `@Observable`: this package's macOS floor is 13
 (Domain and Data are testable with a plain `swift test`, no simulator) and the
 Observation macro needs 14 — the same reason `WriteActivity` and `Prefs` are
 written this way.

 Mirrors apps/android/data/.../sync/SyncStatusRepository.kt.
 */
@MainActor
public final class SyncStatusStore: ObservableObject {

    /// The one status. Everything that used to poll reads this instead.
    @Published public private(set) var status = SyncStatusSnapshot()

    /**
     The native `useInitialSyncPending()` — true while the FIRST sync from the
     server has not finished, so a screen shows skeletons rather than a "you have
     nothing yet" empty state.

     Web's rule is exactly `online && !hasSynced`, and now that connectivity is in
     this object the ports can finally say the same thing (the old per-caller gate
     had no `online` to consult and substituted a deadline).

     The deadline is KEPT anyway, as a floor rather than a substitute: nothing in
     either native app currently calls `PowerSyncDatabase.connect()`, so
     `hasSynced` can stay false forever on a perfectly healthy connection, and
     without a deadline every list in the app would shimmer for the life of the
     process. That is a bootstrap bug, not a gate bug — but the gate is where it
     would be *seen*, and a placeholder that never resolves is the worst way to
     see it.
     */
    @Published public private(set) var initialSyncPending = true

    /// `initialSyncPending` as a stream, for the callers that `await` it rather
    /// than render it (`awaitInitialSync`). Exposed as a method-shaped property
    /// rather than leaving callers to reach for `$initialSyncPending`, whose
    /// access level follows the wrapper rather than the declaration.
    public var initialSyncPendingPublisher: AnyPublisher<Bool, Never> {
        $initialSyncPending.eraseToAnyPublisher()
    }

    private let db: any PowerSyncDatabaseProtocol
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "app.sanvya.sync-status")
    private var tasks: [Task<Void, Never>] = []

    public init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    /// Idempotent — safe from every `.task`/`.onAppear`, which is how a shell
    /// that can be rebuilt on a size-class change has to be treated.
    public func start() {
        guard tasks.isEmpty else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.apply { $0.online = online } }
        }
        monitor.start(queue: monitorQueue)

        // Seed from whatever the SDK already knows, then follow the stream. The
        // first frame matters: a returning user's `hasSynced` is persisted with
        // the local database, so they answer "already synced" offline, before
        // any event arrives.
        ingest(db.currentStatus)
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await snapshot in self.db.currentStatus.asFlow() {
                if Task.isCancelled { return }
                self.ingest(snapshot)
            }
        })

        // The floor described on `initialSyncPending`. One timer for the app,
        // where there used to be one per caller.
        tasks.append(Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(syncWaitTimeoutMilliseconds))
            guard let self, !Task.isCancelled else { return }
            self.initialSyncPending = false
        })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        monitor.cancel()
    }

    private func ingest(_ snapshot: any SyncStatusData) {
        // `anyError` is `Any?` in the SDK, so it is stringified once here and
        // classified in Domain (`syncNotice`). The raw text never reaches the
        // UI — web says the same thing in sync.ts and for the same reason.
        let error = snapshot.anyError.map { String(describing: $0) }
        apply {
            $0.connected = snapshot.connected
            $0.hasSynced = snapshot.hasSynced == true
            $0.lastSyncedAt = snapshot.lastSyncedAt
            $0.error = error
        }
    }

    /// One mutation point, so `initialSyncPending` cannot drift out of step with
    /// the fields it is derived from.
    private func apply(_ mutate: (inout SyncStatusSnapshot) -> Void) {
        var next = status
        mutate(&next)
        if next != status { status = next }
        // Once false it stays false: this answers "is the skeleton still the
        // honest thing to show?", and going offline after the data has landed
        // must not put the placeholders back.
        if initialSyncPending, next.hasSynced || !next.online {
            initialSyncPending = false
        }
    }
}

/// Ten seconds is well past a healthy first sync and well short of the point
/// where a person decides the app is broken.
private let syncWaitTimeoutMilliseconds = 10_000

@MainActor
public extension Container {
    /// Registered here rather than in `DI/DataModule.swift` so that the whole
    /// sync status — type, store and wiring — is one file to read and one file
    /// to move.
    var syncStatusStore: Factory<SyncStatusStore> {
        self { MainActor.assumeIsolated { SyncStatusStore(db: self.powerSyncDatabase()) } }.singleton
    }
}
