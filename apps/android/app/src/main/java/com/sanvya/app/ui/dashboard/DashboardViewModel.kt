package com.sanvya.app.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.AccountWithBalance
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.NetWorth
import com.sanvya.app.data.repository.TransactionRow
import com.sanvya.app.domain.money.money
import com.sanvya.app.ui.transactions.TransactionUiModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import java.text.NumberFormat
import java.util.Locale
import java.time.format.DateTimeFormatter
import java.time.OffsetDateTime
import java.time.ZoneId

data class DashboardUiState(
    val netWorthFormatted: String = "₹0.00",
    val assetsFormatted: String = "₹0.00",
    val liabilitiesFormatted: String = "₹0.00",
    val accounts: List<AccountWithBalance> = emptyList(),
    val recentTransactions: List<TransactionUiModel> = emptyList()
)

class DashboardViewModel(
    private val ledgerRepository: LedgerRepository
) : ViewModel() {

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 2
    }

    val uiState: StateFlow<DashboardUiState> = combine(
        ledgerRepository.watchNetWorth("INR"),
        ledgerRepository.watchAccountBalances(includeArchived = false),
        ledgerRepository.watchRecentTransactions(limit = 10)
    ) { netWorth, accounts, txns ->
        val accountMap = accounts.associateBy { it.account.id }
        
        val recentUiTxns = txns.map { txn ->
            val isIncome = txn.type == "income"
            val sign = if (isIncome) "+" else "-"
            val amt = (txn.amount / 100.0)
            val account = accountMap[txn.accountId]?.account
            
            val formattedDate = try {
                val odt = OffsetDateTime.parse(txn.occurredAt)
                val zdt = odt.atZoneSameInstant(ZoneId.systemDefault())
                val today = OffsetDateTime.now().atZoneSameInstant(ZoneId.systemDefault())
                if (zdt.toLocalDate() == today.toLocalDate()) {
                    "Today"
                } else if (zdt.toLocalDate() == today.toLocalDate().minusDays(1)) {
                    "Yesterday"
                } else {
                    zdt.format(DateTimeFormatter.ofPattern("dd MMM"))
                }
            } catch (e: Exception) {
                txn.occurredAt.take(10)
            }

            TransactionUiModel(
                id = txn.id,
                description = txn.description ?: txn.note ?: "Transaction",
                amount = "$sign${numberFormat.format(amt)}",
                date = formattedDate,
                accountName = account?.name ?: "Unknown Account",
                categoryName = "General",
                isIncome = isIncome
            )
        }

        // Net worth formatting
        val assets = accounts.filter { it.balance.amount > 0 && it.account.includeInNetWorth }
            .sumOf { it.balance.amount }
        val liabilities = accounts.filter { it.balance.amount < 0 && it.account.includeInNetWorth }
            .sumOf { it.balance.amount }

        DashboardUiState(
            netWorthFormatted = numberFormat.format(netWorth.total.amount / 100.0),
            assetsFormatted = numberFormat.format(assets / 100.0),
            liabilitiesFormatted = numberFormat.format(Math.abs(liabilities) / 100.0),
            accounts = accounts,
            recentTransactions = recentUiTxns
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = DashboardUiState()
    )
}
