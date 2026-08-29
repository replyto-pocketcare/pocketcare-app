package com.sanvya.app.ui.splits

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.ExpenseItem
import com.sanvya.app.data.repository.ExpenseItemShare
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.InvitesRepository
import com.sanvya.app.data.repository.SplitGroup
import com.sanvya.app.data.repository.SplitsRepository
import com.sanvya.app.data.repository.UpiHandleError
import com.sanvya.app.data.repository.UpiRepository
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
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.i18n.S

/**
 * `netFormatted` alongside `net` for the same reason `ExpenseUiModel` and
 * `SettlementUiModel` carry `amountFormatted`: the group's currency is known
 * here and not in the row composable, which had been calling `formatMoney`
 * without one. The raw `net` stays for the sign and the colour.
 *
 * The display NAME is not on any of these models. `S` is resource-backed on
 * Android, so "You" and the "Someone" fallback need a `Resources` the view
 * model must not hold -- it would pin the configuration the view model was
 * created under and go stale on a locale change. The ids travel instead and
 * [GroupDetailViewModel.nameOf] resolves them in the composable. (iOS's
 * `S` needs no such handle, which is why its models still carry `name`.)
 */
data class MemberUiModel(
    val userId: String,
    val net: Long,
    val netFormatted: String,
    val isSelf: Boolean,
)
data class ExpenseUiModel(
    val id: String,
    /** Raw, so the row can fall back to a translated label for a blank one. */
    val description: String?,
    val amountFormatted: String,
    /** Kept alongside the formatted string so the summary can total the group. */
    val amountMinor: Long,
    /** The EXPENSE's currency, which the breakdown's own numbers are in. */
    val currency: String,
    val date: String,
    /** `expenses.has_items` -- whether there is a per-item breakdown to open. */
    val hasItems: Boolean,
)

/**
 * [pending] drives web's "Waiting to be confirmed" line. A settlement raised
 * from a UPI hand-off is a CLAIM until the payee says the money landed, and a
 * row that looks identical to a confirmed one tells both people the debt is
 * closed when it is not.
 */
data class SettlementUiModel(
    val id: String,
    val fromUser: String,
    val toUser: String,
    /** The party who is not you -- who web's two first-person labels name. */
    val otherUserId: String,
    val iPaid: Boolean,
    val paidToMe: Boolean,
    val amountFormatted: String,
    val date: String,
    val pending: Boolean,
)
data class AccountOption(val id: String, val name: String)

/**
 * The raw rows behind one itemised bill, loaded on demand when a row is opened.
 *
 * Kept raw rather than pre-formatted: the arithmetic that turns these into what
 * is on screen is Domain's `itemBreakdown`, and it re-runs whenever the person
 * filter chip changes -- which is view state, not view-model state.
 */
data class ExpenseBreakdownUiModel(
    val items: List<ExpenseItem>,
    val shares: List<ExpenseItemShare>,
)

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
            // Real names only. "You" and the "Someone" fallback are resource
            // strings and are resolved by [nameOf], which the composable calls
            // with its own `Resources`.
            namesById = conns.associate { it.id to it.name }
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
                    ExpenseUiModel(
                        id = e.id,
                        description = e.description?.takeIf { it.isNotBlank() },
                        amountFormatted = formatMoney(e.amount, e.currency),
                        amountMinor = e.amount,
                        currency = e.currency,
                        date = e.occurredAt.take(10),
                        hasItems = e.hasItems,
                    )
                }
            }.launchIn(this)

            splitsRepository.watchGroupSettlements(groupId).onEach { list ->
                _settlements.value = list.map { s ->
                    SettlementUiModel(
                        id = s.id, fromUser = s.fromUser, toUser = s.toUser,
                        // Web's three labels: "You paid X", "X paid you", and
                        // "X paid Y" for a settlement between two other members
                        // of a group you are in.
                        otherUserId = if (s.fromUser == uid) s.toUser else s.fromUser,
                        iPaid = s.fromUser == uid,
                        paidToMe = s.toUser == uid,
                        amountFormatted = formatMoney(s.amount, s.currency ?: baseCurrencyNow()),
                        date = s.at.take(10),
                        // A NULL status is a settlement written before the
                        // confirm/dispute columns existed; the query already
                        // treats those as confirmed (IFNULL(status,'confirmed'))
                        // and so must this.
                        pending = s.status == "pending",
                    )
                }
            }.launchIn(this)

            ledgerRepository.watchAccounts().onEach { list ->
                _accounts.value = list.filter { it.type !in setOf("stocks", "mutual_funds") }.map { AccountOption(it.id, it.name) }
            }.launchIn(this)
        }
    }

    /**
     * A member's display name, resolved against the caller's `Resources`.
     *
     * Public and res-taking rather than a field on the UI models: see the note
     * on [MemberUiModel]. Mirrors SplitsViewModel.nameOfUser.
     */
    fun nameOf(id: String, res: android.content.res.Resources): String = when {
        id == userId -> S.Receipts.splitYou(res)
        else -> namesById[id] ?: S.Groups.someone(res)
    }

    // Add-expense is GONE from this view model.
    //
    // It used to open a sheet that could only split equally, so an unequal
    // expense added from inside a group was impossible on a phone -- while the
    // full percent/exact/itemised editor sat one screen away, already built.
    // Web's button is a link to that editor with the group preselected
    // (`/transactions/new?split=<id>`, groups/[id]/page.tsx), and the screen now
    // navigates to the same place. Two half-forms for one job is worse than one
    // whole one, and the half was the one that could get a bill wrong.
    //
    // (A line comment, not KDoc: KDoc here would silently attach itself to the
    // next declaration, which is about something else entirely.)

    // ---- itemised breakdown ----

    /** Loaded bills, by expense id. Absent = never opened. */
    private val _breakdowns = MutableStateFlow<Map<String, ExpenseBreakdownUiModel>>(emptyMap())
    val breakdowns: StateFlow<Map<String, ExpenseBreakdownUiModel>> = _breakdowns

    /**
     * Fetch one bill's lines the first time its row is expanded.
     *
     * Once, not per recomposition, and never eagerly for the whole list: a
     * group can hold hundreds of expenses and almost none of them are opened.
     * The rows never change after the expense is written (the breakdown is
     * read-only on every platform), so a cached copy cannot go stale.
     */
    fun loadBreakdown(expenseId: String) {
        if (_breakdowns.value.containsKey(expenseId)) return
        viewModelScope.launch {
            runCatching {
                ExpenseBreakdownUiModel(
                    items = splitsRepository.expenseItems(expenseId),
                    shares = splitsRepository.expenseItemShares(expenseId),
                )
            }.onSuccess { loaded ->
                _breakdowns.value = _breakdowns.value + (expenseId to loaded)
            }.onFailure { e ->
                _error.value = e.message
            }
        }
    }

    /**
     * The group's headline figures -- total spent, what you are owed, what you
     * owe -- in the group's own currency.
     *
     * Web's summary card. Without it the screen listed rows and left the user
     * to add them up: you could not tell what a trip cost in total, or which
     * way your own side of it leaned, without doing arithmetic by hand.
     *
     * `total` is every expense in the group. The other two come from the
     * members' nets, which the view model already computes for the rows.
     */
    val summary: StateFlow<GroupSummaryUiModel?> = combine(_group, _expenses, _members) { g, exps, mems ->
        if (g == null) {
            null
        } else {
            GroupSummaryUiModel(
                totalSpentFormatted = formatMoney(exps.sumOf { it.amountMinor }, g.currency),
                owedFormatted = formatMoney(mems.sumOf { maxOf(0L, it.net) }, g.currency),
                oweFormatted = formatMoney(mems.sumOf { maxOf(0L, -it.net) }, g.currency),
                memberCount = mems.size,
                startDate = g.startDate,
                endDate = g.endDate,
                autoSplit = g.autoSplit,
            )
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    /** Rename, re-date, or toggle auto-split. Matches web's `saveEdit()`. */
    fun updateGroup(name: String, startDate: String, endDate: String, autoSplit: Boolean, onDone: (String?) -> Unit) {
        if (name.isBlank()) { onDone("Enter a name."); return }
        viewModelScope.launch {
            try {
                splitsRepository.updateGroup(groupId, name, startDate, endDate, autoSplit)
                _group.value = splitsRepository.getGroup(groupId)
                onDone(null)
            } catch (e: Exception) {
                onDone(e.message)
            }
        }
    }

    /** Soft-delete the group. Its expenses stay in the ledger -- see the repo. */
    fun deleteGroup(onDone: (String?) -> Unit) {
        viewModelScope.launch {
            try {
                splitsRepository.deleteGroup(groupId)
                onDone(null)
            } catch (e: Exception) {
                onDone(e.message)
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
                splitsRepository.settleUp(userId = uid, otherUserId = otherUserId, groupId = groupId, amount = fromMajor(amountMajor, g.currency).amount, direction = direction, accountId = accountId, currency = g.currency)
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
                    amount = fromMajor(amountMajor, g.currency).amount, direction = direction, accountId = null,
                    currency = g.currency, status = "pending", method = "upi_intent", upiRef = upiRef,
                )
                onDone(null)
            } catch (e: Exception) {
                onDone(e.message ?: "Couldn't record the settlement.")
            }
        }
    }
}

/** Web's summary card, as one value. */
data class GroupSummaryUiModel(
    val totalSpentFormatted: String,
    val owedFormatted: String,
    val oweFormatted: String,
    val memberCount: Int,
    val startDate: String?,
    val endDate: String?,
    val autoSplit: Boolean,
)
