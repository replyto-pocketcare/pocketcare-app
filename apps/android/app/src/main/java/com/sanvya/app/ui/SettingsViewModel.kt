package com.sanvya.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.diagnostics.QueuedOp
import com.sanvya.app.data.diagnostics.currentDiagnosticsEntries
import com.sanvya.app.data.diagnostics.diagnosticsReport
import com.sanvya.app.data.diagnostics.failingTableFrom
import com.sanvya.app.data.diagnostics.summarizeQueue
import com.sanvya.app.data.repository.FailedWriteItem
import com.sanvya.app.data.repository.NotificationPrefs
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.data.repository.RepairRepository
import com.sanvya.app.data.repository.RepairScanResult
import com.sanvya.app.data.repository.SettingsRepository
import com.sanvya.app.data.repository.StrandedRow
import com.sanvya.app.domain.diagnostics.LogEntry
import com.sanvya.app.domain.entitlements.isPaid
import com.sanvya.app.ui.notifications.PushController
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * Settings screen state + actions (task #47).
 *
 * Ports the functional pieces of apps/web/app/settings/page.tsx that have a
 * real mobile counterpart. Deliberately excludes (see settings.md spec for
 * the full reasoning): Security & encryption (E2E crypto, its own future
 * task), UPI Payment Handle (bundles with Splits #30 where it's actually
 * used), Categories/Labels/Import-Export (no mobile screens exist yet to
 * link to -- queued as their own tasks), Language (no i18n on mobile), and
 * Fault Injection (dev-only per the web source's own gating comment -- a
 * shipped build with this visible would be a way to break a real user's sync).
 */

data class SessionInfo(
    val email: String?,
    val isGuest: Boolean,
    val username: String,
    /** Days until a guest's data is deleted. Null once registered. */
    val daysLeft: Int?,
)

data class EntitlementUi(val tier: String, val isPaid: Boolean)

/** DELETE/upload op failed against the given error text -- used by repairStranded's UI. */
data class RepairFailure(val table: String, val id: String, val error: String)

class SettingsViewModel : ViewModel(), KoinComponent {
    private val prefsRepository: PrefsRepository by inject()
    private val authRepository: AuthRepository by inject()
    private val repairRepository: RepairRepository by inject()
    private val settingsRepository: SettingsRepository by inject()

    // ---- Notifications (existing, unchanged) ----
    private val _notifPrefs = MutableStateFlow<NotificationPrefs?>(null)
    val notifPrefs: StateFlow<NotificationPrefs?> = _notifPrefs.asStateFlow()

    // ---- Account / session ----
    private val _session = MutableStateFlow<SessionInfo?>(null)
    val session: StateFlow<SessionInfo?> = _session.asStateFlow()

    private val _usernameSaved = MutableStateFlow(false)
    val usernameSaved: StateFlow<Boolean> = _usernameSaved.asStateFlow()

    // ---- Plan & billing (display-only; no native IAP checkout yet) ----
    val entitlement: StateFlow<EntitlementUi> = prefsRepository.watchEntitlement()
        .map { row ->
            val tier = row?.tier ?: "free"
            EntitlementUi(
                tier = tier,
                isPaid = isPaid(row?.tier, row?.premiumTrialStartDate, row?.compTier, row?.compUntil, System.currentTimeMillis()),
            )
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), EntitlementUi("free", false))

    // ---- About you (profile traits) ----
    private val _profileGender = MutableStateFlow("")
    val profileGender: StateFlow<String> = _profileGender.asStateFlow()
    private val _profileCountry = MutableStateFlow("")
    val profileCountry: StateFlow<String> = _profileCountry.asStateFlow()
    private var profileExists = false
    private val _profileMsg = MutableStateFlow<String?>(null)
    val profileMsg: StateFlow<String?> = _profileMsg.asStateFlow()

    // ---- Diagnostics ----
    private val _diagnosticsEntries = MutableStateFlow<List<LogEntry>>(emptyList())
    val diagnosticsEntries: StateFlow<List<LogEntry>> = _diagnosticsEntries.asStateFlow()
    private val _queueOps = MutableStateFlow<List<QueuedOp>>(emptyList())
    val queueOps: StateFlow<List<QueuedOp>> = _queueOps.asStateFlow()
    private val _queueDepth = MutableStateFlow<Int?>(null)
    val queueDepth: StateFlow<Int?> = _queueDepth.asStateFlow()
    private val _discardingStuck = MutableStateFlow(false)
    val discardingStuck: StateFlow<Boolean> = _discardingStuck.asStateFlow()

    // ---- Problems syncing (dead-letter queue) ----
    private val _failedWrites = MutableStateFlow<List<FailedWriteItem>>(emptyList())
    val failedWrites: StateFlow<List<FailedWriteItem>> = _failedWrites.asStateFlow()
    private val _problemsBusy = MutableStateFlow<String?>(null) // item.id, or "all"
    val problemsBusy: StateFlow<String?> = _problemsBusy.asStateFlow()

    // ---- Check for unsynced data (repair) ----
    private val _repairStage = MutableStateFlow("idle") // idle|scanning|found|clean|repairing|done|error
    val repairStage: StateFlow<String> = _repairStage.asStateFlow()
    private val _strandedRows = MutableStateFlow<List<StrandedRow>>(emptyList())
    val strandedRows: StateFlow<List<StrandedRow>> = _strandedRows.asStateFlow()
    private val _repairUnchecked = MutableStateFlow<List<String>>(emptyList())
    val repairUnchecked: StateFlow<List<String>> = _repairUnchecked.asStateFlow()
    private val _repairUploaded = MutableStateFlow(0)
    val repairUploaded: StateFlow<Int> = _repairUploaded.asStateFlow()
    private val _repairFailed = MutableStateFlow<List<RepairFailure>>(emptyList())
    val repairFailed: StateFlow<List<RepairFailure>> = _repairFailed.asStateFlow()
    private val _repairError = MutableStateFlow<String?>(null)
    val repairError: StateFlow<String?> = _repairError.asStateFlow()

    // ---- Sync status (minimal -- see refreshDiagnostics doc comment) ----
    private val _syncConnected = MutableStateFlow(false)
    val syncConnected: StateFlow<Boolean> = _syncConnected.asStateFlow()
    private val _syncLastSyncedAt = MutableStateFlow<String?>(null)
    val syncLastSyncedAt: StateFlow<String?> = _syncLastSyncedAt.asStateFlow()

    // ---- Local device prefs (theme/base currency/hide-amounts) ----
    val theme: StateFlow<String> get() = Prefs.theme
    val baseCurrency: StateFlow<String> get() = Prefs.baseCurrency

    // ---- Delete account ----
    private val _deleting = MutableStateFlow(false)
    val deleting: StateFlow<Boolean> = _deleting.asStateFlow()
    private val _deleteError = MutableStateFlow<String?>(null)
    val deleteError: StateFlow<String?> = _deleteError.asStateFlow()

    init {
        loadPrefs()
        loadSession()
        loadProfile()
        refreshDiagnostics()
        refreshFailedWrites()
    }

    private fun loadPrefs() {
        val userId = authRepository.currentUserId.value ?: return
        viewModelScope.launch {
            try {
                val existingPrefs = prefsRepository.getNotificationPrefs(userId)
                if (existingPrefs != null) {
                    _notifPrefs.value = existingPrefs
                } else {
                    val newPrefs = NotificationPrefs(user_id = userId)
                    prefsRepository.updateNotificationPrefs(userId, newPrefs)
                    _notifPrefs.value = newPrefs
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    // ---- push ----

    /** "granted" | "denied" | "notDetermined", refreshed whenever the screen appears. */
    private val _pushPermission = MutableStateFlow("notDetermined")
    val pushPermission: StateFlow<String> = _pushPermission.asStateFlow()

    private val _pushBusy = MutableStateFlow(false)
    val pushBusy: StateFlow<Boolean> = _pushBusy.asStateFlow()

    /** The one-line result of the last push action — an error, or the test-sent note. */
    private val _pushMessage = MutableStateFlow<String?>(null)
    val pushMessage: StateFlow<String?> = _pushMessage.asStateFlow()

    fun refreshPushPermission(controller: PushController) {
        _pushPermission.value = controller.permission()
    }

    fun clearPushMessage() { _pushMessage.value = null }

    /**
     * Turn push on: ask the OS if needed, mint a token, register it, and only
     * THEN write the pref.
     *
     * The order is the point. Writing `push_enabled = 1` first — which is all
     * the switch used to do — leaves a user looking at an "on" switch with no
     * token registered anywhere and no alert ever arriving. The pref means "a
     * token for this device is on the server", so it must not be set until one
     * is.
     */
    fun enablePush(controller: PushController, requestPermission: ((Boolean) -> Unit) -> Unit) {
        if (_pushBusy.value) return
        _pushBusy.value = true
        _pushMessage.value = null
        requestPermission { granted ->
            _pushPermission.value = controller.permission()
            if (!granted) {
                _pushMessage.value = PUSH_DENIED
                _pushBusy.value = false
                return@requestPermission
            }
            viewModelScope.launch {
                try {
                    val userId = authRepository.currentUserId.value ?: authRepository.ensureGuest()
                    controller.ensureChannel()
                    controller.register(userId)
                    updatePref { it.copy(push_enabled = 1) }
                } catch (e: Exception) {
                    // Surfaced, not swallowed. The repository used to eat this
                    // and the switch would go green over a registration that
                    // had failed.
                    _pushMessage.value = e.message ?: PUSH_FAILED
                } finally {
                    _pushBusy.value = false
                }
            }
        }
    }

    /**
     * Turn push off: drop the token, then clear the pref.
     *
     * The OS permission is deliberately left alone — revoking it is the user's
     * business and there is no API to do it anyway. Web's `disablePush()` has
     * the same shape.
     */
    fun disablePush(controller: PushController) {
        if (_pushBusy.value) return
        _pushBusy.value = true
        _pushMessage.value = null
        viewModelScope.launch {
            try {
                controller.unregister()
            } catch (e: Exception) {
                _pushMessage.value = e.message ?: PUSH_FAILED
            }
            // The pref clears even when the delete failed: the user asked for
            // off, and leaving the switch on because the network was down would
            // be the wrong half to honour. A stale row is the dispatcher's
            // problem and `last_seen` is how it finds one.
            updatePref { it.copy(push_enabled = 0) }
            _pushBusy.value = false
        }
    }

    fun sendTestNotification(controller: PushController) {
        _pushMessage.value = if (controller.sendTest()) PUSH_TEST_SENT else PUSH_TEST_BLOCKED
    }

    fun updatePref(updater: (NotificationPrefs) -> NotificationPrefs) {
        val currentPrefs = _notifPrefs.value ?: return
        val userId = authRepository.currentUserId.value ?: return
        val newPrefs = updater(currentPrefs)
        _notifPrefs.value = newPrefs
        viewModelScope.launch {
            try {
                prefsRepository.updateNotificationPrefs(userId, newPrefs)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun loadSession() {
        viewModelScope.launch {
            try {
                val s = settingsRepository.currentSession() ?: run { _session.value = null; return@launch }
                // Bound to a local first: `createdAtMs` is a public property on a
                // :data class, and Kotlin refuses to smart-cast a public API
                // property declared in another module. Same trap as the Loans and
                // Insights fixes (PARITY_AUDIT.md trap 3).
                val createdAtMs = s.createdAtMs
                val daysLeft = if (s.isGuest && createdAtMs != null) {
                    val remainMs = createdAtMs + 3L * 86_400_000L - System.currentTimeMillis()
                    kotlin.math.max(0, kotlin.math.ceil(remainMs / 86_400_000.0).toInt())
                } else null
                _session.value = SessionInfo(email = s.email, isGuest = s.isGuest, username = s.username, daysLeft = daysLeft)
            } catch (_: Exception) {
                // Offline / transient -- keep whatever we had, don't blank it out.
            }
        }
    }

    fun saveUsername(name: String) {
        viewModelScope.launch {
            try {
                settingsRepository.updateUsername(name)
                _session.value = _session.value?.copy(username = name)
                _usernameSaved.value = true
            } catch (_: Exception) {
                // Offline -- kept locally on next successful call, matches web's swallow.
            }
        }
    }

    fun clearUsernameSaved() {
        _usernameSaved.value = false
    }

    fun signOut() {
        viewModelScope.launch {
            try {
                authRepository.signOut()
            } catch (_: Exception) {
                /* best effort */
            }
        }
    }

    // ---- About you (profiles.gender / profiles.country) ----

    private fun loadProfile() {
        val userId = authRepository.currentUserId.value ?: return
        viewModelScope.launch {
            try {
                val row = settingsRepository.loadProfile(userId)
                if (row != null) {
                    profileExists = true
                    _profileGender.value = row.first
                    _profileCountry.value = row.second
                }
            } catch (_: Exception) {
                /* profiles row may not exist yet -- fine, save() will insert it */
            }
        }
    }

    fun saveProfile(gender: String, country: String) {
        val userId = authRepository.currentUserId.value ?: return
        viewModelScope.launch {
            _profileMsg.value = null
            try {
                if (profileExists) {
                    settingsRepository.updateProfile(userId, gender.ifEmpty { null }, country.ifEmpty { null })
                } else {
                    settingsRepository.insertProfile(userId, gender.ifEmpty { null }, country.ifEmpty { null })
                    profileExists = true
                }
                _profileGender.value = gender
                _profileCountry.value = country
                _profileMsg.value = "Saved."
            } catch (e: Exception) {
                _profileMsg.value = e.message ?: "Couldn't save. Please try again."
            }
        }
    }

    // ---- Diagnostics ----

    /**
     * Sync fields and the queue depth both come from SettingsRepository --
     * see there for which SyncStatus fields are safe to read and why the
     * "waiting to upload" count is a direct ps_crud query instead.
     */
    fun refreshDiagnostics() {
        _diagnosticsEntries.value = currentDiagnosticsEntries()
        try {
            val status = settingsRepository.syncSnapshot()
            _syncConnected.value = status.connected
            _syncLastSyncedAt.value = status.lastSyncedAt
        } catch (_: Exception) {
            /* leave last-known values */
        }
        viewModelScope.launch {
            try {
                _queueDepth.value = settingsRepository.crudQueueDepth()
            } catch (_: Exception) {
                _queueDepth.value = null
            }
            val failingTable = failingTableFrom(_diagnosticsEntries.value)
            _queueOps.value = try { settingsRepository.queueOps(failingTable) } catch (_: Exception) { emptyList() }
        }
    }

    fun diagnosticsShareText(): String {
        val errors = _diagnosticsEntries.value.count { it.level == "error" }
        val context = linkedMapOf(
            "queuedWrites" to (_queueDepth.value?.toString() ?: "unknown"),
            "queue" to summarizeQueue(_queueOps.value),
            "errorsLogged" to errors.toString(),
        )
        return diagnosticsReport(context)
    }

    fun discardStuck() {
        val stuck = _queueOps.value.filter { it.orphaned }
        if (stuck.isEmpty()) return
        viewModelScope.launch {
            _discardingStuck.value = true
            try {
                settingsRepository.discardQueueOps(stuck.map { it.id })
                refreshDiagnostics()
            } finally {
                _discardingStuck.value = false
            }
        }
    }

    // ---- Problems syncing ----

    fun refreshFailedWrites() {
        viewModelScope.launch {
            _failedWrites.value = repairRepository.listFailedWrites()
        }
    }

    fun retryFailedWrite(item: FailedWriteItem) {
        viewModelScope.launch {
            _problemsBusy.value = item.id
            repairRepository.retryFailedWrite(item)
            _problemsBusy.value = null
            refreshFailedWrites()
        }
    }

    fun retryAllFailedWrites() {
        viewModelScope.launch {
            _problemsBusy.value = "all"
            // Sequential: these often depend on each other (a parent succeeding
            // is frequently what makes the child's retry work).
            for (item in _failedWrites.value) repairRepository.retryFailedWrite(item)
            _problemsBusy.value = null
            refreshFailedWrites()
        }
    }

    fun discardFailedWrite(item: FailedWriteItem) {
        viewModelScope.launch {
            _problemsBusy.value = item.id
            repairRepository.discardFailedWrite(item)
            _problemsBusy.value = null
            refreshFailedWrites()
        }
    }

    fun exportFailedWritesJson(items: List<FailedWriteItem> = _failedWrites.value): String =
        repairRepository.exportFailedWritesJson(items)

    // ---- Check for unsynced data ----

    fun scanForStranded() {
        viewModelScope.launch {
            _repairStage.value = "scanning"
            _repairError.value = null
            try {
                val res: RepairScanResult = repairRepository.scanForStranded()
                _strandedRows.value = res.stranded
                _repairUnchecked.value = res.unchecked
                _repairStage.value = if (res.stranded.isNotEmpty()) "found" else "clean"
            } catch (e: Exception) {
                _repairError.value = e.message ?: "Couldn't check right now."
                _repairStage.value = "error"
            }
        }
    }

    fun repairStrandedNow() {
        viewModelScope.launch {
            _repairStage.value = "repairing"
            try {
                val (uploaded, failed) = repairRepository.repairStranded(_strandedRows.value)
                _repairUploaded.value = uploaded
                _repairFailed.value = failed.map { RepairFailure(it.first, it.second, it.third) }
                _repairStage.value = "done"
            } catch (e: Exception) {
                _repairError.value = e.message ?: "Couldn't repair right now."
                _repairStage.value = "error"
            }
        }
    }

    fun resetRepair() {
        _repairStage.value = "idle"
        _strandedRows.value = emptyList()
        _repairUnchecked.value = emptyList()
        _repairFailed.value = emptyList()
        _repairUploaded.value = 0
        _repairError.value = null
    }

    fun exportStrandedJson(): String = repairRepository.exportStrandedJson(_strandedRows.value)

    // ---- Local device prefs ----

    fun setTheme(value: String) = Prefs.setTheme(value)
    fun setBaseCurrency(value: String) = Prefs.setBaseCurrency(value)

    // ---- Delete account ----

    /**
     * Deletes the account server-side, wipes the local database, then signs
     * out. The RPC and schema mechanics live in SettingsRepository.
     */
    fun deleteAccount() {
        viewModelScope.launch {
            _deleting.value = true
            _deleteError.value = null
            try {
                settingsRepository.deleteAccountOnServer()
                try {
                    settingsRepository.clearLocalDatabase()
                } catch (_: Exception) {
                    /* best-effort local clear; sign-out proceeds regardless */
                }
                authRepository.signOut()
            } catch (e: Exception) {
                _deleteError.value = e.message ?: "Something went wrong. Please try again."
            } finally {
                _deleting.value = false
            }
        }
    }

    private companion object {
        // English on all three platforms, because these are English literals in
        // web's NotificationPanel.tsx too -- see PARITY_AUDIT's i18n row.
        const val PUSH_DENIED =
            "Notifications are blocked in your system settings \u2014 allow them for Sanvya and try again."
        const val PUSH_FAILED = "Couldn't set up notifications on this device."
        const val PUSH_TEST_SENT = "Sent \u2014 check your device notifications."
        const val PUSH_TEST_BLOCKED = "Allow notifications for Sanvya first."
    }
}
