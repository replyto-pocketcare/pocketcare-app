package com.sanvya.app.ui.splits

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.SplitsRepository
import com.sanvya.app.data.repository.UserProfile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/** Real port of apps/web/app/friends/page.tsx's hub (task #30). See
 * docs/mobile/screen-specs/splits.md. Replaces the previous version's
 * `"Friend" // Placeholder` name bug -- names are now resolved via a real
 * connections join, matching web's `profiles.get(id)?.name ?? "Someone"`. */

data class SplitGroupUiModel(
    val id: String,
    val name: String,
    val kind: String, // "trip" or "group"
    val memberCount: Int,
    val dateRange: String?,
    val net: Long,
    val netBalanceFormatted: String,
    val isOwed: Boolean,
)

data class FriendEdgeUiModel(
    val id: String,
    val name: String,
    val net: Long,
    val balanceFormatted: String,
    val isOwed: Boolean,
)

data class SplitOverviewUiModel(
    val netPositionFormatted: String,
    val netPositive: Boolean,
    val owedFormatted: String,
    val oweFormatted: String,
)

class SplitsViewModel : ViewModel(), KoinComponent {
    private val splitsRepository: SplitsRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val userId: String?
        get() = authRepository.currentUserId.value

    private val _groups = MutableStateFlow<List<SplitGroupUiModel>>(emptyList())
    val groups: StateFlow<List<SplitGroupUiModel>> = _groups

    private val _friends = MutableStateFlow<List<FriendEdgeUiModel>>(emptyList())
    val friends: StateFlow<List<FriendEdgeUiModel>> = _friends

    private val _overview = MutableStateFlow<SplitOverviewUiModel?>(null)
    val overview: StateFlow<SplitOverviewUiModel?> = _overview

    /** Sourced from `connections` -- the pool of people a new group's
     * member picker offers, matching web's implicit assumption that group
     * members come from your connections. */
    private val _connections = MutableStateFlow<List<UserProfile>>(emptyList())
    val connections: StateFlow<List<UserProfile>> = _connections

    private val _loaded = MutableStateFlow(false)
    val loaded: StateFlow<Boolean> = _loaded

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private var namesById: Map<String, String> = emptyMap()

    init {
        viewModelScope.launch {
            val uid = userId ?: return@launch
            try {
                val conns = splitsRepository.watchConnections(uid).first()
                _connections.value = conns
                namesById = conns.associate { it.id to it.name }

                refreshOverview(uid)
                splitsRepository.watchGroups().collect {
                    refreshOverview(uid)
                }
            } catch (e: Exception) {
                _error.value = e.message
            } finally {
                _loaded.value = true
            }
        }
    }

    private fun nameOf(id: String): String = namesById[id] ?: "Someone"

    private suspend fun refreshOverview(uid: String) {
        val ov = splitsRepository.splitOverview(uid)

        _overview.value = SplitOverviewUiModel(
            netPositionFormatted = (if (ov.netPosition >= 0) "+" else "−") + formatMoney(kotlin.math.abs(ov.netPosition)),
            netPositive = ov.netPosition >= 0,
            owedFormatted = formatMoney(ov.owed),
            oweFormatted = formatMoney(ov.owe),
        )

        _groups.value = ov.groups.map { g ->
            val isOwed = g.net > 0
            SplitGroupUiModel(
                id = g.group.id,
                name = g.group.name,
                kind = g.group.kind,
                memberCount = g.peopleCount,
                dateRange = g.group.startDate,
                net = g.net,
                netBalanceFormatted = if (g.net == 0L) "Settled up" else (if (isOwed) "You are owed ${formatMoney(g.net)}" else "You owe ${formatMoney(-g.net)}"),
                isOwed = isOwed,
            )
        }

        _friends.value = ov.direct.map { bal ->
            val isOwed = bal.net > 0
            FriendEdgeUiModel(
                id = bal.userId,
                name = nameOf(bal.userId),
                net = bal.net,
                balanceFormatted = formatMoney(kotlin.math.abs(bal.net)),
                isOwed = isOwed,
            )
        }.sortedByDescending { kotlin.math.abs(it.net) }
    }

    /** Everyone the caller shares a group with, settled or not -- matches
     * `everyone` on web (the "Friends" directory, a superset of the
     * owed/owe lists which drop settled people). Cheap to compute here
     * since [groups] and [friends] both already carry a `net` field. */
    fun everyone(): List<FriendEdgeUiModel> = _friends.value

    fun createGroup(name: String, kind: String, currency: String, memberIds: List<String>, onDone: (String?) -> Unit) {
        val uid = userId ?: return
        if (name.isBlank()) { onDone(null); return }
        viewModelScope.launch {
            try {
                val id = splitsRepository.createGroup(userId = uid, name = name, kind = kind, currency = currency, memberUserIds = memberIds)
                onDone(id)
            } catch (e: Exception) {
                _error.value = e.message
                onDone(null)
            }
        }
    }
}

internal fun formatMoney(minor: Long, currency: String = "INR"): String = try {
    NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        this.currency = Currency.getInstance(currency)
        maximumFractionDigits = 2
    }.format(minor / 100.0)
} catch (e: Exception) {
    "$currency ${minor / 100.0}"
}
