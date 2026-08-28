import Foundation
import PowerSync

/**
 The native `useInitialSyncPending()` (apps/web/src/sync.ts).

 Returns once the FIRST sync from the server has finished — until then the local
 database may still be empty because the data is on its way. Lists await it and
 show skeletons instead of a "you have nothing yet" empty state, which during a
 first sync is not merely unhelpful but wrong: it tells a returning user their
 money is gone.

 Shared rather than repeated because more than one list needs it, and because
 the two screens that need it must agree — Transactions and Accounts showing
 different answers to "has the data arrived?" is worse than either answer.

 TWO deliberate differences from web, both recorded here rather than in the call
 sites:

 * It POLLS. `hasSynced` has no change stream on either SDK, so this reads the
   same status object the diagnostics panel does — exactly as `WalkthroughGate`
   already does, and for the same reason. It settles once and then never changes
   for the life of the process, so the loop ends for good the moment it flips.
   This is not a background poller.
 * There is no `online &&`, but there IS a deadline. Web can cheaply ask
   `navigator.onLine`; the equivalent here is the shell's `NWPathMonitor`, which
   is not reachable from a view model. Without a substitute the gate would wait
   FOREVER on a brand-new install with no network — the user would get a
   shimmering placeholder and no way to read what it means. So the wait is
   bounded: after `syncWaitTimeoutMilliseconds` we give up and let the empty
   state show, which at that point is the honest answer. A returning user never
   reaches the deadline — PowerSync persists `hasSynced` with the local
   database, so they answer "already synced" offline on the first frame.
 */
@MainActor
func awaitInitialSync(_ db: any PowerSyncDatabaseProtocol) async {
    var waited = 0
    while !Task.isCancelled && waited < syncWaitTimeoutMilliseconds {
        if db.currentStatus.hasSynced == true { return }
        try? await Task.sleep(for: .milliseconds(syncPollMilliseconds))
        waited += syncPollMilliseconds
    }
}

/// `WalkthroughGate`'s own interval, so the two gates settle together.
private let syncPollMilliseconds = 400

/// How long a placeholder is allowed to stand in for an answer.
///
/// Ten seconds is well past a healthy first sync and well short of the point
/// where a person decides the app is broken. Past it the empty state is not a
/// guess any more — it is what we actually know.
private let syncWaitTimeoutMilliseconds = 10_000
