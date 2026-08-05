package com.sanvya.app.ui.accounts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LedgerRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.text.NumberFormat
import java.util.Locale

data class AccountUiModel(
    val id: String,
    val name: String,
    val type: String,
    val currency: String,
    val color: String?,
    val balance: String,
    val isArchived: Boolean = false,
    val allowNegative: Boolean = false,
    val includeInNetWorth: Boolean = true
)

data class AccountsUiState(
    val visible: List<AccountUiModel> = emptyList(),
    val archivedCount: Int = 0,
    val showArchived: Boolean = false,
)

/** No-arg + KoinComponent, matches DashboardViewModel/SettingsViewModel's
 * established pattern (docs/mobile/screen-specs/dashboard.md's "no Koin
 * viewModel-DSL module needed" note). */
class AccountsViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 2
    }

    private val showArchived = MutableStateFlow(false)

    fun toggleShowArchived() {
        showArchived.value = !showArchived.value
    }

    val uiState: StateFlow<AccountsUiState> = combine(
        ledgerRepository.watchAccountBalances(includeArchived = true),
        showArchived,
    ) { balances, showArch ->
        val all = balances.map { acctWithBal ->
            val acct = acctWithBal.account
            AccountUiModel(
                id = acct.id,
                name = acct.name,
                type = acct.type,
                currency = acct.currency,
                color = acct.color,
                balance = numberFormat.format(acctWithBal.balance.amount / 100.0),
                isArchived = acct.isArchived,
                allowNegative = acct.allowNegative,
                includeInNetWorth = acct.includeInNetWorth,
            )
        }
        val archivedCount = all.count { it.isArchived }
        val visible = if (showArch) all else all.filterNot { it.isArchived }
        AccountsUiState(visible = visible, archivedCount = archivedCount, showArchived = showArch)
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = AccountsUiState(),
    )

    /** Matches accounts/page.tsx's toggleNw() exactly (direct SQL update, no
     * confirmation). Boolean columns are stored as INTEGER 0/1 -- pass Long,
     * not a raw Kotlin Boolean, matching setAccountArchived()'s existing
     * convention in LedgerRepository.kt (accountMapper reads it back via
     * getBooleanOptional). */
    fun toggleIncludeInNetWorth(id: String, current: Boolean) {
        viewModelScope.launch {
            ledgerRepository.updateAccount(id, mapOf("include_in_net_worth" to if (!current) 1L else 0L))
        }
    }

    fun setArchived(id: String, archived: Boolean) {
        viewModelScope.launch {
            ledgerRepository.setAccountArchived(id, archived)
        }
    }
}
