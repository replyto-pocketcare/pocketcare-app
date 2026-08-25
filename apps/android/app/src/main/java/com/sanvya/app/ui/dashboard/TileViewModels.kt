package com.sanvya.app.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.RecurringRepository
import com.sanvya.app.ui.transactions.TransactionListItem
import com.sanvya.app.ui.transactions.transactionListItem
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * One view model per tile, not one for the dashboard.
 *
 * Web does the same — every tile in `tiles.tsx` runs its own `useQuery` — and
 * it is what lets the catalog hold fourteen tiles cheaply: a tile the user has
 * not enabled is never composed, so its query never runs.
 */

/* ------------------------------ Recent ------------------------------ */

class RecentTileViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    /**
     * Web reads 24 rows, collapses split siblings, then shows however many fit
     * the tile — capped at 10. Native rows size to their content rather than
     * being clipped to a measured height, so there is nothing to fit to: the
     * cap IS the count. Ten was already web's ceiling and is what a phone
     * showed there.
     */
    val rows: StateFlow<List<TransactionListItem>> = combine(
        ledgerRepository.watchRecentTransactions(limit = 24),
        ledgerRepository.watchAccounts(includeArchived = true),
        ledgerRepository.watchCategories(),
        ledgerRepository.watchTransactionLabelNames(),
    ) { txns, accounts, categories, labels ->
        val accountMap = accounts.associateBy { it.id }
        val categoryMap = categories.associateBy { it.id }
        txns.asSequence()
            // Web filters `type != 'opening_balance'` in the query itself. An
            // opening balance is bookkeeping, not activity, and showing it as
            // the most recent thing you did is how a new account looks like a
            // deposit you do not remember making.
            .filter { it.type != "opening_balance" }
            .take(10)
            .map { transactionListItem(it, accountMap, categoryMap, labels[it.id]) }
            .toList()
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
}

/* ----------------------------- Spending ----------------------------- */

/** One category's share of this month's spending. */
data class SpendSlice(
    val categoryId: String?,
    val name: String,
    val totalMinor: Long,
    /** Share of the month's total, 0-100. */
    val sharePct: Int,
    /** Share of the LARGEST category, 0-100 — the bar's fill. */
    val fillPct: Int,
)

data class SpendingTileState(
    val totalMinor: Long = 0,
    val slices: List<SpendSlice> = emptyList(),
    val hiddenCount: Int = 0,
)

class SpendingTileViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    /** Web's `new Date(y, m, 1).toISOString()` — the first instant of this month. */
    private fun monthStartIso(): String =
        LocalDate.now().withDayOfMonth(1).atStartOfDay().atOffset(ZoneOffset.UTC).toString()

    val state: StateFlow<SpendingTileState> = combine(
        // Open-ended: `occurred_at < ?` with a sentinel far in the future, so a
        // transaction dated later today is included. Web's query has no upper
        // bound at all; this repository's does, and inventing a second
        // unbounded method for one caller would be worse than a sentinel that
        // is obviously one.
        ledgerRepository.watchTransactionsInRange(monthStartIso(), "9999-12-31T00:00:00Z"),
        ledgerRepository.watchCategories(),
    ) { txns, categories ->
        val categoryMap = categories.associateBy { it.id }
        val expenses = txns.filter { it.type == "expense" }
        // NOTE: web's query also excludes transactions with a `lend` expense
        // posting -- money you fronted for someone is not your spending. That
        // exclusion is NOT applied here, because no native repository exposes
        // expense_postings yet. Recorded in ABSENT-BY-DECISION.md rather than
        // left to be discovered as a number that disagrees with the browser.
        val byCategory = expenses
            .groupBy { it.categoryId }
            .map { (categoryId, rows) ->
                categoryId to rows.sumOf { it.amount }
            }
            .sortedByDescending { it.second }

        val total = byCategory.sumOf { it.second }
        val largest = byCategory.firstOrNull()?.second ?: 0L
        // Web charts the top 7 and links the rest to Insights.
        val top = byCategory.take(7)
        SpendingTileState(
            totalMinor = total,
            slices = top.map { (categoryId, amount) ->
                SpendSlice(
                    categoryId = categoryId,
                    name = categoryId?.let { categoryMap[it]?.name } ?: "Uncategorised",
                    totalMinor = amount,
                    sharePct = if (total > 0) ((amount * 100) / total).toInt() else 0,
                    // Web floors the fill at 3% so a tiny category still draws
                    // something -- a zero-width bar reads as a rendering bug.
                    fillPct = if (largest > 0) maxOf(3, ((amount * 100) / largest).toInt()) else 0,
                )
            },
            hiddenCount = (byCategory.size - top.size).coerceAtLeast(0),
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), SpendingTileState())
}

/* ----------------------------- Upcoming ----------------------------- */

data class UpcomingRow(
    val id: String,
    val name: String,
    val dueIso: String,
    val amountMinor: Long?,
    val currency: String?,
)

class UpcomingTileViewModel : ViewModel(), KoinComponent {
    private val recurringRepository: RecurringRepository by inject()

    val rows: StateFlow<List<UpcomingRow>> = recurringRepository.watchActiveItems()
        .map { items ->
            items
                // Savings are excluded here for the same reason they are
                // excluded from the Recurring screen's totals: a SIP is a
                // transfer between your own accounts, so listing it as an
                // upcoming payment overstates what is leaving.
                .filter { it.direction != "saving" }
                .sortedBy { it.nextDue }
                .take(5)
                .map { UpcomingRow(it.id, it.name, it.nextDue, it.amount, it.currency) }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
}
