package com.sanvya.app.ui.accounts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.SettingsRepository
import com.sanvya.app.ui.components.initialSyncPending
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import com.sanvya.app.ui.formatMoneyAware

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
    /**
     * False on the seed value only. Web's `useAccountsLoading()` exists for the
     * same reason: a list of no accounts that has not been read yet is not a
     * list of no accounts.
     */
    val loaded: Boolean = false,
)

/** No-arg + KoinComponent, matches DashboardViewModel/SettingsViewModel's
 * established pattern (docs/mobile/screen-specs/dashboard.md's "no Koin
 * viewModel-DSL module needed" note). */
class AccountsViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val settingsRepository: SettingsRepository by inject()

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
                balance = formatMoneyAware(acctWithBal.balance),
                isArchived = acct.isArchived,
                allowNegative = acct.allowNegative,
                includeInNetWorth = acct.includeInNetWorth,
            )
        }
        val archivedCount = all.count { it.isArchived }
        val visible = if (showArch) all else all.filterNot { it.isArchived }
        AccountsUiState(visible = visible, archivedCount = archivedCount, showArchived = showArch, loaded = true)
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = AccountsUiState(),
    )

    /**
     * Show card skeletons rather than "no accounts yet".
     *
     * Web's guard is `balances.length === 0 && (accountsLoading || syncPending)`.
     * The half that matters is `syncPending`: on a returning user's first
     * launch the local database is empty because the accounts are still
     * downloading, and this screen told them they had none -- which for an
     * accounts list reads as "your money is gone", not as "still loading".
     */
    val showSkeleton: StateFlow<Boolean> = combine(
        uiState,
        initialSyncPending(settingsRepository),
    ) { state, syncPending ->
        !state.loaded || syncPending
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

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
