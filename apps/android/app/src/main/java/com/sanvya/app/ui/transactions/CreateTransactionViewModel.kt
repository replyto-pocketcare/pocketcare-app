package com.sanvya.app.ui.transactions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.Account
import com.sanvya.app.data.repository.CategoryRow
import com.sanvya.app.data.repository.LabelRow
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.PaymentMethodRow
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.data.repository.TransactionItemInput
import com.sanvya.app.domain.categorize.CategoryData
import com.sanvya.app.domain.entitlements.isPaid as domainIsPaid
import com.sanvya.app.domain.js.jsParseFloat
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.money.money
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import com.sanvya.app.data.repository.ParticipantInput
import com.sanvya.app.data.repository.PayerInput
import com.sanvya.app.data.repository.SplitExpenseInput
import com.sanvya.app.data.repository.SplitGroup
import com.sanvya.app.data.repository.SplitsRepository
import com.sanvya.app.data.repository.UserProfile
import com.sanvya.app.domain.splits.AutoSplitCandidate
import com.sanvya.app.domain.splits.SplitModes
import com.sanvya.app.domain.splits.autoSplitGroupFor
import com.sanvya.app.domain.splits.SplitPlan
import com.sanvya.app.domain.splits.forOtherActive
import com.sanvya.app.domain.splits.splitActive
import com.sanvya.app.domain.splits.splitPlan
import com.sanvya.app.i18n.S
import com.sanvya.app.ui.FormOptions
import com.sanvya.app.ui.baseCurrencyNow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.LocalDateTime
import java.time.ZoneId

typealias TxType = String // "expense" | "income" | "transfer"

data class TxItemDraft(val id: String, val description: String, val value: String)

private var itemCounter = 0
private fun newDraftItem() = TxItemDraft(id = "i${++itemCounter}", description = "", value = "")

data class CreateTransactionUiState(
    val type: TxType = "expense",
    val accountId: String? = null,
    val toAccountId: String? = null,
    val categoryId: String? = null,
    val selectedLabels: List<String> = emptyList(),
    val note: String = "",
    val paymentMethod: String = "",
    val items: List<TxItemDraft> = listOf(newDraftItem()),
    val toValue: String = "",
    /** Local wall-clock date+time the user picked, defaults to now --
     * converted to an ISO instant at save time. Matches `date` on
     * transactions/new/page.tsx (a `datetime-local` input, defaults to now). */
    val occurredAt: LocalDateTime = LocalDateTime.now(),
    val saving: Boolean = false,
    val saved: Boolean = false,
    val error: String? = null,
    /**
     * The category the auto-categoriser proposed for the current description,
     * and whether it was applied without the user asking.
     *
     * Both are needed at save time: learning treats "you suggested Food and
     * they chose Groceries" as a CORRECTION worth five ordinary sightings, and
     * that is only true if the suggestion was actually on screen.
     */
    val suggestedCategoryId: String? = null,
    val autoApplied: Boolean = false,
    /** True once the user has touched the category picker themselves. */
    val manualCategory: Boolean = false,

    // ---- split ----
    //
    // Web keeps the two toggles mutually exclusive by RENDERING: the "paid for
    // someone else" card is hidden while the split is on and vice versa. Both
    // flags live here so the same exclusion is one condition rather than two
    // screens' worth of `if`.
    val splitOn: Boolean = false,
    /** True once the user has touched the toggle or the group picker. Web uses
     *  it to stop the auto-split effect from overriding a deliberate choice. */
    val splitTouched: Boolean = false,
    val splitGroupId: String = "",
    val splitMode: String = SplitModes.EQUAL,
    /** User ids taking part in THIS expense -- a subset of the group. */
    val splitMembers: List<String> = emptyList(),
    /** Raw text per member: a percent in percent mode, an amount in exact. */
    val shareText: Map<String, String> = emptyMap(),
    val multiPayer: Boolean = false,
    /** Raw text per member: what they put in. */
    val paidText: Map<String, String> = emptyMap(),

    val forOtherOn: Boolean = false,
    val forOtherUserId: String = "",
)

/** New transaction — ported from transactions/new/page.tsx's regular
 * expense/income/transfer path per docs/mobile/screen-specs/transactions.md.
 * Split-expense and templates are explicitly deferred (see spec's Scope
 * section) -- not built, not faked.
 *
 * Auto-categorisation is no longer in that list: it landed 2026-08-27 and
 * behaves as web's does -- debounced suggestion while typing, auto-applied
 * unless the user has picked a category themselves, and learned from on save. */
class CreateTransactionViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val splitsRepository: SplitsRepository by inject()
    private val authRepository: AuthRepository by inject()
    private val prefsRepository: PrefsRepository by inject()

    private val ui = MutableStateFlow(CreateTransactionUiState())

    /**
     * Accounts that can move real money.
     *
     * Web's picker query carries `NOT_INVESTMENT_ACCOUNT_SQL` -- demat, stocks
     * and mutual funds are excluded from the NEW-transaction form entirely
     * (the EDIT form does not filter, because it has to show whatever the
     * transaction already points at). Without it a user could book a grocery
     * expense against their demat account.
     *
     * `isInvestment` below is web's own defensive branch and stays: with this
     * filter in place it can never be true on either platform, exactly as it
     * can never be true on web. Reproducing dead code is the point of a port.
     */
    val accounts: StateFlow<List<Account>> = ledgerRepository.watchAccounts(includeArchived = false)
        .map { list -> list.filterNot { FormOptions.isInvestmentAccount(it.type) } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val categories: StateFlow<List<CategoryRow>> = ledgerRepository.watchCategories()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val labels: StateFlow<List<LabelRow>> = ledgerRepository.watchLabels()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    private val paymentMethods: StateFlow<List<PaymentMethodRow>> = ledgerRepository.watchPaymentMethods()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val uiState: StateFlow<CreateTransactionUiState> = ui.asStateFlow()

    /** Selected account, defaulting to the first real account -- matches
     * `accounts.find(a => a.id === accountId) ?? accounts[0]`. */
    val account: StateFlow<Account?> = combine(accounts, ui) { accts, state ->
        accts.find { it.id == state.accountId } ?: accts.firstOrNull()
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    val toAccount: StateFlow<Account?> = combine(accounts, ui, account) { accts, state, acct ->
        accts.find { it.id == state.toAccountId } ?: accts.firstOrNull { it.id != acct?.id }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    // ---- split ----

    /**
     * Groups and trips for the picker.
     *
     * `includeDirect = false`, matching web's `useGroups()`: a direct group is
     * the 1:1 container created by "I paid for someone else" and is not
     * something to pick from a list.
     */
    val groups: StateFlow<List<SplitGroup>> = splitsRepository.watchGroups()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /** Every membership row, so the picker can list a group's members. */
    private val groupMembers: StateFlow<Map<String, List<String>>> =
        splitsRepository.watchAllGroupMembers()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyMap())

    /** People this user is connected to -- the "paid for someone else" list. */
    val connections: StateFlow<List<UserProfile>> = authRepository.currentUserId
        .flatMapLatest { uid -> if (uid == null) flowOf(emptyList()) else splitsRepository.watchConnections(uid) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun membersOf(groupId: String): List<String> = groupMembers.value[groupId].orEmpty()

    /** The signed-in user's id, for the summary's "your share" row. */
    val currentUserId: String? get() = authRepository.currentUserId.value

    /** A member's display name. "You" for the current user, as web has it. */
    fun memberName(userId: String, res: android.content.res.Resources): String =
        if (userId == authRepository.currentUserId.value) {
            S.Receipts.splitYou(res)
        } else {
            connections.value.firstOrNull { it.id == userId }?.name ?: userId.take(8)
        }

    val splitActive: StateFlow<Boolean> = ui
        .map { splitActive(it.type, it.splitOn, it.splitGroupId, it.splitMembers.size) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    val forOtherActive: StateFlow<Boolean> = combine(ui, account) { state, acct ->
        forOtherActive(
            type = state.type,
            splitOn = state.splitOn,
            forOtherOn = state.forOtherOn,
            otherUserId = state.forOtherUserId,
            totalMinor = totalMinor(acct?.currency ?: baseCurrencyNow()),
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    /** The whole split, recomputed by Domain whenever anything it reads moves. */
    val splitPlan: StateFlow<SplitPlan> = combine(ui, account) { state, acct ->
        val currency = acct?.currency ?: baseCurrencyNow()
        splitPlan(
            groupId = state.splitGroupId,
            mode = state.splitMode,
            memberIds = state.splitMembers,
            me = authRepository.currentUserId.value.orEmpty(),
            totalMinor = totalMinor(currency),
            currency = currency,
            shareText = state.shareText,
            multiPayer = state.multiPayer,
            paidText = state.paidText,
            hasAccount = acct != null,
        )
    }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5000),
        splitPlan("", SplitModes.EQUAL, emptyList(), "", 0L, baseCurrencyNow(), emptyMap(), false, emptyMap(), false),
    )

    fun setSplitOn(v: Boolean) = update { it.copy(splitOn = v, splitTouched = true) }
    fun setSplitMode(v: String) = update { it.copy(splitMode = v) }
    fun setMultiPayer(v: Boolean) = update { it.copy(multiPayer = v) }
    fun setShareText(userId: String, v: String) = update { it.copy(shareText = it.shareText + (userId to v)) }
    fun setPaidText(userId: String, v: String) = update { it.copy(paidText = it.paidText + (userId to v)) }
    fun setForOtherOn(v: Boolean) = update { it.copy(forOtherOn = v) }
    fun setForOtherUserId(v: String) = update { it.copy(forOtherUserId = v) }

    /** Choosing a group replaces the participant list with its members. */
    fun setSplitGroup(groupId: String) = update {
        it.copy(
            splitTouched = true,
            splitGroupId = groupId,
            splitMembers = if (groupId.isEmpty()) emptyList() else membersOf(groupId),
        )
    }

    fun toggleSplitMember(userId: String) = update {
        it.copy(
            splitMembers = if (it.splitMembers.contains(userId)) {
                it.splitMembers - userId
            } else {
                it.splitMembers + userId
            },
        )
    }

    val isInvestment: StateFlow<Boolean> = account
        .map { it?.type in setOf("stocks", "mutual_funds") }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    val relevantPaymentMethods: StateFlow<List<PaymentMethodRow>> = combine(paymentMethods, account) { methods, acct ->
        methods.filter { it.accountTypeId == acct?.type }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val relevantCategories: StateFlow<List<CategoryRow>> = combine(categories, ui) { cats, state ->
        val kind = if (state.type == "income") "income" else "expense"
        cats.filter { it.kind == kind }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    init {
        // Auto-split: a date inside an auto-split trip preselects it, ONCE.
        //
        // `splitTouched` is the whole guard: web sets it the moment the user
        // touches the toggle or the group picker, and without it a deliberate
        // "no, not this trip" would be undone on the next recomposition.
        viewModelScope.launch {
            combine(groups, groupMembers, ui) { list, membersByGroup, state ->
                Triple(list, membersByGroup, state)
            }.collect { (list, membersByGroup, state) ->
                if (state.type != "expense" || state.splitTouched) return@collect
                val candidates = list.map {
                    AutoSplitCandidate(it.id, it.startDate, it.endDate, it.autoSplit)
                }
                val auto = autoSplitGroupFor(candidates, state.occurredAt.toLocalDate().toString())
                if (auto != null && state.splitGroupId != auto) {
                    ui.value = state.copy(
                        splitOn = true,
                        splitGroupId = auto,
                        splitMembers = membersByGroup[auto].orEmpty(),
                        splitMode = SplitModes.EQUAL,
                    )
                }
            }
        }
        // Investment accounts (stocks/mutual funds) can only move money via
        // transfers -- matches the `isInvestment && type !== transfer` effect.
        viewModelScope.launch {
            isInvestment.collect { inv -> if (inv && ui.value.type != "transfer") setType("transfer") }
        }
        // Payment method resets to the first valid one whenever the account
        // (or its type) changes -- matches the paymentMethods effect.
        viewModelScope.launch {
            relevantPaymentMethods.collect { methods ->
                if (ui.value.paymentMethod !in methods.map { it.id }) {
                    ui.value = ui.value.copy(paymentMethod = methods.firstOrNull()?.id ?: "")
                }
            }
        }
        // Auto-categorisation. Debounced at web's own 220ms: the query is two
        // narrow reads, but running them on every keystroke of a long POS
        // narration would still be dozens of round-trips for one answer.
        //
        // `distinctUntilChanged` matters as much as the debounce -- moving the
        // cursor or re-selecting text re-emits the same string, and without it
        // every one of those would re-suggest and stomp a manual choice.
        viewModelScope.launch {
            prefsRepository.watchEntitlement().collect { ent ->
                _isPaid.value = domainIsPaid(
                    ent?.tier,
                    ent?.premiumTrialStartDate,
                    ent?.compTier,
                    ent?.compUntil,
                    System.currentTimeMillis(),
                )
            }
        }
        viewModelScope.launch {
            ui.map { autoCategorizeTextOf(it) }
                .distinctUntilChanged()
                .debounce(AUTO_CATEGORIZE_DEBOUNCE_MS)
                .collectLatest { text -> suggest(text) }
        }
    }

    /**
     * What the categoriser reads: every item description plus the note, exactly
     * as web joins them. A transfer contributes nothing -- it has no category
     * to suggest.
     */
    private fun autoCategorizeTextOf(state: CreateTransactionUiState): String {
        if (state.type == "transfer") return state.note.trim()
        val descriptions = state.items.map { it.description.trim() }.filter { it.isNotEmpty() }.joinToString(", ")
        return listOf(descriptions, state.note.trim()).filter { it.isNotEmpty() }.joinToString(" ")
    }

    /**
     * Whether the categoriser runs at all.
     *
     * Web gates BOTH halves on the entitlement — `useAutoCategorize(text, cats,
     * isPaid && type !== "transfer")` and `if (... && isPaid) learnCategory(...)`.
     * The first port of this screen missed it, so a free account was quietly
     * getting a paid feature and, worse, writing category rules that would then
     * shape suggestions it was never supposed to see.
     */
    private val _isPaid = MutableStateFlow(false)

    private suspend fun suggest(text: String) {
        if (!_isPaid.value) {
            ui.value = ui.value.copy(suggestedCategoryId = null)
            return
        }
        if (text.isBlank() || ui.value.type == "transfer") {
            ui.value = ui.value.copy(suggestedCategoryId = null)
            return
        }
        val userId = authRepository.currentUserId.value ?: return
        val cats = relevantCategories.value.map { CategoryData(it.id, it.name) }
        if (cats.isEmpty()) return
        val suggestion = runCatching {
            ledgerRepository.suggestCategory(text, userId, cats)
        }.getOrNull() ?: run {
            ui.value = ui.value.copy(suggestedCategoryId = null)
            return
        }
        val state = ui.value
        ui.value = if (!state.manualCategory && state.categoryId != suggestion) {
            state.copy(suggestedCategoryId = suggestion, categoryId = suggestion, autoApplied = true)
        } else {
            state.copy(suggestedCategoryId = suggestion)
        }
    }

    /** The file's `ui.value = ui.value.copy(...)` shape, named once. */
    private inline fun update(block: (CreateTransactionUiState) -> CreateTransactionUiState) {
        ui.value = block(ui.value)
    }

    fun setType(v: TxType) { ui.value = ui.value.copy(type = v) }
    fun setAccountId(v: String) { ui.value = ui.value.copy(accountId = v) }
    fun setToAccountId(v: String) { ui.value = ui.value.copy(toAccountId = v) }
    fun setCategoryId(v: String?) {
        // A manual pick stops the suggester overwriting it, for good. Web keeps
        // the same latch and never clears it.
        ui.value = ui.value.copy(categoryId = v, manualCategory = true, autoApplied = false)
    }
    fun setPaymentMethod(v: String) { ui.value = ui.value.copy(paymentMethod = v) }
    fun setNote(v: String) { ui.value = ui.value.copy(note = v) }
    fun setToValue(v: String) { ui.value = ui.value.copy(toValue = v) }
    fun setOccurredAt(v: LocalDateTime) { ui.value = ui.value.copy(occurredAt = v) }
    fun toggleLabel(name: String) {
        val cur = ui.value.selectedLabels
        ui.value = ui.value.copy(selectedLabels = if (name in cur) cur - name else cur + name)
    }
    fun addNewLabel(name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty() || trimmed in ui.value.selectedLabels) return
        ui.value = ui.value.copy(selectedLabels = ui.value.selectedLabels + trimmed)
    }

    fun updateItem(id: String, description: String? = null, value: String? = null) {
        ui.value = ui.value.copy(items = ui.value.items.map {
            if (it.id != id) it else it.copy(
                description = description ?: it.description,
                value = value ?: it.value,
            )
        })
    }
    fun addItem() { ui.value = ui.value.copy(items = ui.value.items + newDraftItem()) }
    fun removeItem(id: String) { ui.value = ui.value.copy(items = ui.value.items.filterNot { it.id == id }) }
    /** Transfer uses a single amount field, mapped onto items[0].value so the
     * same draft-item state backs both UIs (matches web reusing `items[0]`
     * for the transfer amount input). */
    fun setTransferAmount(v: String) {
        val first = ui.value.items.firstOrNull() ?: newDraftItem()
        ui.value = ui.value.copy(items = listOf(first.copy(value = v)))
    }

    /**
     * The typed amount in minor units.
     *
     * Web is `items.map(it => fromMajor(parseFloat(it.value) || 0, currency))`
     * summed -- per item, not on the sum, so each item rounds the way web's
     * does. This used to be `Math.round(v * 100)`, which quietly gave a JPY
     * expense a hundred times too many units and made every split refuse to
     * balance against it.
     */
    fun totalMinor(currency: String): Long =
        ui.value.items.sumOf { fromMajor(jsParseFloat(it.value) ?: 0.0, currency).amount }

    /**
     * Web's `canSave`, including the two SPLIT guards that were missing.
     *
     * Without them an exact- or percent-mode split whose shares do not add up
     * left Save enabled, `save()` found `plan.valid == false`, fell past the
     * split branch and booked the whole amount as an ordinary personal expense.
     * No split, no warning, no error -- the worst shape a bug can take, because
     * it looks like it worked. Domain computed `valid` correctly the whole
     * time under 35 vectors; the button simply never asked.
     *
     * The `forOther` guard has web's exact shape, including its two escape
     * hatches: it does not apply to a non-expense, and it does not apply while
     * the split toggle is on -- because the card is hidden then, and a hidden
     * control must not be able to block Save.
     */
    fun canSave(): Boolean {
        val state = ui.value
        val acct = account.value ?: return false
        val total = totalMinor(acct.currency)
        if (total <= 0 || state.saving) return false
        if (state.type == "transfer") {
            val to = toAccount.value ?: return false
            if (to.id == acct.id) return false
        }
        if (splitActive.value && !splitPlan.value.valid) return false
        if (state.forOtherOn && state.type == "expense" && !state.splitOn && state.forOtherUserId.isEmpty()) {
            return false
        }
        return true
    }

    /** Matches transactions/new/page.tsx's save() for the regular
     * (non-split) path exactly. */
    fun save() {
        val acct = account.value ?: return
        if (!canSave()) return
        val state = ui.value
        val userId = authRepository.currentUserId.value ?: return
        ui.value = ui.value.copy(saving = true, error = null)
        viewModelScope.launch {
            try {
                val total = totalMinor(acct.currency)
                val occurredAt = state.occurredAt.atZone(ZoneId.systemDefault()).toInstant().toString()
                val nonZeroItems = state.items.filter { (it.value.toDoubleOrNull() ?: 0.0) > 0 }
                val splitDescription = nonZeroItems
                    .joinToString(", ") { it.description.trim() }
                    .ifEmpty { null }

                // Paid entirely for someone else: a 1:1 split where they carry
                // the whole share and you carry none. `mode = "exact"` with your
                // share pinned to 0 is what makes projectPersonal book the full
                // amount as `lend` rather than as your own spending -- the money
                // left your account, but none of it was yours to spend.
                if (forOtherActive.value) {
                    val person = connections.value.firstOrNull { it.id == state.forOtherUserId }
                    val groupId = splitsRepository.getOrCreateDirectGroup(
                        userId = userId,
                        otherUserId = state.forOtherUserId,
                        otherName = person?.name ?: "Direct",
                        currency = acct.currency,
                    )
                    splitsRepository.createSplitExpense(
                        userId = userId,
                        input = SplitExpenseInput(
                            groupId = groupId,
                            mode = SplitModes.EXACT,
                            total = money(total, acct.currency),
                            participants = listOf(
                                ParticipantInput(userId, 0.0),
                                ParticipantInput(state.forOtherUserId, total.toDouble()),
                            ),
                            payers = listOf(PayerInput(userId, total, acct.id)),
                            categoryId = state.categoryId,
                            description = splitDescription,
                            note = state.note.trim().ifEmpty { null },
                            occurredAt = occurredAt,
                        ),
                    )
                    learnFromThisSave(state)
                    ui.value = ui.value.copy(saving = false, saved = true)
                    return@launch
                }

                // Split path: book only your share; lend/borrow the rest via the
                // virtual accounts createSplitExpense maintains.
                val plan = splitPlan.value
                if (splitActive.value && plan.valid) {
                    splitsRepository.createSplitExpense(
                        userId = userId,
                        input = SplitExpenseInput(
                            groupId = state.splitGroupId,
                            mode = state.splitMode,
                            total = money(total, acct.currency),
                            participants = plan.participants.map {
                                ParticipantInput(it.userId, it.value)
                            },
                            payers = plan.payers.map {
                                PayerInput(
                                    userId = it.userId,
                                    paid = it.paidMinor,
                                    // Only MY leg carries an account -- the
                                    // others' money did not move through one of
                                    // mine, and web writes null for them.
                                    accountId = if (it.isMe) acct.id else null,
                                )
                            },
                            categoryId = state.categoryId,
                            description = splitDescription,
                            note = state.note.trim().ifEmpty { null },
                            occurredAt = occurredAt,
                        ),
                    )
                    learnFromThisSave(state)
                    ui.value = ui.value.copy(saving = false, saved = true)
                    return@launch
                }

                if (state.type == "transfer") {
                    val to = toAccount.value ?: error("Destination account required")
                    val crossCurrency = to.currency != acct.currency
                    ledgerRepository.createTransaction(
                        userId = userId, accountId = acct.id, type = "transfer",
                        amount = money(total, acct.currency), occurredAt = occurredAt,
                        labels = state.selectedLabels.ifEmpty { null },
                        toAccountId = to.id,
                        toAmount = if (crossCurrency) fromMajor(state.toValue.toDoubleOrNull() ?: 0.0, to.currency) else null,
                    )
                } else {
                    val nonZero = state.items.filter { (it.value.toDoubleOrNull() ?: 0.0) > 0 }
                    val combinedDescription = nonZero.joinToString(", ") { it.description.trim() }.ifEmpty { null }
                    val itemPayload = if (nonZero.size > 1) {
                        nonZero.mapIndexed { i, it ->
                            TransactionItemInput(
                                description = it.description.trim().ifEmpty { "Item ${i + 1}" },
                                amount = fromMajor(it.value.toDoubleOrNull() ?: 0.0, acct.currency),
                            )
                        }
                    } else null
                    ledgerRepository.createTransaction(
                        userId = userId, accountId = acct.id, type = state.type,
                        amount = money(total, acct.currency), occurredAt = occurredAt,
                        categoryId = state.categoryId, labels = state.selectedLabels.ifEmpty { null },
                        note = state.note.trim().ifEmpty { null }, description = combinedDescription,
                        paymentMethod = state.paymentMethod.ifEmpty { null }, items = itemPayload,
                    )
                }
                learnFromThisSave(state)
                ui.value = ui.value.copy(saving = false, saved = true)
            } catch (e: Exception) {
                ui.value = ui.value.copy(saving = false, error = e.message ?: "Couldn't save this transaction")
            }
        }
    }

    /**
     * Teach the categoriser from what was actually saved.
     *
     * `suggestedCategoryId` is passed ONLY when the suggestion was auto-applied.
     * That is web's rule and it is the load-bearing part: a correction is
     * "you proposed X and I chose Y", which is only meaningful if X was on
     * screen. Passing a suggestion the user never saw would record a correction
     * they never made, and corrections count for five ordinary sightings.
     *
     * Best-effort: a learning failure must never turn a saved transaction into
     * an error the user has to read.
     */
    private suspend fun learnFromThisSave(state: CreateTransactionUiState) {
        if (!_isPaid.value || state.type == "transfer") return
        val text = autoCategorizeTextOf(state)
        if (text.isBlank() || state.categoryId == null) return
        val userId = authRepository.currentUserId.value ?: return
        runCatching {
            ledgerRepository.learnFromSave(
                userId = userId,
                text = text,
                chosenCategoryId = state.categoryId,
                suggestedCategoryId = if (state.autoApplied) state.suggestedCategoryId else null,
            )
        }
    }

    private companion object {
        /** Web's own 220ms. */
        const val AUTO_CATEGORIZE_DEBOUNCE_MS = 220L
    }
}
