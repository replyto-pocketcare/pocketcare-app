@file:OptIn(ExperimentalCoroutinesApi::class)

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
import com.sanvya.app.domain.dashboard.CashflowMonth
import com.sanvya.app.domain.dashboard.TrendBucket
import com.sanvya.app.domain.dashboard.TrendPeriod
import com.sanvya.app.domain.dashboard.buildTrend
import com.sanvya.app.domain.dashboard.monthlyCashflow
import com.sanvya.app.domain.finance.monthlyEquivalent
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import com.sanvya.app.ui.baseCurrencyNow
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

/* -------------------- By category / by label ------------------- */

/**
 * One horizontal bar. `name` is null for the uncategorised bucket — the view
 * names it, because i18n belongs where the string is rendered.
 */
data class NamedTotalRow(val name: String?, val totalMinor: Long)

class ByCategoryTileViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    val rows: StateFlow<List<NamedTotalRow>> = ledgerRepository.watchExpenseByCategory()
        .map { rows -> rows.map { NamedTotalRow(it.name, it.total) } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
}

class ByLabelTileViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    val rows: StateFlow<List<NamedTotalRow>> = ledgerRepository.watchExpenseByLabel()
        .map { rows -> rows.map { NamedTotalRow(it.name, it.total) } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
}

/* ---------------------- This month vs last --------------------- */

data class MonthCompareState(
    val lastIncomeMinor: Long = 0,
    val lastExpenseMinor: Long = 0,
    val thisIncomeMinor: Long = 0,
    val thisExpenseMinor: Long = 0,
) {
    val isEmpty: Boolean
        get() = lastIncomeMinor == 0L && lastExpenseMinor == 0L &&
            thisIncomeMinor == 0L && thisExpenseMinor == 0L
}

class MonthCompareTileViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    val state: StateFlow<MonthCompareState> = ledgerRepository.watchMonthlyIncomeExpense()
        .map { rows ->
            // Local months, matching web's `new Date().getMonth()`. The query
            // groups on strftime('%Y-%m', occurred_at), which SQLite evaluates
            // in UTC -- so a transaction in the first hours of a month can land
            // in the previous bucket for a user east of UTC. That is web's
            // behaviour too, bug included, and fixing it here alone would make
            // the two disagree.
            val now = LocalDate.now()
            val thisYm = "%04d-%02d".format(now.year, now.monthValue)
            val last = now.minusMonths(1)
            val lastYm = "%04d-%02d".format(last.year, last.monthValue)
            fun total(ym: String, type: String) =
                rows.firstOrNull { it.yearMonth == ym && it.type == type }?.total ?: 0L
            MonthCompareState(
                lastIncomeMinor = total(lastYm, "income"),
                lastExpenseMinor = total(lastYm, "expense"),
                thisIncomeMinor = total(thisYm, "income"),
                thisExpenseMinor = total(thisYm, "expense"),
            )
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), MonthCompareState())
}

/* ---------------------------- Trends --------------------------- */

class TrendsTileViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    private val _period = MutableStateFlow(TrendPeriod.ONE_MONTH)
    val period: StateFlow<TrendPeriod> = _period.asStateFlow()

    private val _buckets = MutableStateFlow<List<TrendBucket>>(emptyList())
    val buckets: StateFlow<List<TrendBucket>> = _buckets.asStateFlow()

    private val _totalMinor = MutableStateFlow(0L)
    val totalMinor: StateFlow<Long> = _totalMinor.asStateFlow()

    init {
        viewModelScope.launch {
            // flatMapLatest, so changing the period swaps the query rather than
            // filtering a wider one in memory -- a year of daily rows is not
            // something to hold just because the user might pick "1y".
            _period.flatMapLatest { period ->
                val today = LocalDate.now()
                val since = today.minusDays(daysFor(period) - 1L).toString() + "T00:00:00"
                ledgerRepository.watchDailyExpenseSince(since).map { daily -> period to daily }
            }.collectLatest { (period, daily) ->
                _buckets.value = buildTrend(daily, period, LocalDate.now().toString())
                _totalMinor.value = daily.values.sum()
            }
        }
    }

    fun setPeriod(period: TrendPeriod) { _period.value = period }

    private fun daysFor(period: TrendPeriod): Long = when (period) {
        TrendPeriod.THREE_DAYS -> 3
        TrendPeriod.ONE_WEEK -> 7
        TrendPeriod.ONE_MONTH -> 28
        TrendPeriod.ONE_YEAR -> 365
    }
}

/* ------------------- Cashflow / net trend ---------------------- */

class CashflowTileViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    val months: StateFlow<List<CashflowMonth>> = ledgerRepository.watchMonthlyCashflow()
        .map { rows -> monthlyCashflow(rows.map { Triple(it.yearMonth, it.type, it.total) }) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
}

/* ------------------------ Subscriptions ------------------------ */

data class SubscriptionRow(
    val id: String,
    val name: String,
    val dueIso: String,
    val amountMinor: Long?,
    val currency: String?,
)

data class SubscriptionsState(
    val monthlyMinor: Long = 0,
    val rows: List<SubscriptionRow> = emptyList(),
    val hiddenCount: Int = 0,
)

class SubscriptionsTileViewModel : ViewModel(), KoinComponent {
    private val recurringRepository: RecurringRepository by inject()

    val state: StateFlow<SubscriptionsState> = recurringRepository.watchSubscriptions()
        .map { items ->
            // Everything normalised to a MONTHLY equivalent so a yearly plan and
            // a monthly one are comparable -- the same vector-tested
            // monthlyEquivalent the Recurring screen uses.
            val monthly = items.sumOf { monthlyEquivalent(it.amount ?: 0L, it.frequency) }
            val renewing = items.filter { it.nextDue.isNotBlank() }
            val top = renewing.take(8)
            SubscriptionsState(
                monthlyMinor = monthly,
                rows = top.map { SubscriptionRow(it.id, it.name, it.nextDue, it.amount, it.currency) },
                hiddenCount = (renewing.size - top.size).coerceAtLeast(0),
            )
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), SubscriptionsState())
}

/* ----------------------- Across currencies --------------------- */

data class CurrencySlice(
    val currency: String,
    val nativeMinor: Long,
    val baseMinor: Long,
    val sharePct: Int,
)

class CurrenciesTileViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    val slices: StateFlow<List<CurrencySlice>> = combine(
        ledgerRepository.watchAccountBalances(),
        ledgerRepository.watchRates(),
    ) { balances, rates ->
        val base = baseCurrencyNow()
        val byCurrency = balances.groupBy { it.balance.currency }
            .mapValues { (_, rows) -> rows.sumOf { it.balance.amount } }
        val converted = byCurrency.mapValues { (currency, amount) ->
            (amount * rates(currency, base)).toLong()
        }
        val total = converted.values.sum()
        byCurrency.entries
            .sortedByDescending { converted[it.key] ?: 0L }
            .map { (currency, nativeAmount) ->
                val inBase = converted[currency] ?: 0L
                CurrencySlice(
                    currency = currency,
                    nativeMinor = nativeAmount,
                    baseMinor = inBase,
                    sharePct = if (total != 0L) ((inBase * 100) / total).toInt() else 0,
                )
            }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
}
