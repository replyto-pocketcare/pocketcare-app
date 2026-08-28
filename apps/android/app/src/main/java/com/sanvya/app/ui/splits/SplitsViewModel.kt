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
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.i18n.S
import com.sanvya.app.data.repository.PendingSettlement
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.Account
import com.sanvya.app.ui.FormOptions
import kotlinx.coroutines.flow.catch
import com.sanvya.app.domain.splits.PersonNet
import com.sanvya.app.domain.splits.friendNets
import com.sanvya.app.domain.splits.everyoneYouShareWith
import com.sanvya.app.data.repository.PersonLine
import com.sanvya.app.domain.splitsinsights.FriendInsight

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
    private val ledgerRepository: LedgerRepository by inject()

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

    // ---- friend insights ----

    /**
     * Behavioural patterns across the groups you share -- who covers the most,
     * who always ends up owing, who settles fastest.
     *
     * `friendInsights()` has been on both repositories since P2.5 with zero
     * callers: the ranking was computed, thresholded, returned and thrown away.
     * `pickFriendInsights` in Domain does the actual choosing under its own
     * vectors, including the evidence thresholds that stop it asserting a
     * pattern from one dinner.
     */
    private val _insights = MutableStateFlow<List<FriendInsight>>(emptyList())
    val insights: StateFlow<List<FriendInsight>> = _insights

    // ---- person detail ----

    /**
     * The itemised ledger behind one person's balance, across every group.
     *
     * `personLedger()` has been on both repositories since P2.5 with zero
     * callers, so the Friends screen could tell you THAT you owed someone and
     * not one line of WHY -- unless the whole balance happened to sit in a
     * single group you could open.
     */
    private val _personLines = MutableStateFlow<List<PersonLine>>(emptyList())
    val personLines: StateFlow<List<PersonLine>> = _personLines

    private val _personLinesFor = MutableStateFlow<String?>(null)
    val personLinesFor: StateFlow<String?> = _personLinesFor

    fun loadPersonLedger(otherUserId: String) {
        val uid = userId ?: return
        if (_personLinesFor.value == otherUserId) return
        _personLinesFor.value = otherUserId
        _personLines.value = emptyList()
        viewModelScope.launch {
            try {
                _personLines.value = splitsRepository.personLedger(uid, otherUserId).first
            } catch (e: Exception) {
                _error.value = e.message
            }
        }
    }

    fun clearPersonLedger() {
        _personLinesFor.value = null
        _personLines.value = emptyList()
    }

    // ---- pending settlements ----

    /**
     * Payments someone says they made to you, waiting on your confirmation.
     *
     * Web renders this above the Friends list on /friends. It is the payee's
     * half of settle-up and it had no native UI at all -- both repositories
     * have had `confirmSettlement` and `disputeSettlement` since P2.5 with
     * zero callers, so a UPI settlement raised on a phone stayed pending until
     * somebody opened the browser.
     */
    private val _pending = MutableStateFlow<List<PendingSettlement>>(emptyList())
    val pending: StateFlow<List<PendingSettlement>> = _pending

    /** Real accounts the deposit could land in -- web's own picker query. */
    private val _accounts = MutableStateFlow<List<Account>>(emptyList())
    val accounts: StateFlow<List<Account>> = _accounts

    /** The settlement currently being confirmed or disputed, by id. */
    private val _busySettlementId = MutableStateFlow<String?>(null)
    val busySettlementId: StateFlow<String?> = _busySettlementId

    fun nameOfUser(userId: String, res: android.content.res.Resources): String =
        namesById[userId] ?: S.Payments.someone(res)

    /**
     * "Yes, it arrived" / "Didn't arrive".
     *
     * Note what dispute does NOT do: it does not unwind the payer's ledger
     * entry. The ledger is append-only and if their money really left, that is
     * still true. What changes is that the settlement stops counting toward
     * the balance between you -- web's own comment, and the reason the two
     * actions are not symmetric.
     */
    fun confirmArrived(settlement: PendingSettlement, accountId: String?) {
        act(settlement.id) { uid -> splitsRepository.confirmSettlement(uid, settlement, accountId) }
    }

    fun markDidNotArrive(settlement: PendingSettlement) {
        act(settlement.id) { uid -> splitsRepository.disputeSettlement(uid, settlement.id) }
    }

    private fun act(settlementId: String, block: suspend (String) -> Unit) {
        val uid = userId ?: return
        if (_busySettlementId.value != null) return
        _busySettlementId.value = settlementId
        viewModelScope.launch {
            try {
                block(uid)
            } catch (e: Exception) {
                _error.value = e.message
            } finally {
                _busySettlementId.value = null
            }
        }
    }

    private var namesById: Map<String, String> = emptyMap()

    init {
        viewModelScope.launch {
            val uid = userId ?: return@launch
            launch {
                splitsRepository.watchPendingSettlements(uid)
                    .catch { _pending.value = emptyList() }
                    .collect { _pending.value = it }
            }
            launch {
                // Web's picker query: real, unarchived, non-investment. A
                // deposit cannot land in a demat account.
                ledgerRepository.watchAccounts(includeArchived = false)
                    .catch { _accounts.value = emptyList() }
                    .collect { list -> _accounts.value = list.filter { !FormOptions.isInvestmentAccount(it.type) } }
            }
            try {
                val conns = splitsRepository.watchConnections(uid).first()
                _connections.value = conns
                namesById = conns.associate { it.id to it.name }

                refreshOverview(uid)
                refreshInsights(uid)
                splitsRepository.watchGroups().collect {
                    refreshOverview(uid)
                    refreshInsights(uid)
                }
            } catch (e: Exception) {
                _error.value = e.message
            } finally {
                _loaded.value = true
            }
        }
    }

    private fun nameOf(id: String): String = namesById[id] ?: "Someone"

    private suspend fun refreshInsights(uid: String) {
        _insights.value = runCatching { splitsRepository.friendInsights(uid).second }.getOrDefault(emptyList())
    }

    private suspend fun refreshOverview(uid: String) {
        val ov = splitsRepository.splitOverview(uid)

        // These roll up across groups, so they report in the user's base
        // currency. The per-group rows below take each group's own currency.
        val base = baseCurrencyNow()

        _overview.value = SplitOverviewUiModel(
            netPositionFormatted = (if (ov.netPosition >= 0) "+" else "−") + formatMoney(kotlin.math.abs(ov.netPosition), base),
            netPositive = ov.netPosition >= 0,
            owedFormatted = formatMoney(ov.owed, base),
            oweFormatted = formatMoney(ov.owe, base),
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
                netBalanceFormatted = if (g.net == 0L) "Settled up" else (if (isOwed) "You are owed ${formatMoney(g.net, g.group.currency)}" else "You owe ${formatMoney(-g.net, g.group.currency)}"),
                isOwed = isOwed,
            )
        }

        // Across the WHOLE ledger, not `ov.direct` alone.
        //
        // `direct` holds only the 1:1 groups. Every balance that lives inside a
        // real group -- a trip, a flat, anything with a name -- is in
        // `GroupOverview.perUser`, which was computed, returned, and never
        // read. Somebody who owed you from a trip did not appear in Friends at
        // all, so the debt was invisible outside that one group's screen.
        //
        // The rollup itself is Domain's under 25 vectors, including the
        // first-appearance ordering web gets from spreading a JS Map.
        val nets = friendNets(
            groupPerUser = ov.groups.map { g -> g.perUser.map { PersonNet(it.userId, it.net) } },
            direct = ov.direct.map { PersonNet(it.userId, it.net) },
        )
        // Everyone you share a group with, INCLUDING the people you are square
        // with -- a Friends directory that lists only debts is a debt list.
        _friends.value = everyoneYouShareWith(
            groupMemberIds = ov.groups.map { it.memberIds },
            direct = ov.direct.map { PersonNet(it.userId, it.net) },
            nets = nets,
            names = namesById,
        ).map { person ->
            FriendEdgeUiModel(
                id = person.userId,
                name = nameOf(person.userId),
                net = person.net,
                balanceFormatted = formatMoney(kotlin.math.abs(person.net), base),
                isOwed = person.net > 0,
            )
        }
    }

    /** Everyone the caller shares a group with, settled or not -- matches
     * `everyone` on web (the "Friends" directory, a superset of the
     * owed/owe lists which drop settled people). Cheap to compute here
     * since [groups] and [friends] both already carry a `net` field. */
    fun everyone(): List<FriendEdgeUiModel> = _friends.value

    /** Friends aren't groups in the UI, but ARE one underneath (a hidden
     * `is_direct` group per pair, matching `getOrCreateDirectGroup()`) --
     * tapping a friend reuses GroupDetailScreen against that hidden group
     * rather than a second, near-duplicate "person ledger" screen. */
    fun openOrCreateDirectGroup(otherUserId: String, currency: String, onDone: (String?) -> Unit) {
        val uid = userId ?: return onDone(null)
        viewModelScope.launch {
            try {
                val id = splitsRepository.getOrCreateDirectGroup(uid, otherUserId, nameOf(otherUserId), currency)
                onDone(id)
            } catch (e: Exception) {
                _error.value = e.message
                onDone(null)
            }
        }
    }

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

