package com.sanvya.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.NotificationPrefs
import com.sanvya.app.data.repository.PrefsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

class SettingsViewModel : ViewModel(), KoinComponent {
    private val prefsRepository: PrefsRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _notifPrefs = MutableStateFlow<NotificationPrefs?>(null)
    val notifPrefs: StateFlow<NotificationPrefs?> = _notifPrefs.asStateFlow()

    init {
        loadPrefs()
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
}
