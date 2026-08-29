import Combine
import Factory
import Foundation
import Data
import PowerSync

/**
 The native `useInitialSyncPending()` (apps/web/src/sync.ts).

 Returns once the FIRST sync from the server has finished — until then the local
 database may still be empty because the data is on its way. Lists await it and
 show skeletons instead of a "you have nothing yet" empty state, which during a
 first sync is not merely unhelpful but wrong: it tells a returning user their
 money is gone.

 **This file no longer polls.** It used to run its own 400 ms loop over
 `db.currentStatus.hasSynced`, once per caller — three view models, plus a fourth
 hand-rolled copy in `WalkthroughGate`. Four loops asking one field the same
 question, free to disagree with each other mid-flight.

 All of it now reads one app-level ``SyncStatusStore`` (`Data`), which follows
 the SDK's own `SyncStatus.asFlow()` — a real change stream, so there is no poll
 left on this platform at all — and owns connectivity as well. That is what let
 the gate adopt web's actual rule, `online && !hasSynced`, instead of the
 deadline it used as a stand-in for connectivity. The deadline is still there,
 but as a floor rather than a substitute; the reason is on
 `SyncStatusStore.initialSyncPending` and it is not a pretty one.

 - Parameter db: ignored. Kept so the three call sites that pass their injected
   database keep compiling; `hasSynced` is read by the shared store now, not per
   caller. The parameter is vestigial and those callers should drop it the next
   time one of their files is opened for its own reasons.
 */
@MainActor
func awaitInitialSync(_ db: any PowerSyncDatabaseProtocol) async {
    _ = db
    await awaitInitialSync()
}

@MainActor
func awaitInitialSync() async {
    let store = Container.shared.syncStatusStore()
    store.start()
    // Checked before subscribing: a returning user's `hasSynced` is persisted
    // with the local database, so they are already settled on the first frame
    // and must not wait for an event that will never come.
    if !store.initialSyncPending { return }
    for await pending in store.initialSyncPendingPublisher.values {
        if !pending { return }
    }
}
