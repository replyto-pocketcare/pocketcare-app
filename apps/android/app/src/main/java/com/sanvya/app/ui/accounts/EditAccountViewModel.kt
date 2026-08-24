package com.sanvya.app.ui.accounts

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.domain.money.Money
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.money.money
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.Instant
import com.sanvya.app.ui.formatMoneyAware

/** Persisted ledger text, stays English by design -- matches
 * accounts/[id]/edit/page.tsx's ADJUSTMENT_TITLE exactly (data, not UI
 * chrome; must read the same in exports/support views on every platform). */
private const val ADJUSTMENT_TITLE = "Account Balance Adjustment record"

data class EditAccountUiState(
    val loaded: Boolean = false,
    val name: String = "",
    val type: String = "savings",
    val color: String = ACCOUNT_COLOR_HEX.first(),
    val includeInNetWorth: Boolean = true,
    val allowNegative: Boolean = false,
    val currentBalanceFormatted: String = "…",
    val currentBalance: Money? = null,
    val targetBalance: String = "",
    val balanceMode: BalanceMode = BalanceMode.Direct,
    val balanceMessage: String? = null,
    val confirmDelete: Boolean = false,
    val deleting: Boolean = false,
    val saved: Boolean = false,
    val archived: Boolean = false,
    val deleted: Boolean = false,
)

enum class BalanceMode { Direct, Transaction }

/** No-arg + SavedStateHandle for the account id (nav-graph arg) + KoinComponent,
 * consistent with this codebase's established ViewModel patterns. */
class EditAccountViewModel(
    private val savedStateHandle: SavedStateHandle,
) : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val accountId: String = checkNotNull(savedStateHandle["accountId"]) { "EditAccountViewModel needs an accountId nav arg" }

    private val form = MutableStateFlow<FormEdits?>(null) // null until the loaded row seeds it
    private val ui = MutableStateFlow(EditAccountUiState())

    val uiState: StateFlow<EditAccountUiState> = ui.asStateFlow()

    private data class FormEdits(
        val name: String,
        val type: String,
        val color: String,
        val includeInNetWorth: Boolean,
        val allowNegative: Boolean,
    )

    init {
        viewModelScope.launch {
            combine(
                ledgerRepository.watchAccount(accountId),
                ledgerRepository.watchAccountBalances(includeArchived = true),
                form,
            ) { account, balances, edits -> Triple(account, balances, edits) }
                .collect { (account, balances, edits) ->
                    if (account == null) return@collect
                    val balance = balances.find { it.account.id == accountId }?.balance
                    val seeded = edits ?: FormEdits(
                        name = account.name,
                        type = account.type,
                        color = account.color ?: ACCOUNT_COLOR_HEX.first(),
                        includeInNetWorth = account.includeInNetWorth,
                        allowNegative = account.allowNegative,
                    ).also { form.value = it }
                    ui.value = ui.value.copy(
                        loaded = true,
                        name = seeded.name,
                        type = seeded.type,
                        color = seeded.color,
                        includeInNetWorth = seeded.includeInNetWorth,
                        allowNegative = seeded.allowNegative,
                        currentBalance = balance,
                        currentBalanceFormatted = balance?.let { formatMoneyAware(it) } ?: "…",
                        archived = account.isArchived,
                    )
                }
        }
    }

    fun setName(v: String) = editForm { it.copy(name = v) }
    fun setType(v: String) = editForm { it.copy(type = v) }
    fun setColor(v: String) = editForm { it.copy(color = v) }
    fun setIncludeInNetWorth(v: Boolean) = editForm { it.copy(includeInNetWorth = v) }
    fun setAllowNegative(v: Boolean) = editForm { it.copy(allowNegative = v) }

    private fun editForm(f: (FormEdits) -> FormEdits) {
        val current = form.value ?: return
        val next = f(current)
        form.value = next
        ui.value = ui.value.copy(
            name = next.name, type = next.type, color = next.color,
            includeInNetWorth = next.includeInNetWorth, allowNegative = next.allowNegative,
        )
    }

    fun setTargetBalance(v: String) {
        ui.value = ui.value.copy(targetBalance = v.filter { it.isDigit() || it == '.' || it == '-' }, balanceMessage = null)
    }

    fun setBalanceMode(mode: BalanceMode) {
        ui.value = ui.value.copy(balanceMode = mode)
    }

    fun setConfirmDelete(v: Boolean) {
        ui.value = ui.value.copy(confirmDelete = v)
    }

    fun save() {
        val edits = form.value ?: return
        viewModelScope.launch {
            ledgerRepository.updateAccount(
                accountId,
                mapOf(
                    "name" to edits.name.trim(),
                    "type" to edits.type,
                    "color" to edits.color,
                    "include_in_net_worth" to if (edits.includeInNetWorth) 1L else 0L,
                    "allow_negative" to if (edits.allowNegative) 1L else 0L,
                ),
            )
            ui.value = ui.value.copy(saved = true)
        }
    }

    /** Matches accounts/[id]/edit/page.tsx's deleteAccount(cascade) exactly:
     * cascade soft-deletes the account's transactions first, then the
     * account; "keep" soft-deletes only the account. */
    fun delete(cascade: Boolean) {
        ui.value = ui.value.copy(deleting = true)
        viewModelScope.launch {
            try {
                if (cascade) ledgerRepository.cascadeDeleteAccountTransactions(accountId)
                ledgerRepository.deleteAccount(accountId)
                ui.value = ui.value.copy(deleting = false, deleted = true)
            } catch (e: Exception) {
                e.printStackTrace()
                ui.value = ui.value.copy(deleting = false)
            }
        }
    }

    /** Matches accounts/[id]/edit/page.tsx's applyBalance() exactly: delta =
     * target - current (minor units); "direct" writes a no-category
     * `adjustment` transaction, "transaction" writes a real income/expense
     * sized to |delta|. Both use ADJUSTMENT_TITLE as the description
     * (persisted ledger text -- stays English, never localized). */
    fun applyBalance() {
        val state = ui.value
        val current = state.currentBalance ?: return
        val targetMajor = state.targetBalance.toDoubleOrNull() ?: return
        val userId = authRepository.currentUserId.value ?: return
        val target = fromMajor(targetMajor, current.currency)
        val delta = target.amount - current.amount
        if (delta == 0L) {
            ui.value = ui.value.copy(balanceMessage = "Already at that balance")
            return
        }
        viewModelScope.launch {
            val now = Instant.now().toString()
            if (state.balanceMode == BalanceMode.Direct) {
                ledgerRepository.createTransaction(
                    userId = userId, accountId = accountId, type = "adjustment",
                    amount = money(delta, current.currency), occurredAt = now,
                    note = "Balance adjustment", description = ADJUSTMENT_TITLE,
                )
            } else {
                ledgerRepository.createTransaction(
                    userId = userId, accountId = accountId,
                    type = if (delta > 0) "income" else "expense",
                    amount = money(Math.abs(delta), current.currency), occurredAt = now,
                    note = "Balance adjustment", description = ADJUSTMENT_TITLE,
                )
            }
            ui.value = ui.value.copy(
                balanceMessage = "Balance updated to ${formatMoneyAware(target)}",
                targetBalance = "",
            )
        }
    }
}
