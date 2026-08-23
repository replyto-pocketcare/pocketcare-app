package com.sanvya.app.ui.shell

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.NotificationsRepository
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.data.repository.RepairRepository
import com.sanvya.app.data.repository.SettingsRepository
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
                    _canScan.value = isPaid(
                        row?.tier,
                        row?.premiumTrialStartDate,
                        row?.compTier,
                        row?.compUntil,
                        System.currentTimeMillis(),
                    )
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
}
