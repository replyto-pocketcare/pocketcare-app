package com.sanvya.app.ui.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.Account
import com.sanvya.app.data.repository.CategoryRow
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.TransactionRow
import com.sanvya.app.domain.search.SearchCriteria
import com.sanvya.app.domain.search.SearchRow
import com.sanvya.app.domain.search.searchTransactions
import com.sanvya.app.domain.splits.SplitInfo
import com.sanvya.app.domain.splits.collapseSplitRowIds
import com.sanvya.app.domain.splits.splitInfoByTransaction
import com.sanvya.app.ui.transactions.TransactionListItem
import com.sanvya.app.ui.transactions.transactionListItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/** What the screen shows once the filter has run. */
data class SearchState(
    val items: List<TransactionListItem> = emptyList(),
    /**
     * Web counts the FILTERED rows, before collapse -- so two postings of one
     * split expense count as two here and render as one row below. Copied
     * deliberately: the count answers "how much matched", not "how many rows".
     */
    val resultCount: Int = 0,
    val accounts: List<Account> = emptyList(),
)

/**
 * Search -- ported from apps/web/app/search/page.tsx.
 *
 * The filter itself is `domain.search.searchTransactions`, vector-tested
 * against a reference implementation of web's `useMemo`. This view model's
 * whole job is to keep the six live queries that feed it and to turn the
 * surviving rows into the SAME [TransactionListItem] the Transactions list and
 * the dashboard tile render -- web renders the same `<TransactionTile>` on all
 * three, and a third row builder here is the re-inlining the component
 * inventory exists to prevent.
 *
 * Mirrors apps/ios/App/ViewModels/SearchViewModel.swift.
 */
class SearchViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    private val _criteria = MutableStateFlow(SearchCriteria())
    val criteria: StateFlow<SearchCriteria> = _criteria.asStateFlow()

    private val _showFilters = MutableStateFlow(false)
    val showFilters: StateFlow<Boolean> = _showFilters.asStateFlow()

    fun setQuery(v: String) { _criteria.value = _criteria.value.copy(query = v) }
    fun setType(v: String) { _criteria.value = _criteria.value.copy(type = v) }
    fun setAccountId(v: String) { _criteria.value = _criteria.value.copy(accountId = v) }
    fun setFrom(v: String) { _criteria.value = _criteria.value.copy(from = v) }
    fun setTo(v: String) { _criteria.value = _criteria.value.copy(to = v) }
    fun setMin(v: String) { _criteria.value = _criteria.value.copy(min = v) }
    fun setMax(v: String) { _criteria.value = _criteria.value.copy(max = v) }
    fun toggleFilters() { _showFilters.value = !_showFilters.value }

    /** Clears every filter but keeps what was typed -- web's `clearFilters`. */
    fun clearFilters() { _criteria.value = SearchCriteria(query = _criteria.value.query) }

    private data class Source(
        val txns: List<TransactionRow>,
        val accounts: List<Account>,
        val categories: List<CategoryRow>,
        val labelNames: Map<String, List<String>>,
        val splitInfo: Map<String, SplitInfo>,
    )

    private val source: StateFlow<Source> = combine(
        ledgerRepository.watchSearchTransactions(),
        ledgerRepository.watchAccounts(includeArchived = true),
        ledgerRepository.watchCategories(),
        ledgerRepository.watchTransactionLabelNames(),
        ledgerRepository.watchSplitPostings(),
    ) { txns, accounts, categories, labelNames, postings ->
        Source(txns, accounts, categories, labelNames, splitInfoByTransaction(postings))
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = Source(emptyList(), emptyList(), emptyList(), emptyMap(), emptyMap()),
    )

    /**
     * The repository returns one row per (account type, method) pairing, so the
     * same method arrives several times. Only the id -> label mapping is wanted
     * here, and it is the same in every pairing.
     */
    private val methodLabels: StateFlow<Map<String, String>> =
        ledgerRepository.watchPaymentMethods()
            .map { methods -> methods.associate { it.id to it.label } }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyMap())

    val state: StateFlow<SearchState> = combine(
        source, methodLabels, _criteria,
    ) { (txns, accounts, categories, labelNames, splitInfo), methods, criteria ->
        val accountMap = accounts.associateBy { it.id }
        val categoryMap = categories.associateBy { it.id }

        val rows = txns.map { txn ->
            val account = accountMap[txn.accountId]
            SearchRow(
                id = txn.id,
                type = txn.type,
                accountId = txn.accountId,
                toAccountId = txn.toAccountId,
                occurredAt = txn.occurredAt,
                amountMinor = txn.amount,
                currency = txn.currency,
                labels = labelNames[txn.id]?.joinToString(", "),
                note = txn.note,
                description = txn.description,
                methodLabel = txn.paymentMethod?.let { methods[it] },
                categoryName = txn.categoryId?.let { categoryMap[it]?.name },
                accountName = account?.name,
                accountType = account?.type,
            )
        }

        val matched = searchTransactions(rows, criteria)
        val byId = txns.associateBy { it.id }
        SearchState(
            items = collapseSplitRowIds(matched.map { it.id }, splitInfo).mapNotNull { id ->
                byId[id]?.let { txn ->
                    transactionListItem(txn, accountMap, categoryMap, labelNames[id], splitInfo[id])
                }
            },
            resultCount = matched.size,
            accounts = accounts,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), SearchState())
}
