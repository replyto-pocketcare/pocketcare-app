package com.sanvya.app.ui.transactions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.TransactionRow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/** Type filter chips -- matches transactions/page.tsx's TYPES exactly. */
val TX_TYPE_FILTERS = listOf("all", "income", "expense", "transfer")



/** No-arg + KoinComponent, matches AccountsViewModel/DashboardViewModel's
 * established pattern -- previous version took `LedgerRepository` as a
 * constructor arg, which the default `viewModel()` factory can't satisfy
 * (same class of dangling-reference bug found + fixed elsewhere this
 * session; there was no TransactionsScreen.kt to ever surface it). */
class TransactionsViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    val query = MutableStateFlow("")
    val typeFilter = MutableStateFlow("all")

    fun setQuery(v: String) { query.value = v }
    fun setTypeFilter(v: String) { typeFilter.value = v }

    private data class Source(
        val txns: List<TransactionRow>,
        val accounts: List<com.sanvya.app.data.repository.Account>,
        val categories: List<com.sanvya.app.data.repository.CategoryRow>,
        val labelNames: Map<String, List<String>>,
    )

    private val source: StateFlow<Source> = combine(
        ledgerRepository.watchAllTransactions(),
        ledgerRepository.watchAccounts(includeArchived = true),
        ledgerRepository.watchCategories(),
        ledgerRepository.watchTransactionLabelNames(),
    ) { txns, accounts, categories, labelNames -> Source(txns, accounts, categories, labelNames) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = Source(emptyList(), emptyList(), emptyList(), emptyMap()),
        )

    /** Matches transactions/page.tsx's query: excludes opening_balance rows,
     * filters by note/label search text and type, newest first, capped at
     * 200 -- done client-side over the reactive local rows rather than a
     * per-keystroke parameterized SQL watch (simpler, same effective result
     * for a local offline cache of this size). */
    val items: StateFlow<List<TransactionListItem>> = combine(
        source, query, typeFilter,
    ) { (txns, accounts, categories, labelNames), q, ty ->
        val accountMap = accounts.associateBy { it.id }
        val categoryMap = categories.associateBy { it.id }
        val needle = q.trim().lowercase()

        txns
            .asSequence()
            .filter { it.type != "opening_balance" }
            .filter { ty == "all" || it.type == ty }
            .filter { txn ->
                if (needle.isEmpty()) return@filter true
                val noteHit = txn.note?.lowercase()?.contains(needle) == true
                val labelHit = (labelNames[txn.id] ?: emptyList()).any { it.lowercase().contains(needle) }
                noteHit || labelHit
            }
            .sortedByDescending { it.occurredAt }
            .take(200)
            .map { txn -> transactionListItem(txn, accountMap, categoryMap, labelNames[txn.id]) }
            .toList()
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = emptyList(),
    )

}
