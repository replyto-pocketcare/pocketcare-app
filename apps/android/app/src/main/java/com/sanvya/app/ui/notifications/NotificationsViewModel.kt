package com.sanvya.app.ui.notifications

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.NotificationRow
import com.sanvya.app.data.repository.NotificationsRepository
import com.sanvya.app.data.repository.nowIso
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * The notification inbox -- ported from apps/web/app/notifications/page.tsx.
 *
 * The repository and the bell badge already existed on both platforms; this is
 * the screen the badge was pointing at, which was a placeholder.
 *
 * Mirrors apps/ios/App/ViewModels/NotificationsViewModel.swift.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NotificationsViewModel : ViewModel(), KoinComponent {
    private val notificationsRepository: NotificationsRepository by inject()
    private val authRepository: AuthRepository by inject()

    // flatMapLatest on the user id rather than a one-shot read: the queries are
    // scoped by user_id, and a guest who signs in mid-session must not keep
    // watching the id they had before.
    private val userId: StateFlow<String?> = authRepository.currentUserId

    val items: StateFlow<List<NotificationRow>> = userId.filterNotNull()
        .flatMapLatest { id -> notificationsRepository.watchInbox(id) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val unread: StateFlow<Int> = userId.filterNotNull()
        .flatMapLatest { id -> notificationsRepository.watchUnreadCount(id) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), 0)

    fun markRead(id: String) {
        viewModelScope.launch {
            val user = userId.filterNotNull().first()
            runCatching { notificationsRepository.markRead(user, id, nowIso()) }
        }
    }

    fun markAllRead() {
        viewModelScope.launch {
            val user = userId.filterNotNull().first()
            runCatching { notificationsRepository.markAllRead(user, nowIso()) }
        }
    }

    fun dismiss(id: String) {
        viewModelScope.launch { runCatching { notificationsRepository.dismiss(id) } }
    }
}
