package com.sanvya.app.ui.receipts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.Account
import com.sanvya.app.data.repository.CategoryRow
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.ReceiptsRepository
import com.sanvya.app.data.repository.SplitGroup
import com.sanvya.app.data.repository.SplitsRepository
import com.sanvya.app.data.repository.TransactionItemInput
import com.sanvya.app.data.repository.UpdateScanDraftInput
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.receipts.ReceiptDraft
import com.sanvya.app.domain.receipts.ReceiptLine
import com.sanvya.app.domain.receipts.ReconcileResult
import com.sanvya.app.domain.receipts.Subtotals
import com.sanvya.app.domain.receipts.balanceWithLine
import com.sanvya.app.domain.receipts.reconcile
import com.sanvya.app.domain.receipts.subtotals
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * Real port of apps/web/app/receipts/review/page.tsx (task #62). See
 * docs/mobile/screen-specs/receipt-scan.md for the documented scope cut
 * (no category auto-suggest yet -- pairs with task #65; "Split this bill"
 * shown disabled -- pairs with task #63/64).
 *
 * Instantiated via the parameterless `viewModel()` factory; the scan id is
 * passed in via [load], matching GroupDetailViewModel/LoanDetailViewModel's
 * established convention.
 */
class ReceiptReviewViewModel : ViewModel(), KoinComponent {
    private val receiptsRepository: ReceiptsRepository by inject()
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()
    private val splitsRepository: SplitsRepository by inject()

    private var scanId: String = ""

    private val _draft = MutableStateFlow<ReceiptDraft?>(null)
    val draft: StateFlow<ReceiptDraft?> = _draft

    private val _accounts = MutableStateFlow<List<Account>>(emptyList())
    val accounts: StateFlow<List<Account>> = _accounts

    private val _categories = MutableStateFlow<List<CategoryRow>>(emptyList())
    val categories: StateFlow<List<CategoryRow>> = _categories

    private val _accountId = MutableStateFlow<String?>(null)
    val accountId: StateFlow<String?> = _accountId

    private val _categoryId = MutableStateFlow<String?>(null)
    val categoryId: StateFlow<String?> = _categoryId

    private val _loaded = MutableStateFlow(false)
    val loaded: StateFlow<Boolean> = _loaded

    private val _saving = MutableStateFlow(false)
    val saving: StateFlow<Boolean> = _saving

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private val _savedTransactionId = MutableStateFlow<String?>(null)
    val savedTransactionId: StateFlow<String?> = _savedTransactionId

    // ---- split ----

    /** "Just record it" vs "Split this bill". Web's `wantsSplit`. */
    private val _wantsSplit = MutableStateFlow(false)
    val wantsSplit: StateFlow<Boolean> = _wantsSplit

    private val _groups = MutableStateFlow<List<SplitGroup>>(emptyList())
    val groups: StateFlow<List<SplitGroup>> = _groups

    private val _groupId = MutableStateFlow("")
    val groupId: StateFlow<String> = _groupId

    private val _newGroupName = MutableStateFlow("")
    val newGroupName: StateFlow<String> = _newGroupName

    /**
     * Set once the group exists and the draft is saved — the screen navigates
     * to the split route on it. Web pushes `/receipts/split?...` at this point.
     */
    private val _splitGroupId = MutableStateFlow<String?>(null)
    val splitGroupId: StateFlow<String?> = _splitGroupId

    fun setWantsSplit(value: Boolean) { _wantsSplit.value = value }
    fun setGroupId(value: String) {
        _groupId.value = value
        if (value.isNotEmpty()) _newGroupName.value = ""
    }
    fun setNewGroupName(value: String) { _newGroupName.value = value }
    fun clearSplitTarget() { _splitGroupId.value = null }

    /**
     * Save the edited draft, make the group if it does not exist yet, and hand
     * the screen a group id to navigate with.
     *
     * The draft is written FIRST, deliberately: the split screen re-reads it
     * from `receipt_scans`, so any line the user fixed here has to be on disk
     * before we leave. Web does the same in `goToSplit`.
     */
    fun continueToSplit(pickGroupMessage: String) {
        val draft = _draft.value ?: return
        if (_saving.value) return
        _saving.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                val s = subtotals(draft.lines)
                receiptsRepository.updateScanDraft(
                    scanId,
                    UpdateScanDraftInput(
                        engine = draft.engine, merchant = draft.merchant, occurredAt = draft.occurredAt,
                        currency = draft.currency, subtotal = s.items, tax = s.tax, serviceCharge = s.serviceCharge,
                        tip = s.tip, discount = s.discount, total = draft.total, confidence = draft.confidence.toLong(),
                        parsedJson = draft.toJsonString(),
                    ),
                )
                var gid = _groupId.value
                val wanted = _newGroupName.value.trim()
                if (gid.isEmpty() && wanted.isNotEmpty()) {
                    val userId = authRepository.currentUserId.value ?: authRepository.ensureGuest()
                    gid = splitsRepository.createGroup(
                        userId = userId, name = wanted, kind = "group", currency = draft.currency,
                    )
                }
                if (gid.isEmpty()) {
                    _error.value = pickGroupMessage
                } else {
                    _splitGroupId.value = gid
                }
            } catch (e: Exception) {
                _error.value = e.message
            }
            _saving.value = false
        }
    }

    fun load(scanId: String) {
        if (this.scanId == scanId && _loaded.value) return
        this.scanId = scanId
        viewModelScope.launch {
            try {
                val row = receiptsRepository.get(scanId)
                val json = row?.parsedJson
                _draft.value = if (json != null) receiptDraftFromJsonString(json) else null
                if (_draft.value == null) _error.value = "We couldn't reopen this scan. Please scan it again."
            } catch (e: Exception) {
                _error.value = e.message ?: "We couldn't reopen this scan."
            }
            _loaded.value = true

            ledgerRepository.watchAccounts().onEach { list ->
                _accounts.value = list
                if (_accountId.value == null && list.isNotEmpty()) _accountId.value = list.first().id
            }.launchIn(viewModelScope)

            ledgerRepository.watchCategories().onEach { list ->
                _categories.value = list.filter { it.kind != "income" }
            }.launchIn(viewModelScope)

            // Real groups only. A direct (1:1) group is created BY a settle-up
            // and has no name of its own, so offering one here would put a
            // blank row in the picker -- watchGroups() excludes them by
            // default, same as web's useGroups().
            splitsRepository.watchGroups().onEach { _groups.value = it }.launchIn(viewModelScope)
        }
    }

    fun reconcileResult(): ReconcileResult? = _draft.value?.let { reconcile(it) }
    fun subtotalsResult(): Subtotals? = _draft.value?.let { subtotals(it.lines) }

    private fun patch(fn: (ReceiptDraft) -> ReceiptDraft) {
        _draft.value = _draft.value?.let(fn)
    }

    fun setMerchant(value: String) = patch { it.copy(merchant = value) }
    fun setOccurredAt(value: String) = patch { it.copy(occurredAt = value) }
    fun setTotal(minor: Long?) = patch { it.copy(total = minor) }
    fun setAccountId(id: String) { _accountId.value = id }
    fun setCategoryId(id: String?) { _categoryId.value = id }

    fun updateLine(lineId: String, fn: (ReceiptLine) -> ReceiptLine) = patch { d ->
        d.copy(lines = d.lines.map { if (it.id == lineId) fn(it) else it })
    }

    fun removeLine(lineId: String) = patch { d -> d.copy(lines = d.lines.filter { it.id != lineId }) }

    fun addLine(kind: String) = patch { d ->
        val line = ReceiptLine(
            id = "new-${System.currentTimeMillis()}",
            kind = kind,
            description = "",
            quantity = null,
            unit = null,
            unitPrice = null,
            amount = 0L,
            confidence = 100,
        )
        d.copy(lines = d.lines + line)
    }

    /** One-tap fix: "Add {delta} as a line". */
    fun addDifferenceAsLine() = patch { d -> balanceWithLine(d, "fix-${System.currentTimeMillis()}", "Unmatched") }

    /** One-tap fix: "Use {computed} as the total". */
    fun useComputedTotal() = patch { d -> adoptComputedTotal(d) }

    fun saveAsTransaction() {
        val draft = _draft.value ?: return
        val rec = reconcile(draft)
        val stated = rec.stated ?: return
        val accId = _accountId.value ?: return
        val userId = authRepository.currentUserId.value ?: return
        _saving.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                val s = subtotals(draft.lines)
                receiptsRepository.updateScanDraft(
                    scanId,
                    UpdateScanDraftInput(
                        engine = draft.engine, merchant = draft.merchant, occurredAt = draft.occurredAt,
                        currency = draft.currency, subtotal = s.items, tax = s.tax, serviceCharge = s.serviceCharge,
                        tip = s.tip, discount = s.discount, total = draft.total, confidence = draft.confidence.toLong(),
                        parsedJson = draft.toJsonString(),
                    ),
                )
                val cur = draft.currency
                val tx = ledgerRepository.createTransaction(
                    userId = userId,
                    accountId = accId,
                    type = "expense",
                    amount = money(stated, cur),
                    occurredAt = draft.occurredAt ?: java.time.Instant.now().toString(),
                    categoryId = _categoryId.value,
                    description = draft.merchant,
                    // Breakdown must sum EXACTLY to the transaction amount --
                    // reconciliation already proved it does, mirrors web's
                    // `describeItem` (fold qty/unit into the description since
                    // transaction_items has no qty column).
                    items = draft.lines.map { line ->
                        TransactionItemInput(describeItem(line.description, line.quantity, line.unit), money(line.amount, cur))
                    },
                )
                receiptsRepository.linkScan(scanId, transactionId = tx.id)
                _savedTransactionId.value = tx.id
            } catch (e: Exception) {
                _error.value = e.message ?: "Couldn't save this transaction."
            } finally {
                _saving.value = false
            }
        }
    }

    private fun describeItem(description: String, quantity: Long?, unit: String?): String {
        val name = description.trim().ifEmpty { "Item" }
        if (quantity == null) return name
        val q = quantity / 1000.0
        val qtyText = if (q == Math.floor(q)) q.toLong().toString() else String.format("%.3f", q).trimEnd('0').trimEnd('.')
        return if (unit != null) "$name ($qtyText $unit)" else "$name × $qtyText"
    }
}
