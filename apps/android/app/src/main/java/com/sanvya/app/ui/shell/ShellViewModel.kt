package com.sanvya.app.ui.shell

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.filterNotNull
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.NotificationsRepository
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.data.repository.RepairRepository
import com.sanvya.app.data.repository.SettingsRepository
import com.sanvya.app.data.sync.SyncStatus
import com.sanvya.app.data.sync.SyncStatusRepository
import com.sanvya.app.domain.entitlements.entitlementState
import com.sanvya.app.domain.entitlements.isPaid
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * The state the app shell needs on every screen: the bell badge, the two
 * banners, and who is signed in.
 *
 * Kept apart from any screen's ViewModel because it outlives all of them — the
 * shell is composed once and the screens come and go beneath it.
 */
class ShellViewModel : ViewModel(), KoinComponent {

    private val authRepository: AuthRepository by inject()
    private val notificationsRepository: NotificationsRepository by inject()
    private val repairRepository: RepairRepository by inject()
    private val settingsRepository: SettingsRepository by inject()
    private val prefsRepository: PrefsRepository by inject()
    private val syncStatusRepository: SyncStatusRepository by inject()
    private val recurringRepository: com.sanvya.app.data.repository.RecurringRepository by inject()
    private val loanAutoPostRepository: com.sanvya.app.data.repository.LoanAutoPostRepository by inject()

    /**
     * Guards the once-per-session catch-up. Web uses a `useRef` boolean set
     * BEFORE the timer starts, so a re-render or an auth-state transition
     * cannot start a second one; this is the same latch. It is not persisted --
     * a relaunch runs the catch-up again, which is correct, because both
     * engines are idempotent by design (`next_due` for recurring, the ledger
     * description lookup for EMIs).
     */
    private var catchUpStarted = false

    /**
     * The app's ONE sync status -- online, connected, hasSynced, lastSyncedAt.
     *
     * Handed straight through rather than copied into fields of this class: the
     * whole point of `SyncStatusRepository` is that there is a single object
     * everything reads, and a shell-shaped copy of it would be the fifth place
     * this app kept sync state.
     */
    val syncStatus: StateFlow<SyncStatus> = syncStatusRepository.status

    private val _unreadCount = MutableStateFlow(0)
    val unreadCount: StateFlow<Int> = _unreadCount.asStateFlow()

    private val _failedWriteCount = MutableStateFlow(0)
    val failedWriteCount: StateFlow<Int> = _failedWriteCount.asStateFlow()

    private val _isGuest = MutableStateFlow(false)
    val isGuest: StateFlow<Boolean> = _isGuest.asStateFlow()

    private val _guestDaysLeft = MutableStateFlow<Int?>(null)
    val guestDaysLeft: StateFlow<Int?> = _guestDaysLeft.asStateFlow()

    /**
     * Whether receipt scanning is available — Lite, Pro, or an active trial.
     * Gates the lock badge on the default add menu's second item, matching
     * web's own `canScan` in AppShell.tsx.
     */
    private val _canScan = MutableStateFlow(false)
    val canScan: StateFlow<Boolean> = _canScan.asStateFlow()

    /**
     * On the 14-day trial, and how much of it is left -- what `TrialNotice`
     * needs.
     *
     * Derived from the same `watchEntitlement()` stream `canScan` already
     * consumes, because `entitlementState()` answers both questions in one pass
     * and a second watch on one table for one boolean is how the sync status
     * ended up in four places.
     */
    private val _isTrial = MutableStateFlow(false)
    val isTrial: StateFlow<Boolean> = _isTrial.asStateFlow()

    private val _trialDaysLeft = MutableStateFlow(0)
    val trialDaysLeft: StateFlow<Int> = _trialDaysLeft.asStateFlow()

    /**
     * The signed-in email, which is what web keys the one-time trial welcome
     * dialog on (`sanvya:trial-welcome:<email>`). Null while unknown.
     */
    private val _sessionEmail = MutableStateFlow<String?>(null)
    val sessionEmail: StateFlow<String?> = _sessionEmail.asStateFlow()

    init {
        viewModelScope.launch {
            authRepository.currentUserId.collectLatest { userId ->
                if (userId == null) {
                    _unreadCount.value = 0
                    return@collectLatest
                }
                notificationsRepository.watchUnreadCount(userId)
                    .catch { _unreadCount.value = 0 }
                    .collectLatest { _unreadCount.value = it }
            }
        }

        viewModelScope.launch {
            prefsRepository.watchEntitlement()
                .catch { /* offline — keep the last known tier */ }
                .collectLatest { row ->
                    val now = System.currentTimeMillis()
                    _canScan.value = isPaid(
                        row?.tier,
                        row?.premiumTrialStartDate,
                        row?.compTier,
                        row?.compUntil,
                        now,
                    )
                    val state = entitlementState(
                        tier = row?.tier,
                        premiumTrialStartDate = row?.premiumTrialStartDate,
                        compTier = row?.compTier,
                        compUntil = row?.compUntil,
                        nowMillis = now,
                    )
                    _isTrial.value = state.isTrial
                    _trialDaysLeft.value = state.trialDaysLeft
                }
        }

        refreshSession()
        refreshFailedWrites()
    }

    fun refreshSession() {
        viewModelScope.launch {
            try {
                val session = settingsRepository.currentSession() ?: return@launch
                _isGuest.value = session.isGuest
                _sessionEmail.value = session.email
                val createdAtMs = session.createdAtMs
                _guestDaysLeft.value = if (session.isGuest && createdAtMs != null) {
                    val remainingMs = createdAtMs + 3L * 86_400_000L - System.currentTimeMillis()
                    kotlin.math.max(0, kotlin.math.ceil(remainingMs / 86_400_000.0).toInt())
                } else {
                    null
                }
            } catch (_: Exception) {
                /* offline — keep whatever we had rather than blanking it */
            }
        }
    }

    /**
     * Post anything that fell due while the app was closed.
     *
     * Mirrors AppShell.tsx's effect: **once per session, after a 2500 ms
     * delay.** The delay is not cosmetic and must not be tuned away. Loan
     * auto-post's dedupe is a lookup in the SYNCED ledger, so running it before
     * the first sync has settled means asking "has another device already
     * charged this EMI?" before that device's row has arrived — and getting
     * "no". Web's own comment says the same. It is a proxy for "sync has
     * settled" rather than a real signal, on both platforms, and replacing it
     * with a real one is a genuine improvement someone could make.
     *
     * Both engines run and a failure in one must not stop the other.
     *
     * Failures are swallowed deliberately, again matching web (`.catch(() =>
     * {})`). This is a background catch-up the user did not ask for; surfacing
     * "could not post your rent" as a toast over the dashboard on every cold
     * start would be worse than the silence. Anything it fails to post stays
     * due and is retried next launch.
     */
    fun startCatchUp(todayIso: String, baseCurrency: String) {
        if (catchUpStarted) return
        catchUpStarted = true
        viewModelScope.launch {
            kotlinx.coroutines.delay(CATCH_UP_DELAY_MS)
            // Suspend until there IS a user rather than reading `.value` and
            // giving up on null. The latch is already set by this point, so a
            // premature null would mean the catch-up silently never ran this
            // session -- and 2500 ms after launch is exactly when the session
            // may still be resolving. viewModelScope cancels this with the
            // shell, so it cannot outlive the screen.
            val userId = authRepository.currentUserId.filterNotNull().first()
            // Sequential, where web fires both without awaiting either. A
            // deliberate divergence: both engines write transactions into the
            // same local database, and nothing depends on them overlapping, so
            // serialising removes an interleaving for no cost. The separate
            // try/catch on each keeps a failure in one from stopping the other,
            // which is the part of web's shape that actually matters.
            try {
                recurringRepository.runRecurring(userId, todayIso, baseCurrency)
            } catch (_: Exception) {
            }
            try {
                loanAutoPostRepository.run(userId, todayIso)
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Polled by the shell, not observed.
     *
     * `failed_writes` is a LOCAL-ONLY table, so there is no sync event to hang a
     * watch off, and quarantining is rare enough that a periodic check costs
     * nothing. Web polls it every 30s for exactly this reason; do not "improve"
     * it into a watch that would never fire.
     */
    fun refreshFailedWrites() {
        viewModelScope.launch {
            _failedWriteCount.value = try {
                repairRepository.listFailedWrites(50).size
            } catch (_: Exception) {
                0
            }
        }
    }

    private companion object {
        /** Web's 2500 ms. See startCatchUp's note on why it exists. */
        const val CATCH_UP_DELAY_MS = 2_500L
    }
}
