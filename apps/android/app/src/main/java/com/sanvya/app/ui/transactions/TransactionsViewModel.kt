package com.sanvya.app.ui.transactions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.TransactionRow
import com.sanvya.app.domain.splits.SplitInfo
import com.sanvya.app.domain.splits.collapseSplitRowIds
import com.sanvya.app.domain.splits.splitInfoByTransaction
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
        val splitInfo: Map<String, SplitInfo>,
    )

    private val source: StateFlow<Source> = combine(
        ledgerRepository.watchAllTransactions(),
        ledgerRepository.watchAccounts(includeArchived = true),
        ledgerRepository.watchCategories(),
        ledgerRepository.watchTransactionLabelNames(),
        ledgerRepository.watchSplitPostings(),
    ) { txns, accounts, categories, labelNames, postings ->
        Source(txns, accounts, categories, labelNames, splitInfoByTransaction(postings))
    }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = Source(emptyList(), emptyList(), emptyList(), emptyMap(), emptyMap()),
        )

    /** Matches transactions/page.tsx's query: excludes opening_balance rows,
     * filters by note/label search text and type, newest first, capped at
     * 200 -- done client-side over the reactive local rows rather than a
     * per-keystroke parameterized SQL watch (simpler, same effective result
     * for a local offline cache of this size). */
    val items: StateFlow<List<TransactionListItem>> = combine(
        source, query, typeFilter,
    ) { (txns, accounts, categories, labelNames, splitInfo), q, ty ->
        val accountMap = accounts.associateBy { it.id }
        val categoryMap = categories.associateBy { it.id }
        val needle = q.trim().lowercase()

        val page = txns
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
            .toList()

        // Collapse AFTER the cap, which is web's order: it queries with
        // `LIMIT 200` and collapses the page it got back. Collapsing first
        // would let a page of split siblings pull older rows into view and make
        // the list's length depend on how many splits it happened to contain.
        //
        // This was missing until 2026-08-26. A split expense writes up to three
        // ledger rows, so this list showed one dinner as three lines with three
        // different amounts, where the browser has always shown one.
        val byId = page.associateBy { it.id }
        collapseSplitRowIds(page.map { it.id }, splitInfo).mapNotNull { id ->
            byId[id]?.let { txn ->
                transactionListItem(txn, accountMap, categoryMap, labelNames[id], splitInfo[id])
            }
        }
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = emptyList(),
    )

}
