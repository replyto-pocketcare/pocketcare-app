package com.sanvya.app.ui.splits

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.ParticipantInput
import com.sanvya.app.data.repository.PayerInput
import com.sanvya.app.data.repository.SplitExpenseInput
import com.sanvya.app.data.repository.InvitesRepository
import com.sanvya.app.data.repository.SplitGroup
import com.sanvya.app.data.repository.SplitsRepository
import com.sanvya.app.data.repository.UpiHandleError
import com.sanvya.app.data.repository.UpiRepository
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.splits.Invitee
import com.sanvya.app.domain.splits.InviteOutcome
import com.sanvya.app.domain.splits.InviteSuggestions
import com.sanvya.app.domain.splits.inviteSuggestions
import com.sanvya.app.domain.splits.inviteeKey
import com.sanvya.app.domain.splits.inviteeLabel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.Instant
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.baseCurrencyNow

/**
 * `netFormatted` alongside `net` for the same reason `ExpenseUiModel` and
 * `SettlementUiModel` carry `amountFormatted`: the group's currency is known
 * here and not in the row composable, which had been calling `formatMoney`
 * without one. The raw `net` stays for the sign and the colour.
 */
data class MemberUiModel(
    val userId: String,
    val name: String,
    val net: Long,
    val netFormatted: String,
    val isSelf: Boolean,
)
data class ExpenseUiModel(val id: String, val description: String, val amountFormatted: String, val date: String)
data class SettlementUiModel(val id: String, val fromUser: String, val toUser: String, val fromName: String, val toName: String, val amountFormatted: String, val date: String)
data class AccountOption(val id: String, val name: String)

/** Payer-side UPI settle-up state machine -- mirrors PayViaUpi.tsx's Stage
 * type exactly (idle/fetching/ready/error), since there is no success
 * callback from a UPI Intent hand-off (see PayViaUpiDialog.kt). */
sealed class UpiStage {
    object Idle : UpiStage()
    object Fetching : UpiStage()
    data class Ready(val vpa: String, val displayName: String?) : UpiStage()
    data class Error(val message: String, val code: String?) : UpiStage()
}

/** Instantiated via the parameterless `viewModel()` factory (matching
 * LoanDetailViewModel's established convention) -- the group id is passed
 * in via [select], called once from `LaunchedEffect(groupId)` in
 * GroupDetailScreen, not through the constructor. */
class GroupDetailViewModel : ViewModel(), KoinComponent {
    private val splitsRepository: SplitsRepository by inject()
    private val ledgerRepository: LedgerRepository by inject()
    private val upiRepository: UpiRepository by inject()
    private val invitesRepository: InvitesRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val userId: String? get() = authRepository.currentUserId.value
    private var groupId: String = ""
    private var watchJob: Job? = null

    private val _group = MutableStateFlow<SplitGroup?>(null)
    val group: StateFlow<SplitGroup?> = _group

    private val _members = MutableStateFlow<List<MemberUiModel>>(emptyList())
    val members: StateFlow<List<MemberUiModel>> = _members

    private val _expenses = MutableStateFlow<List<ExpenseUiModel>>(emptyList())
    val expenses: StateFlow<List<ExpenseUiModel>> = _expenses

    private val _settlements = MutableStateFlow<List<SettlementUiModel>>(emptyList())
    val settlements: StateFlow<List<SettlementUiModel>> = _settlements

    // ---- invites ----

    /** Everyone this user is connected to, as the invite box's candidates. */
    private val _connections = MutableStateFlow<List<Invitee>>(emptyList())
    val connections: StateFlow<List<Invitee>> = _connections

    private val _selected = MutableStateFlow<List<Invitee>>(emptyList())
    val selected: StateFlow<List<Invitee>> = _selected

    private val _inviteQuery = MutableStateFlow("")
    val inviteQuery: StateFlow<String> = _inviteQuery

    private val _inviting = MutableStateFlow(false)
    val inviting: StateFlow<Boolean> = _inviting

    /** The last run's counts, for the summary line. Null before the first. */
    private val _inviteOutcome = MutableStateFlow<InviteOutcome?>(null)
    val inviteOutcome: StateFlow<InviteOutcome?> = _inviteOutcome

    /** A share link, once one has been created. */
    private val _inviteLink = MutableStateFlow<String?>(null)
    val inviteLink: StateFlow<String?> = _inviteLink

    /** A failure worth showing, already worded by the repository. */
    private val _inviteError = MutableStateFlow<String?>(null)
    val inviteError: StateFlow<String?> = _inviteError

    /** What the box should offer right now. Recomputed by Domain, not here. */
    val suggestions: StateFlow<InviteSuggestions> =
        combine(_connections, _members, _selected, _inviteQuery) { conns, members, picked, query ->
            inviteSuggestions(
                connections = conns,
                memberIds = members.map { it.userId },
                selected = picked,
                query = query,
            )
        }.stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5000),
            InviteSuggestions(emptyList(), 0, false),
        )

    fun setInviteQuery(v: String) { _inviteQuery.value = v }

    fun addInvitee(invitee: Invitee) {
        _selected.value = _selected.value + invitee
        _inviteQuery.value = ""
    }

    fun removeInvitee(key: String) {
        _selected.value = _selected.value.filterNot { inviteeKey(it) == key }
    }

    /** Web resets the whole panel every time the modal opens. */
    fun resetInvite() {
        _selected.value = emptyList()
        _inviteQuery.value = ""
        _inviteOutcome.value = null
        _inviteLink.value = null
        _inviteError.value = null
    }

    /**
     * Invite everyone in the chips.
     *
     * One call per invitee, as web does -- the Edge Function takes a single
     * address, and batching would need a server change. A failure is counted
     * and the loop continues: inviting four people and having one address
     * bounce should still add the other three.
     */
    fun inviteSelected() {
        val picked = _selected.value
        if (picked.isEmpty() || _inviting.value) return
        _inviting.value = true
        _inviteOutcome.value = null
        _inviteLink.value = null
        _inviteError.value = null
        viewModelScope.launch {
            var added = 0
            var links = 0
            val failed = mutableListOf<String>()
            for (invitee in picked) {
                runCatching {
                    invitesRepository.createInvite(groupId, invitee.email.ifEmpty { null })
                }.onSuccess { result ->
                    if (result.added) added++ else links++
                }.onFailure {
                    failed.add(inviteeLabel(invitee))
                }
            }
            _selected.value = emptyList()
            _inviteQuery.value = ""
            _inviting.value = false
            _inviteOutcome.value = InviteOutcome(added, links, failed)
        }
    }

    /** A share link with no particular recipient. Web's `shareLink()`. */
    fun createShareLink() {
        if (_inviting.value) return
        _inviting.value = true
        _inviteOutcome.value = null
        _inviteLink.value = null
        _inviteError.value = null
        viewModelScope.launch {
            runCatching { invitesRepository.createInvite(groupId, null) }
                .onSuccess { _inviteLink.value = it.link }
                .onFailure { _inviteError.value = it.message }
            _inviting.value = false
        }
    }

    private val _accounts = MutableStateFlow<List<AccountOption>>(emptyList())
    val accounts: StateFlow<List<AccountOption>> = _accounts

    private val _loaded = MutableStateFlow(false)
    val loaded: StateFlow<Boolean> = _loaded

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private val _upiStage = MutableStateFlow<UpiStage>(UpiStage.Idle)
    val upiStage: StateFlow<UpiStage> = _upiStage

    private var namesById: Map<String, String> = emptyMap()

    /** (Re)subscribes to this group's live data. Safe to call more than
     * once (e.g. process recreation) -- cancels the previous subscription
     * job first so switching groups never double-collects. */
    fun select(groupId: String) {
        if (this.groupId == groupId && watchJob != null) return
        this.groupId = groupId
        watchJob?.cancel()
        _loaded.value = false

        val uid = userId
        watchJob = viewModelScope.launch {
            _group.value = splitsRepository.getGroup(groupId)
            val conns = if (uid != null) splitsRepository.watchConnections(uid).first() else emptyList()
            namesById = conns.associate { it.id to it.name } + (uid?.let { mapOf(it to "You") } ?: emptyMap())
            // The invite box's candidates. A connection with no email cannot be
            // invited by this route; Domain drops those rather than the query,
            // so the empty string travels and the rule stays in one place.
            _connections.value = conns.map { Invitee(id = it.id, name = it.name, email = it.email.orEmpty()) }
            _loaded.value = true

            if (uid != null) {
                combine(
                    splitsRepository.watchGroupMemberIds(groupId),
                    splitsRepository.watchGroupBalances(groupId, uid),
                ) { ids, balances -> ids to balances }.onEach { (ids, balances) ->
                    val byId = balances.associateBy { it.userId }
                    val everyone = (ids + uid).distinct()
                    _members.value = everyone.map { id ->
                        MemberUiModel(
                            userId = id,
                            name = if (id == uid) "You" else nameOf(id),
                            net = byId[id]?.net ?: 0L,
                            netFormatted = formatMoney(
                                kotlin.math.abs(byId[id]?.net ?: 0L),
                                _group.value?.currency ?: baseCurrencyNow(),
                            ),
                            isSelf = id == uid,
                        )
                    }
                }.launchIn(this)
            }

            splitsRepository.watchGroupExpenses(groupId).onEach { list ->
                _expenses.value = list.map { e ->
                    ExpenseUiModel(id = e.id, description = e.description?.takeIf { it.isNotBlank() } ?: "Expense", amountFormatted = formatMoney(e.amount, e.currency), date = e.occurredAt.take(10))
                }
            }.launchIn(this)

            splitsRepository.watchGroupSettlements(groupId).onEach { list ->
                _settlements.value = list.map { s ->
                    SettlementUiModel(
                        id = s.id, fromUser = s.fromUser, toUser = s.toUser,
                        fromName = if (s.fromUser == uid) "You" else nameOf(s.fromUser),
                        toName = if (s.toUser == uid) "You" else nameOf(s.toUser),
                        amountFormatted = formatMoney(s.amount, s.currency ?: baseCurrencyNow()), date = s.at.take(10),
                    )
                }
            }.launchIn(this)

            ledgerRepository.watchAccounts().onEach { list ->
                _accounts.value = list.filter { it.type !in setOf("stocks", "mutual_funds") }.map { AccountOption(it.id, it.name) }
            }.launchIn(this)
        }
    }

    private fun nameOf(id: String): String = namesById[id] ?: "Someone"

    /** Equal-split add-expense -- see docs/mobile/screen-specs/splits.md's
     * scope note: web's richer percent/exact/itemized modes are deferred
     * to the receipt-scan work, this covers the common case end-to-end. */
    fun addExpense(description: String, amountMajorText: String, payerId: String, payerAccountId: String?, participantIds: List<String>, onDone: (String?) -> Unit) {
        val uid = userId ?: return
        val g = _group.value ?: return
        val amountMajor = amountMajorText.replace(",", "").toDoubleOrNull()
        if (amountMajor == null || amountMajor <= 0 || participantIds.isEmpty()) { onDone("Enter a valid amount and at least one participant."); return }
        val amountMinor = Math.round(amountMajor * 100)
        viewModelScope.launch {
            try {
                splitsRepository.createSplitExpense(
                    userId = uid,
                    input = SplitExpenseInput(
                        groupId = groupId,
                        mode = "equal",
                        total = money(amountMinor, g.currency),
                        participants = participantIds.map { ParticipantInput(it) },
                        payers = listOf(PayerInput(payerId, amountMinor, payerAccountId)),
                        description = description.ifBlank { null },
                        occurredAt = Instant.now().toString(),
                    ),
                )
                onDone(null)
            } catch (e: Exception) {
                onDone(e.message ?: "Couldn't add the expense.")
            }
        }
    }

    /** Manual "mark settled" -- no UPI, matches web's confirmSettle("confirmed"). */
    fun settleManually(otherUserId: String, amountMajorText: String, direction: String, accountId: String?, onDone: (String?) -> Unit) {
        val uid = userId ?: return
        val g = _group.value ?: return
        val amountMajor = amountMajorText.replace(",", "").toDoubleOrNull()
        if (amountMajor == null || amountMajor <= 0) { onDone("Enter a valid amount."); return }
        viewModelScope.launch {
            try {
                splitsRepository.settleUp(userId = uid, otherUserId = otherUserId, groupId = groupId, amount = Math.round(amountMajor * 100), direction = direction, accountId = accountId, currency = g.currency)
                onDone(null)
            } catch (e: Exception) {
                onDone(e.message ?: "Couldn't record the settlement.")
            }
        }
    }

    /** Payer-side UPI fetch -- mirrors PayViaUpi.tsx's start(). */
    fun startUpiFetch(otherUserId: String) {
        _upiStage.value = UpiStage.Fetching
        viewModelScope.launch {
            try {
                val handle = upiRepository.fetchCounterpartyHandle(otherUserId)
                _upiStage.value = UpiStage.Ready(handle.vpa, handle.displayName)
            } catch (e: UpiHandleError) {
                _upiStage.value = UpiStage.Error(e.message ?: "Couldn't fetch payment details.", e.code)
            } catch (e: Exception) {
                _upiStage.value = UpiStage.Error(e.message ?: "Couldn't reach the payments service.", null)
            }
        }
    }

    fun resetUpiStage() { _upiStage.value = UpiStage.Idle }

    /** Records the UPI hand-off as a "pending" settlement -- only the
     * payee can confirm it arrived (matches confirmSettle("pending", ref)). */
    fun recordUpiSettlement(otherUserId: String, amountMajorText: String, direction: String, upiRef: String, onDone: (String?) -> Unit) {
        val uid = userId ?: return
        val g = _group.value ?: return
        val amountMajor = amountMajorText.replace(",", "").toDoubleOrNull()
        if (amountMajor == null || amountMajor <= 0) { onDone("Enter a valid amount."); return }
        viewModelScope.launch {
            try {
                splitsRepository.settleUp(
                    userId = uid, otherUserId = otherUserId, groupId = groupId,
                    amount = Math.round(amountMajor * 100), direction = direction, accountId = null,
                    currency = g.currency, status = "pending", method = "upi_intent", upiRef = upiRef,
                )
                onDone(null)
            } catch (e: Exception) {
                onDone(e.message ?: "Couldn't record the settlement.")
            }
        }
    }
}
