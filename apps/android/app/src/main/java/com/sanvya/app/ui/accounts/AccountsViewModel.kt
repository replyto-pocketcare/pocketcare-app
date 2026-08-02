package com.sanvya.app.ui.accounts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LedgerRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import java.text.NumberFormat
import java.util.Locale

data class AccountUiModel(
    val id: String,
    val name: String,
    val type: String,
    val currency: String,
    val balance: String,
    val isArchived: Boolean = false,
    val allowNegative: Boolean = false,
    val includeInNetWorth: Boolean = true
)

class AccountsViewModel(
    private val ledgerRepository: LedgerRepository
) : ViewModel() {

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 2
    }

    val accounts: StateFlow<List<AccountUiModel>> = ledgerRepository.watchAccountBalances(includeArchived = true)
        .map { balances ->
            balances.map { acctWithBal ->
                val acct = acctWithBal.account
                val amt = acctWithBal.balance.amount / 100.0
                
                AccountUiModel(
                    id = acct.id,
                    name = acct.name,
                    type = acct.type,
                    currency = acct.currency,
                    balance = numberFormat.format(amt),
                    isArchived = acct.isArchived,
                    allowNegative = acct.allowNegative,
                    includeInNetWorth = acct.includeInNetWorth
                )
            }
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = emptyList()
        )
}
