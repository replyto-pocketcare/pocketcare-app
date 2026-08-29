package com.sanvya.app.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.AccountWithBalance
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.SettingsRepository
import com.sanvya.app.data.repository.NetWorth
import com.sanvya.app.data.repository.TransactionRow
import com.sanvya.app.domain.money.money
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.format.DateTimeFormatter
import java.time.OffsetDateTime
import java.time.ZoneId
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.formatMoneyAware
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.FormOptions
import com.sanvya.app.ui.majorScale
import com.sanvya.app.ui.components.initialSyncPending

/**
 * Net-worth hero content — mirrors apps/web/app/page.tsx's NetWorthHero
 * exactly (see docs/mobile/screen-specs/dashboard.md): [net] is total or
 * available depending on the toggle, [deltaMinor] is last month's
 * (income - expense) in minor units, [sparkline] is the cumulative running
 * sum of (income - expense)/100 per month (last 8 months, oldest first).
 */
/**
 * Dashboard's own local row type for the (still-deferred, see
 * docs/mobile/screen-specs/dashboard.md) "Recent Activity" section --
 * deliberately NOT `com.sanvya.app.ui.transactions.TransactionListItem`.
 * This mirrors a real bug found on iOS 2026-08-05: DashboardViewModel.swift
 * depended on Transactions' `TransactionUiModel` type by name with zero
 * indication the two screens were coupled; when the Transactions rewrite
 * removed that type this file would have failed to build the same way iOS
 * did (the Android build catching it now is standing evidence the coupling
 * is real, not hypothetical -- see AUDIT_HISTORY.md). Giving Dashboard its
 * own type avoids both the build break and pulling Transactions' full
 * TransactionListItem shape into an out-of-scope section.
 */
data class DashboardTxnRow(
    val id: String,
    val description: String,
    val amount: String,
    val date: String,
    val accountName: String,
    val categoryName: String,
    val isIncome: Boolean,
)

data class NetWorthHeroState(
    val net: com.sanvya.app.domain.money.Money = money(0, FormOptions.DEFAULT_CURRENCY),
    val base: String = FormOptions.DEFAULT_CURRENCY,
    val showAvailable: Boolean = false,
    val deltaMinor: Long = 0,
    val hasTrend: Boolean = false,
    val sparkline: List<Float> = emptyList(),
)

/**
 * The four figures the wide-window KPI strip shows, all in MINOR units.
 *
 * Derived here rather than in `StatRow` because the monthly income/expense fold
 * this screen already does for the hero's sparkline is the same fold web's
 * StatRow runs a second query for -- one pass over the ledger, two consumers.
 */
data class DashboardStats(
    val netMinor: Long = 0,
    val currentIncomeMinor: Long = 0,
    val currentExpenseMinor: Long = 0,
    val previousIncomeMinor: Long = 0,
    val previousExpenseMinor: Long = 0,
    val base: String = FormOptions.DEFAULT_CURRENCY,
)

data class DashboardUiState(
    val netWorthFormatted: String = formatMoney(0, FormOptions.DEFAULT_CURRENCY),
    val assetsFormatted: String = formatMoney(0, FormOptions.DEFAULT_CURRENCY),
    val liabilitiesFormatted: String = formatMoney(0, FormOptions.DEFAULT_CURRENCY),
    val accounts: List<AccountWithBalance> = emptyList(),
    val recentTransactions: List<DashboardTxnRow> = emptyList(),
    val hero: NetWorthHeroState = NetWorthHeroState(),
    /** Only read at EXPANDED -- see StatRow.kt for why phones skip the strip. */
    val stats: DashboardStats = DashboardStats(),
    /**
     * Who the greeting is addressed to -- page.tsx's
     * `session?.username || session.email.split("@")[0]`. Empty when neither is
     * known; the screen falls back to `dashboard.greetingFallback`, as web does.
     */
    val displayName: String = "",
    /**
     * The local accounts query has returned at least once. Web reads this off
     * `useAccountsLoading()`; here it is simply "the combine below has emitted",
     * which is the same fact.
     */
    val accountsLoaded: Boolean = false,
    /** The FIRST sync from the server has not landed yet -- see [initialSyncPending]. */
    val syncPending: Boolean = true,
)

/** No-arg constructor + KoinComponent/by inject() -- matches SettingsViewModel's
 * established pattern in this codebase, so the default Compose `viewModel()`
 * factory can construct it directly (no Koin viewModel-DSL module needed). */
class DashboardViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val settingsRepository: SettingsRepository by inject()

    /** Mirrors page.tsx's `showAvailable` local state (net-worth toggle). */
    private val showAvailable = MutableStateFlow(false)

    /**
     * Read once, not watched: the name on the greeting comes off the auth
     * session, which changes only by signing in or out -- and either of those
     * replaces this view model anyway.
     */
    private val displayName = MutableStateFlow("")

    init {
        viewModelScope.launch {
            val session = runCatching { settingsRepository.currentSession() }.getOrNull()
            // Web's precedence exactly: username, else the local part of the
            // email, else nothing (the screen supplies the fallback copy).
            displayName.value = session?.username?.takeIf { it.isNotBlank() }
                ?: session?.email?.substringBefore("@").orEmpty()
        }
    }

    fun toggleShowAvailable() {
        showAvailable.value = !showAvailable.value
    }

    private val core: Flow<DashboardUiState> = combine(
        ledgerRepository.watchNetWorth(baseCurrencyNow()),
        ledgerRepository.watchAccountBalances(includeArchived = false),
        ledgerRepository.watchRecentTransactions(limit = 10),
        ledgerRepository.watchMonthlyIncomeExpense(),
        showAvailable,
    ) { netWorth: NetWorth,
        accounts: List<AccountWithBalance>,
        txns: List<TransactionRow>,
        monthly: List<com.sanvya.app.data.repository.MonthlyIncomeExpense>,
        showAvail: Boolean ->

        val accountMap = accounts.associateBy { it.account.id }

        val recentUiTxns = txns.map { txn ->
            val isIncome = txn.type == "income"
            val sign = if (isIncome) "+" else "-"
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

            DashboardTxnRow(
                id = txn.id,
                description = txn.description ?: txn.note ?: "Transaction",
                amount = "$sign${formatMoney(txn.amount, account?.currency ?: baseCurrencyNow())}",
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

        // ---- Hero sparkline/delta -- matches page.tsx's NetWorthHero exactly:
        // group by (year-month, type) is already done by the query; fold into
        // per-month {inc, exp}, take the last 8 months, delta = last month's
        // (inc - exp), sparkline = cumulative running sum of (inc-exp)/100.
        val byMonth = LinkedHashMap<String, Pair<Long, Long>>() // ym -> (inc, exp)
        for (row in monthly) {
            val (inc, exp) = byMonth[row.yearMonth] ?: (0L to 0L)
            byMonth[row.yearMonth] = if (row.type == "income") row.total to exp else inc to row.total
        }
        val months = byMonth.entries.toList().takeLast(8)
        val deltaMinor = if (months.isNotEmpty()) {
            val (inc, exp) = months.last().value
            inc - exp
        } else 0L
        var acc = 0f
        // `majorScale`, not `/ 100f`: the sparkline is drawn in MAJOR units and
        // a zero-decimal currency was being plotted at a hundredth of its real
        // height.
        val sparkScale = majorScale(baseCurrencyNow()).toFloat()
        val sparkline = months.map { (_, v) -> acc += (v.first - v.second) / sparkScale; acc }

        // The KPI strip's four figures, off the SAME fold as the sparkline.
        // Web's StatRow re-runs the identical GROUP BY in its own component; the
        // one thing the port does differently is not paying for it twice.
        val current = months.lastOrNull()?.value ?: (0L to 0L)
        val previous = if (months.size >= 2) months[months.size - 2].value else (0L to 0L)

        val net = if (showAvail) netWorth.available else netWorth.total

        DashboardUiState(
            netWorthFormatted = formatMoneyAware(netWorth.total),
            assetsFormatted = formatMoney(assets, netWorth.base),
            liabilitiesFormatted = formatMoney(kotlin.math.abs(liabilities), netWorth.base),
            accounts = accounts,
            recentTransactions = recentUiTxns,
            stats = DashboardStats(
                netMinor = net.amount,
                currentIncomeMinor = current.first,
                currentExpenseMinor = current.second,
                previousIncomeMinor = previous.first,
                previousExpenseMinor = previous.second,
                base = netWorth.base,
            ),
            hero = NetWorthHeroState(
                net = net,
                base = netWorth.base,
                showAvailable = showAvail,
                deltaMinor = deltaMinor,
                hasTrend = months.isNotEmpty(),
                sparkline = sparkline,
            ),
            // `combine` does not emit until every source has, so reaching this
            // line IS the local read having returned -- web's `accountsLoading`
            // flipping false.
            accountsLoaded = true,
        )
    }

    /**
     * The screen's state, with the two flags that stop it lying during a first
     * sync.
     *
     * A second `combine` rather than five more sources in the first: the typed
     * overload tops out at five, and these two change on a completely different
     * cadence from the ledger -- the name settles once, the sync flag once.
     */
    val uiState: StateFlow<DashboardUiState> = combine(
        core,
        displayName,
        // The app's ONE gate now (`SyncStatusRepository`), where this used to
        // start a 400 ms poll of its own. See ui/components/InitialSyncGate.kt.
        initialSyncPending(),
    ) { state, name, syncPending ->
        state.copy(displayName = name, syncPending = syncPending)
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = DashboardUiState()
    )
}
