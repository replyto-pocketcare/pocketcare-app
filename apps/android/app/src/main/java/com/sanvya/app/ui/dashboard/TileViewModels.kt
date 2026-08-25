package com.sanvya.app.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.BudgetRepository
import com.sanvya.app.data.repository.GoalsRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.RecurringRepository
import com.sanvya.app.data.repository.SplitsRepository
import com.sanvya.app.domain.budget.budgetProgress
import com.sanvya.app.domain.money.Money
import com.sanvya.app.ui.transactions.TransactionListItem
import com.sanvya.app.ui.transactions.transactionListItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
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

/* ------------------------------ Budgets ----------------------------- */

data class BudgetMini(
    val id: String,
    val label: String,
    val spentMinor: Long,
    val limitMinor: Long,
    val currency: String,
    val pct: Float,
    val overLimit: Boolean,
    val atOrOverThreshold: Boolean,
)

class BudgetsTileViewModel : ViewModel(), KoinComponent {
    private val budgetRepository: BudgetRepository by inject()

    private val _rows = MutableStateFlow<List<BudgetMini>>(emptyList())
    val rows: StateFlow<List<BudgetMini>> = _rows.asStateFlow()

    init {
        viewModelScope.launch {
            budgetRepository.watchBudgets().collectLatest { budgets ->
                // Web takes six and shows however many fit; native rows size to
                // their content, so six IS the count.
                val top = budgets.take(6)
                _rows.value = top.map { budget ->
                    // spentThisPeriod is a suspend call per budget -- the same
                    // N+1 web does in BudgetMini's useEffect. Six rows, and the
                    // alternative is a bespoke aggregate query that would then
                    // have to agree with the repository's own period maths.
                    val spent = runCatching { budgetRepository.spentThisPeriod(budget) }
                        .getOrElse { Money(0, budget.currency) }
                    val limit = Money(budget.limitAmount, budget.currency)
                    val progress = budgetProgress(limit, spent, budget.thresholdPct.toDouble())
                    BudgetMini(
                        id = budget.id,
                        label = budget.name?.takeIf { it.isNotBlank() } ?: budget.period,
                        spentMinor = spent.amount,
                        limitMinor = limit.amount,
                        currency = budget.currency,
                        // pct is Infinity for a zero limit; the bar clamps, but
                        // Float.POSITIVE_INFINITY through coerceIn would stay
                        // infinite, so it is pinned here instead.
                        pct = if (progress.pct.isFinite()) progress.pct.toFloat() else 100f,
                        overLimit = progress.overLimit,
                        atOrOverThreshold = progress.atOrOverThreshold,
                    )
                }
            }
        }
    }
}

/* ------------------------------- Goals ------------------------------ */

data class GoalMini(
    val id: String,
    val name: String,
    val isEmergencyFund: Boolean,
    val savedMinor: Long,
    val targetMinor: Long,
    val currency: String,
    val pct: Float,
)

class GoalsTileViewModel : ViewModel(), KoinComponent {
    private val goalsRepository: GoalsRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _rows = MutableStateFlow<List<GoalMini>>(emptyList())
    val rows: StateFlow<List<GoalMini>> = _rows.asStateFlow()

    init {
        viewModelScope.launch {
            // The user id is required by both queries. filterNotNull rather
            // than `?: return`: the shell creates a guest before any screen
            // renders, but this view model can be constructed in the same frame
            // and a bare return would leave the tile permanently empty.
            val userId = authRepository.currentUserId.filterNotNull().first()
            combine(
                goalsRepository.watchGoals(userId),
                goalsRepository.watchAllocations(userId),
            ) { goals, allocations ->
                val savedByGoal = allocations.groupBy { it.goalId }
                    .mapValues { (_, rows) -> rows.sumOf { it.amountBlocked } }
                // Web orders emergency funds first, then by priority, and takes
                // six. The repository already returns that order.
                goals.take(6).map { goal ->
                    val saved = savedByGoal[goal.id] ?: 0L
                    GoalMini(
                        id = goal.id,
                        name = goal.name,
                        isEmergencyFund = goal.isEmergencyFund,
                        savedMinor = saved,
                        targetMinor = goal.targetAmount,
                        currency = goal.currency,
                        pct = if (goal.targetAmount > 0) {
                            minOf(100f, (saved.toFloat() / goal.targetAmount) * 100f)
                        } else 0f,
                    )
                }
            }.collectLatest { _rows.value = it }
        }
    }
}

/* ------------------------------ Splits ------------------------------ */

data class SplitsTileState(
    val owedMinor: Long = 0,
    val oweMinor: Long = 0,
    val rows: List<FriendBalanceRow> = emptyList(),
    val hiddenCount: Int = 0,
)

data class FriendBalanceRow(val userId: String, val name: String, val netMinor: Long)

class SplitsTileViewModel : ViewModel(), KoinComponent {
    private val splitsRepository: SplitsRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _state = MutableStateFlow(SplitsTileState())
    val state: StateFlow<SplitsTileState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val userId = authRepository.currentUserId.filterNotNull().first()
            combine(
                splitsRepository.watchFriendBalances(userId),
                // `watchConnections` is the only profile source in this
                // repository; web reads a profiles map. Same rows, and a
                // balance with nobody attached still renders -- with an empty
                // name rather than an invented "Someone", which would look like
                // a real person you owe money to.
                splitsRepository.watchConnections(userId),
            ) { balances, profiles ->
                // Ranked by SIZE of the balance, not by sign -- web sorts on
                // abs(net), so the person you owe most and the person who owes
                // you most both surface.
                val ranked = balances.filter { it.net != 0L }.sortedByDescending { kotlin.math.abs(it.net) }
                val top = ranked.take(8)
                SplitsTileState(
                    owedMinor = balances.sumOf { maxOf(0L, it.net) },
                    oweMinor = balances.sumOf { maxOf(0L, -it.net) },
                    rows = top.map { balance ->
                        FriendBalanceRow(
                            userId = balance.userId,
                            name = profiles.firstOrNull { it.id == balance.userId }?.name ?: "",
                            netMinor = balance.net,
                        )
                    },
                    hiddenCount = (ranked.size - top.size).coerceAtLeast(0),
                )
            }.collectLatest { _state.value = it }
        }
    }
}
