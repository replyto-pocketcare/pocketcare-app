package com.sanvya.app.data.sync

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import com.powersync.PowerSyncDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.stateIn

/**
 * Everything the app knows about syncing, in one place.
 *
 * A port of `apps/web/src/sync.ts`, which is one hook returning one object.
 * Before this file the same three facts were scattered across three layers and
 * nobody could see all of them at once:
 *
 *  * `hasSynced` was a suspend function on `SettingsRepository`,
 *  * `connected` / `lastSyncedAt` came from `SettingsRepository.syncSnapshot()`,
 *  * real connectivity was trapped inside a `private` composable in the shell
 *    (`rememberIsOffline`), where no view model could reach it.
 *
 * The cost of that was measurable: FOUR independent 400 ms pollers were running
 * against the same `hasSynced` field -- one per `InitialSyncGate` caller
 * (Dashboard, Transactions, Accounts) plus `WalkthroughGateViewModel`'s own
 * copy. They could also disagree, which is worse than the waste: two screens
 * answering "has the data arrived?" differently is a bug the user sees as
 * flicker.
 *
 * There is now exactly ONE poll loop, and it lives here.
 *
 * **Why it polls at all.** The Kotlin SDK's `SyncStatus` exposes a change
 * stream, but only the three fields already used by `SettingsRepository`
 * (`connected`, `hasSynced`, `lastSyncedAt`) have been verified against a real
 * compile of this project, and an unresolved reference in this module fails the
 * whole build. So this reads the same status object the diagnostics panel does,
 * on a loop that is 400 ms until the first sync lands and then slows to
 * [SETTLED_POLL_MS] -- and only while something is actually collecting, which
 * `WhileSubscribed` guarantees.
 *
 * Mirrors apps/ios/Data/Sources/Data/SyncStatusStore.swift.
 */
class SyncStatusRepository(
    context: Context,
    private val db: PowerSyncDatabase,
) {
    /**
     * Application context, held deliberately.
     *
     * This object is a process-lifetime singleton and Koin hands it the
     * application, so there is no activity to leak; taking `applicationContext`
     * anyway makes that true even if someone later constructs it by hand.
     */
    private val appContext: Context = context.applicationContext

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /**
     * True network state -- web's `navigator.onLine`.
     *
     * A `NetworkCallback` rather than a poll: connectivity genuinely is an
     * event stream, unlike `hasSynced`, and the offline banner has to appear
     * the moment signal drops rather than up to a poll interval later.
     */
    private val online: Flow<Boolean> = callbackFlow {
        val manager = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (manager == null) {
            // No connectivity service at all (a stripped image, a unit-test
            // context). Claiming "offline" would put a permanent banner on the
            // screen for a device we simply cannot ask, so assume online.
            trySend(true)
            awaitClose { }
            return@callbackFlow
        }

        fun hasInternet(): Boolean {
            val caps = manager.getNetworkCapabilities(manager.activeNetwork)
            return caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        }

        trySend(hasInternet())

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                trySend(true)
            }

            override fun onLost(network: Network) {
                // Re-ask rather than sending `false`: losing one network while
                // another is up (Wi-Fi dropping with mobile data live) is not
                // being offline.
                trySend(hasInternet())
            }
        }
        manager.registerDefaultNetworkCallback(callback)
        awaitClose { manager.unregisterNetworkCallback(callback) }
    }.distinctUntilChanged()

    /** The three PowerSync fields, read on the one loop. */
    private data class Snapshot(
        val connected: Boolean,
        val hasSynced: Boolean,
        val lastSyncedAt: String?,
    )

    private val snapshots: Flow<Snapshot> = flow {
        while (true) {
            val snapshot = read()
            emit(snapshot)
            // Fast while the first sync is still outstanding -- that is the
            // window a skeleton is standing in for real data. Once it has
            // landed the only thing left to watch is the connection, which
            // nobody is staring at.
            delay(if (snapshot.hasSynced) SETTLED_POLL_MS else FIRST_SYNC_POLL_MS)
        }
    }.distinctUntilChanged()

    /**
     * An unreadable status is "not synced yet", never "done".
     *
     * Erring the other way flashes the "add your first account" empty state at
     * a returning user mid-sync, which reads as "your money is gone".
     */
    private fun read(): Snapshot = runCatching {
        val status = db.currentStatus
        Snapshot(
            connected = status.connected,
            hasSynced = status.hasSynced == true,
            lastSyncedAt = status.lastSyncedAt?.toString(),
        )
    }.getOrDefault(Snapshot(connected = false, hasSynced = false, lastSyncedAt = null))

    /**
     * The one observable sync status.
     *
     * `WhileSubscribed` is what keeps the promise in this file's header: with
     * nothing collecting, the poll loop is not running and the network callback
     * is not registered. The shell collects it for as long as the app is on
     * screen, which is exactly the window in which any of this is worth knowing.
     */
    val status: StateFlow<SyncStatus> = combine(online, snapshots) { isOnline, snapshot ->
        SyncStatus(
            online = isOnline,
            connected = snapshot.connected,
            hasSynced = snapshot.hasSynced,
            lastSyncedAt = snapshot.lastSyncedAt,
            // Left null deliberately, and this is the one field short of web's.
            // `SyncStatusData.anyError` is very likely present on the Kotlin SDK
            // too, but only `connected` / `hasSynced` / `lastSyncedAt` have been
            // verified against a real compile of this project, and there is no
            // local compiler: one unresolved reference here fails the whole
            // module. iOS reads it (its SDK source is vendored in the repo and
            // could be checked). Confirming `anyError` on the Kotlin SDK turns
            // this into a one-line change and lights up the strip's warn branch.
            error = null,
        )
    }.stateIn(scope, SharingStarted.WhileSubscribed(SUBSCRIPTION_GRACE_MS), SyncStatus())

    /**
     * The native `useInitialSyncPending()` -- true while the FIRST sync from the
     * server has not finished, so a screen shows skeletons rather than a "you
     * have nothing yet" empty state.
     *
     * Web's rule is exactly `online && !hasSynced`, and now that connectivity is
     * in this object the ports can finally say the same thing (the old
     * per-caller gate had no `online` to consult and substituted a deadline).
     *
     * The deadline is KEPT anyway, as a floor rather than a substitute: nothing
     * in either native app currently calls `PowerSyncDatabase.connect()`, so
     * `hasSynced` can stay false forever on a perfectly healthy connection, and
     * without a deadline every list in the app would shimmer for the life of the
     * process. That is a bootstrap bug, not a gate bug -- but the gate is where
     * it would be *seen*, and a placeholder that never resolves is the worst way
     * to see it.
     */
    val initialSyncPending: StateFlow<Boolean> =
        combine(status, deadlinePassed()) { current, expired ->
            current.online && !current.hasSynced && !expired
        }.stateIn(scope, SharingStarted.WhileSubscribed(SUBSCRIPTION_GRACE_MS), true)

    private fun deadlinePassed(): Flow<Boolean> = flow {
        emit(false)
        delay(SYNC_WAIT_TIMEOUT_MS)
        emit(true)
    }

    private companion object {
        /** The interval every one of the four old pollers used. */
        const val FIRST_SYNC_POLL_MS = 400L

        /** After the first sync only the connection is still moving. */
        const val SETTLED_POLL_MS = 2_000L

        /**
         * How long a placeholder is allowed to stand in for an answer.
         *
         * Ten seconds is well past a healthy first sync and well short of the
         * point where a person decides the app is broken.
         */
        const val SYNC_WAIT_TIMEOUT_MS = 10_000L

        /** Survives a configuration change without tearing the loop down. */
        const val SUBSCRIPTION_GRACE_MS = 5_000L
    }
}

/**
 * Online / connected / synced, as one value.
 *
 * The same four fields web's `SyncInfo` carries, minus `uploading` /
 * `downloading` (the corner write indicator already covers "something is being
 * written", and neither flag's Kotlin shape is verified).
 *
 * Mirrors `SyncStatusSnapshot` in apps/ios/Data/Sources/Data/SyncStatusStore.swift.
 */
data class SyncStatus(
    /** True network state. The source of truth for "offline". */
    val online: Boolean = true,
    /** PowerSync's own websocket state -- connected to the sync service. */
    val connected: Boolean = false,
    /** At least one full sync has completed on this device. */
    val hasSynced: Boolean = false,
    /** ISO-8601, or null when nothing has synced yet. */
    val lastSyncedAt: String? = null,
    /** A non-network sync failure, in the SDK's own words. Null when fine. */
    val error: String? = null,
)
