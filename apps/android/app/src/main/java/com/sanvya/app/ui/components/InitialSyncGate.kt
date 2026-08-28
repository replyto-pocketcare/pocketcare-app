package com.sanvya.app.ui.components

import com.sanvya.app.data.repository.SettingsRepository
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * The native `useInitialSyncPending()` (apps/web/src/sync.ts).
 *
 * True while the FIRST sync from the server has not finished — i.e. the local
 * database may still be empty because the data is on its way. Lists use it to
 * show skeletons instead of a "you have nothing yet" empty state, which during
 * a first sync is not merely unhelpful but wrong: it tells a returning user
 * their money is gone.
 *
 * Shared rather than repeated because more than one list needs it, and because
 * the two screens that need it must agree — Transactions and Accounts showing
 * different answers to "has the data arrived?" is worse than either answer.
 *
 * TWO deliberate differences from web, both recorded here rather than in the
 * call sites:
 *
 *  * It POLLS. `hasSynced` has no change stream on either SDK, so this reads
 *    the same status object the diagnostics panel does — exactly as
 *    `WalkthroughGateViewModel` already does, and for the same reason. It
 *    settles once and then never changes for the life of the process, so the
 *    loop ends for good the moment it flips. This is not a background poller.
 *  * There is no `online &&`, but there IS a deadline. Web can cheaply ask
 *    `navigator.onLine`; the equivalent here lives in the shell's connectivity
 *    callback, which is not reachable from a repository. Without a substitute
 *    the gate would wait FOREVER on a brand-new install with no network -- the
 *    user would get a shimmering placeholder and no way to read what it means.
 *    So the wait is bounded: past `SYNC_WAIT_TIMEOUT_MS` we give up and show
 *    the empty state, which by then is the honest answer. A returning user
 *    never reaches the deadline -- PowerSync persists `hasSynced` with the
 *    local database, so they answer "already synced" offline on the first
 *    frame.
 */
fun initialSyncPending(settingsRepository: SettingsRepository): Flow<Boolean> = flow {
    if (hasSyncedOrFalse(settingsRepository)) {
        emit(false)
        return@flow
    }
    emit(true)
    var waited = 0L
    while (!hasSyncedOrFalse(settingsRepository) && waited < SYNC_WAIT_TIMEOUT_MS) {
        delay(SYNC_POLL_MS)
        waited += SYNC_POLL_MS
    }
    emit(false)
}

/**
 * An unreadable status is "not yet", never "done".
 *
 * Erring the other way would flash the empty state — the exact failure this
 * gate exists to remove.
 */
private fun hasSyncedOrFalse(settingsRepository: SettingsRepository): Boolean =
    runCatching { settingsRepository.hasSynced() }.getOrDefault(false)

/** `WalkthroughGateViewModel`'s own interval, so the two gates settle together. */
private const val SYNC_POLL_MS = 400L

/**
 * How long a placeholder is allowed to stand in for an answer.
 *
 * Ten seconds is well past a healthy first sync and well short of the point
 * where a person decides the app is broken. Past it the empty state is not a
 * guess any more -- it is what we actually know.
 */
private const val SYNC_WAIT_TIMEOUT_MS = 10_000L
