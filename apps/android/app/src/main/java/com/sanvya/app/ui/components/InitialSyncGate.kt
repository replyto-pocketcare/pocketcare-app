package com.sanvya.app.ui.components

import com.sanvya.app.data.repository.SettingsRepository
import com.sanvya.app.data.sync.SyncStatusRepository
import kotlinx.coroutines.flow.Flow
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * The native `useInitialSyncPending()` (apps/web/src/sync.ts).
 *
 * True while the FIRST sync from the server has not finished -- i.e. the local
 * database may still be empty because the data is on its way. Lists use it to
 * show skeletons instead of a "you have nothing yet" empty state, which during
 * a first sync is not merely unhelpful but wrong: it tells a returning user
 * their money is gone.
 *
 * **This file no longer polls.** It used to run its own 400 ms loop over
 * `SettingsRepository.hasSynced()`, and because the flow was cold, EVERY
 * collector got its own -- three view models, plus a fourth hand-rolled copy in
 * `WalkthroughGateViewModel`. Four loops asking one field the same question,
 * free to disagree with each other mid-flight.
 *
 * All of it now reads one app-level [SyncStatusRepository] (`:data`), which is
 * also where connectivity finally lives. That is what let the gate adopt web's
 * actual rule -- `online && !hasSynced` -- instead of the deadline it used as a
 * stand-in for connectivity. The deadline is still there, but as a floor rather
 * than a substitute; the reason is on `SyncStatusRepository.initialSyncPending`
 * and it is not a pretty one.
 */
fun initialSyncPending(): Flow<Boolean> = SyncStatusHolder.repository.initialSyncPending

/**
 * The pre-consolidation signature, kept so the call sites that pass a
 * [SettingsRepository] keep compiling.
 *
 * The argument is ignored: `hasSynced` is read by the shared status object now,
 * not per caller. It is an overload rather than an edit at each call site
 * because those files belong to other screens and this change is meant to be
 * invisible to them -- but the parameter is vestigial and the two remaining
 * callers (`TransactionsViewModel`, `AccountsViewModel`) should drop it the next
 * time either file is opened for its own reasons.
 */
@Suppress("UNUSED_PARAMETER")
fun initialSyncPending(settingsRepository: SettingsRepository): Flow<Boolean> = initialSyncPending()

/**
 * Koin lookup for a top-level function.
 *
 * The gate is called from `combine(...)` inside view-model property
 * initialisers, which have no injector of their own, and threading the
 * repository through every one of them would have meant editing four files to
 * change one. `KoinComponent` on a private object is the smallest thing that
 * resolves a singleton from module-level code.
 */
private object SyncStatusHolder : KoinComponent {
    val repository: SyncStatusRepository by inject()
}
