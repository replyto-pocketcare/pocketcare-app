package com.sanvya.app.ui.splits

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.SplitsRepository
import com.sanvya.app.data.auth.AuthRepository

import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale

data class SplitGroupUiModel(
    val id: String,
    val name: String,
    val kind: String, // "trip" or "group"
    val memberCount: Int,
    val dateRange: String?,
    val netBalanceFormatted: String,
    val isOwed: Boolean
)

data class FriendEdgeUiModel(
    val id: String,
    val name: String,
    val vpa: String?,
    val balanceFormatted: String,
    val isOwed: Boolean
)

class SplitsViewModel(
    private val splitsRepository: SplitsRepository,
    private val authRepository: AuthRepository
) : ViewModel() {

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 2
    }

    private val userId: String?
        get() = authRepository.currentUserId.value

    private val _groups = kotlinx.coroutines.flow.MutableStateFlow<List<SplitGroupUiModel>>(emptyList())
    val groups: StateFlow<List<SplitGroupUiModel>> = _groups

    private val _friends = kotlinx.coroutines.flow.MutableStateFlow<List<FriendEdgeUiModel>>(emptyList())
    val friends: StateFlow<List<FriendEdgeUiModel>> = _friends

    init {
        viewModelScope.launch {
            val uid = userId ?: return@launch
            try {
                // Initial fetch
                refreshOverview(uid)
                
                // Watch for changes to trigger refresh
                splitsRepository.watchGroups().collect {
                    refreshOverview(uid)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private suspend fun refreshOverview(uid: String) {
        val overview = splitsRepository.splitOverview(uid)
        
        _groups.value = overview.groups.map { grpOverview ->
            val isOwed = grpOverview.net > 0
            val formatted = numberFormat.format(Math.abs(grpOverview.net / 100.0))
            val netStr = if (grpOverview.net == 0L) "Settled up" else (if (isOwed) "You are owed $formatted" else "You owe $formatted")
            
            SplitGroupUiModel(
                id = grpOverview.group.id,
                name = grpOverview.group.name,
                kind = grpOverview.group.kind,
                memberCount = grpOverview.peopleCount,
                dateRange = grpOverview.group.startDate,
                netBalanceFormatted = netStr,
                isOwed = isOwed
            )
        }

        // To get friend names, we'd need to fetch connections, but for now we'll just use the ID or a placeholder.
        // Or we can use watchFriendBalances which does not give names either unless joined.
        // We will fetch connections once.
        var connections = emptyMap<String, String>()
        try {
            // we don't have a one-shot getConnections, we'd have to collect the flow
        } catch (e: Exception) {}

        _friends.value = overview.direct.map { bal ->
            val isOwed = bal.net > 0
            val formatted = numberFormat.format(Math.abs(bal.net / 100.0))
            val netStr = if (isOwed) "Owes you $formatted" else "You owe $formatted"
            
            FriendEdgeUiModel(
                id = bal.userId,
                name = "Friend", // Placeholder
                vpa = null,
                balanceFormatted = netStr,
                isOwed = isOwed
            )
        }
    }
}
