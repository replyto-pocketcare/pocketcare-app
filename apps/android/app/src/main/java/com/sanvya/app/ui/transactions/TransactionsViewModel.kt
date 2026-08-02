package com.sanvya.app.ui.transactions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.Account
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.TransactionRow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import java.text.NumberFormat
import java.util.Locale
import java.time.format.DateTimeFormatter
import java.time.OffsetDateTime
import java.time.ZoneId

data class TransactionUiModel(
    val id: String,
    val description: String,
    val amount: String,
    val date: String,
    val accountName: String,
    val categoryName: String,
    val isIncome: Boolean = false
)

class TransactionsViewModel(
    private val ledgerRepository: LedgerRepository
) : ViewModel() {

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 2
    }

    val transactions: StateFlow<List<TransactionUiModel>> = combine(
        ledgerRepository.watchAllTransactions(),
        ledgerRepository.watchAccounts(includeArchived = true)
    ) { txns, accounts ->
        val accountMap = accounts.associateBy { it.id }
        txns.map { txn ->
            val isIncome = txn.type == "income"
            val sign = if (isIncome) "+" else "-"
            val amt = (txn.amount / 100.0)
            val account = accountMap[txn.accountId]
            
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
                categoryName = "General", // Placeholder until categories are added
                isIncome = isIncome
            )
        }
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = emptyList()
    )
}
