package com.sanvya.app.ui.transactions

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.Account
import com.sanvya.app.data.repository.CategoryRow
import com.sanvya.app.data.repository.LabelRow
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.PaymentMethodRow
import com.sanvya.app.data.repository.TransactionItemInput
import com.sanvya.app.domain.money.fromMajor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import com.sanvya.app.ui.FormOptions

data class EditTransactionUiState(
    val loaded: Boolean = false,
    val type: TxType = "expense",
    val accountId: String = "",
    val transferAmount: String = "",
    val items: List<TxItemDraft> = emptyList(),
    val categoryId: String? = null,
    val selectedLabels: List<String> = emptyList(),
    val paymentMethod: String = "",
    val note: String = "",
    val intent: String? = null,
    val currency: String = FormOptions.DEFAULT_CURRENCY,
    val occurredAt: LocalDateTime = LocalDateTime.now(),
    val saving: Boolean = false,
    val saved: Boolean = false,
    val confirmDelete: Boolean = false,
    val deleting: Boolean = false,
    val deleted: Boolean = false,
    val error: String? = null,
)

/** Edit transaction — ported from transactions/[id]/edit/page.tsx per
 * docs/mobile/screen-specs/transactions.md. Edit-history (the audit-log
 * modal) and the split-expense SplitBanner are explicitly deferred (see
 * spec's Scope section). SavedStateHandle for the transaction id nav arg +
 * KoinComponent, matches EditAccountViewModel's established pattern. */
class EditTransactionViewModel(
    private val savedStateHandle: SavedStateHandle,
) : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val transactionId: String = checkNotNull(savedStateHandle["transactionId"]) { "EditTransactionViewModel needs a transactionId nav arg" }

    private val ui = MutableStateFlow(EditTransactionUiState())
    val uiState: StateFlow<EditTransactionUiState> = ui.asStateFlow()

    val accounts: StateFlow<List<Account>> = ledgerRepository.watchAccounts(includeArchived = true)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val categories: StateFlow<List<CategoryRow>> = ledgerRepository.watchCategories()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val labels: StateFlow<List<LabelRow>> = ledgerRepository.watchLabels()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    private val paymentMethods: StateFlow<List<PaymentMethodRow>> = ledgerRepository.watchPaymentMethods()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val account: StateFlow<Account?> = combine(accounts, ui) { accts, state -> accts.find { it.id == state.accountId } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    val relevantCategories: StateFlow<List<CategoryRow>> = combine(categories, ui) { cats, state ->
        val kind = if (state.type == "income") "income" else "expense"
        cats.filter { it.kind == kind }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val relevantPaymentMethods: StateFlow<List<PaymentMethodRow>> = combine(paymentMethods, account) { methods, acct ->
        methods.filter { it.accountTypeId == acct?.type }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    init {
        viewModelScope.launch {
            combine(
                ledgerRepository.watchAllTransactions().map { list -> list.find { it.id == transactionId } },
                ledgerRepository.watchTransactionLabelNames(),
            ) { txn, labelMap -> txn to (labelMap[transactionId] ?: emptyList()) }
                .collect { (txn, labelNames) ->
                    if (txn == null || ui.value.loaded) return@collect
                    val items = try {
                        ledgerRepository.items(transactionId)
                    } catch (e: Exception) {
                        emptyList()
                    }
                    val itemDrafts = if (items.isNotEmpty()) {
                        items.map { TxItemDraft(id = it.id, description = it.description, value = (it.amount / 100.0).toString()) }
                    } else {
                        listOf(TxItemDraft(id = "new_${System.currentTimeMillis()}", description = txn.description ?: "", value = (txn.amount / 100.0).toString()))
                    }
                    ui.value = ui.value.copy(
                        loaded = true,
                        type = txn.type,
                        accountId = txn.accountId,
                        transferAmount = (txn.amount / 100.0).toString(),
                        items = itemDrafts,
                        categoryId = txn.categoryId,
                        selectedLabels = labelNames,
                        paymentMethod = txn.paymentMethod ?: "",
                        note = txn.note ?: "",
                        intent = txn.intent,
                        currency = txn.currency,
                        occurredAt = try {
                            Instant.parse(txn.occurredAt).atZone(ZoneId.systemDefault()).toLocalDateTime()
                        } catch (e: Exception) {
                            LocalDateTime.now()
                        },
                    )
                }
        }
    }

    fun setType(v: TxType) { ui.value = ui.value.copy(type = v) }
    fun setAccountId(v: String) { ui.value = ui.value.copy(accountId = v) }
    fun setTransferAmount(v: String) { ui.value = ui.value.copy(transferAmount = v) }
    fun setCategoryId(v: String?) { ui.value = ui.value.copy(categoryId = v) }
    fun setPaymentMethod(v: String) { ui.value = ui.value.copy(paymentMethod = v) }
    fun setNote(v: String) { ui.value = ui.value.copy(note = v) }
    fun setIntent(v: String?) { ui.value = ui.value.copy(intent = v) }
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
            if (it.id != id) it else it.copy(description = description ?: it.description, value = value ?: it.value)
        })
    }
    fun addItem() { ui.value = ui.value.copy(items = ui.value.items + TxItemDraft(id = "new_${System.currentTimeMillis()}", description = "", value = "")) }
    fun removeItem(id: String) { ui.value = ui.value.copy(items = ui.value.items.filterNot { it.id == id }) }
    fun setConfirmDelete(v: Boolean) { ui.value = ui.value.copy(confirmDelete = v) }

    /** Matches transactions/[id]/edit/page.tsx's save() exactly. */
    fun save() {
        val state = ui.value
        val userId = authRepository.currentUserId.value ?: return
        ui.value = ui.value.copy(saving = true, error = null)
        viewModelScope.launch {
            try {
                val patch = mutableMapOf<String, Any?>(
                    "type" to state.type,
                    "account_id" to state.accountId,
                    "payment_method" to state.paymentMethod.ifEmpty { null },
                    "note" to state.note.trim().ifEmpty { null },
                    "occurred_at" to state.occurredAt.atZone(ZoneId.systemDefault()).toInstant().toString(),
                )
                if (state.type == "transfer") {
                    patch["amount"] = Math.round((state.transferAmount.toDoubleOrNull() ?: 0.0) * 100)
                    patch["category_id"] = null
                    patch["description"] = null
                    // Explicit clear, not "don't touch" -- matches web sending
                    // `items: null` for transfers (handles editing a
                    // transaction from expense/income, which may have had
                    // breakdown items, into a transfer).
                    patch["items"] = null
                } else {
                    val nonZero = state.items.filter { (it.value.toDoubleOrNull() ?: 0.0) > 0 }
                    val total = nonZero.sumOf { Math.round((it.value.toDoubleOrNull() ?: 0.0) * 100) }
                    patch["amount"] = total
                    patch["category_id"] = state.categoryId
                    patch["description"] = nonZero.joinToString(", ") { it.description.trim() }.ifEmpty { null }
                    patch["items"] = if (nonZero.size > 1) {
                        nonZero.mapIndexed { i, it ->
                            TransactionItemInput(
                                description = it.description.trim().ifEmpty { "Item ${i + 1}" },
                                amount = fromMajor(it.value.toDoubleOrNull() ?: 0.0, state.currency),
                            )
                        }
                    } else emptyList<TransactionItemInput>()
                }
                patch["labels"] = state.selectedLabels
                if (state.type == "expense") patch["intent"] = state.intent
                ledgerRepository.updateTransaction(userId, transactionId, patch)
                ui.value = ui.value.copy(saving = false, saved = true)
            } catch (e: Exception) {
                ui.value = ui.value.copy(saving = false, error = e.message ?: "Couldn't save changes")
            }
        }
    }

    /** Matches transactions/[id]/edit/page.tsx's delete() -- single confirm,
     * soft-deletes the transaction (+ its items/labels, already handled by
     * removeTransaction) in one step, no cascade choice (unlike Accounts). */
    fun delete() {
        val userId = authRepository.currentUserId.value ?: return
        ui.value = ui.value.copy(deleting = true)
        viewModelScope.launch {
            try {
                ledgerRepository.removeTransaction(userId, transactionId)
                ui.value = ui.value.copy(deleting = false, deleted = true)
            } catch (e: Exception) {
                ui.value = ui.value.copy(deleting = false, error = e.message ?: "Couldn't delete this transaction")
            }
        }
    }
}
