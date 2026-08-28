package com.sanvya.app.ui.transactions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.ReceiptsRepository
import com.sanvya.app.data.repository.SettingsRepository
import com.sanvya.app.data.repository.TransactionRow
import com.sanvya.app.domain.splits.SplitInfo
import com.sanvya.app.domain.splits.collapseSplitRowIds
import com.sanvya.app.domain.splits.splitInfoByTransaction
import com.sanvya.app.ui.components.initialSyncPending
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
    private val receiptsRepository: ReceiptsRepository by inject()
    private val settingsRepository: SettingsRepository by inject()

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
        /**
         * False on the seed value only. It is web's `isLoading` from
         * `useQuery`, and the list needs it for the same reason: an empty list
         * that has not been read yet is not an empty list.
         */
        val loaded: Boolean = false,
    )

    private val source: StateFlow<Source> = combine(
        ledgerRepository.watchAllTransactions(),
        ledgerRepository.watchAccounts(includeArchived = true),
        ledgerRepository.watchCategories(),
        ledgerRepository.watchTransactionLabelNames(),
        ledgerRepository.watchSplitPostings(),
    ) { txns, accounts, categories, labelNames, postings ->
        Source(txns, accounts, categories, labelNames, splitInfoByTransaction(postings), loaded = true)
    }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = Source(emptyList(), emptyList(), emptyList(), emptyMap(), emptyMap()),
        )

    /**
     * Transactions a receipt photo created -- the "Scanned" chip.
     *
     * Web's `useScannedTransactionIds()`, which neither phone ever called:
     * `receipt_scans.transaction_id` was written on save and then never read
     * back, so a scanned bill was indistinguishable from a hand-typed one.
     *
     * Its own flow rather than a sixth member of [Source] because `combine`
     * tops out at five typed sources, and because it changes on a different
     * cadence from the ledger.
     */
    private val scannedIds: StateFlow<Set<String>> = receiptsRepository.watchScannedTransactionIds()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptySet())

    /**
     * Show skeletons rather than "no matching transactions".
     *
     * Web's guard is `rows.length > 0 ? list : (rowsLoading || syncPending) ?
     * skeletons : empty`, and the misleading half is the one that matters: for
     * the first seconds of a returning user's first launch the local database
     * is empty because the data is still downloading, and this list told them
     * they had none.
     */
    val showSkeleton: StateFlow<Boolean> = combine(
        source,
        initialSyncPending(settingsRepository),
    ) { src, syncPending ->
        !src.loaded || syncPending
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    /** Matches transactions/page.tsx's query: excludes opening_balance rows,
     * filters by note/label search text and type, newest first, capped at
     * 200 -- done client-side over the reactive local rows rather than a
     * per-keystroke parameterized SQL watch (simpler, same effective result
     * for a local offline cache of this size). */
    val items: StateFlow<List<TransactionListItem>> = combine(
        source, scannedIds, query, typeFilter,
    ) { src, scanned, q, ty ->
        val (txns, accounts, categories, labelNames, splitInfo) = src
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
                transactionListItem(
                    txn, accountMap, categoryMap, labelNames[id], splitInfo[id],
                    scanned = scanned.contains(id),
                )
            }
        }
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = emptyList(),
    )

}
