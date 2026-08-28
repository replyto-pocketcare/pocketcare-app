package com.sanvya.app.ui.insights

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.BudgetLike
import com.sanvya.app.data.repository.BudgetRepository
import com.sanvya.app.data.repository.CategoryRow
import com.sanvya.app.data.repository.DividendRow
import com.sanvya.app.data.repository.GoalsRepository
import com.sanvya.app.data.repository.InvestmentsRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.data.repository.QuoteRow
import com.sanvya.app.data.repository.SubscriptionsRepository
import com.sanvya.app.data.repository.TransactionRow
import com.sanvya.app.domain.entitlements.isPaid as domainIsPaid
import com.sanvya.app.domain.insights.AvgDailyAgg
import com.sanvya.app.domain.insights.BudgetAgg
import com.sanvya.app.domain.insights.CatAgg
import com.sanvya.app.domain.insights.CatSpike
import com.sanvya.app.domain.insights.DayAgg
import com.sanvya.app.domain.insights.DividendAgg
import com.sanvya.app.domain.insights.DivEvent
import com.sanvya.app.domain.insights.DivRow
import com.sanvya.app.domain.insights.DividendPeriod
import com.sanvya.app.domain.insights.GenContext
import com.sanvya.app.domain.insights.GoalAgg
import com.sanvya.app.domain.insights.HoldingLite
import com.sanvya.app.domain.insights.InsightCard
import com.sanvya.app.domain.insights.MonthAgg
import com.sanvya.app.domain.insights.NoSpendAgg
import com.sanvya.app.domain.insights.PaceAgg
import com.sanvya.app.domain.insights.SeriesPoint
import com.sanvya.app.domain.insights.SubAgg
import com.sanvya.app.domain.insights.TopExpense
import com.sanvya.app.domain.insights.TransactionForInsight
import com.sanvya.app.domain.insights.TxnDayCount
import com.sanvya.app.domain.insights.ProjectionAgg
import com.sanvya.app.domain.insights.bucketize
import com.sanvya.app.domain.insights.composeStack
import com.sanvya.app.domain.insights.computeDividendEvents
import com.sanvya.app.domain.insights.dividendSummary
import com.sanvya.app.domain.ledger.RateLookup
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.money.toMajor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.math.pow
import kotlin.math.roundToLong
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.formatMoney


/**
 * Real port of apps/web/src/insights/useInsightStack.ts + src/insights/
 * generators.ts (task #28), replacing an entirely fake predecessor that
 * hardcoded a nonexistent "StreamTV" subscription and a made-up "dining"
 * keyword heuristic -- see docs/mobile/screen-specs/insights.md for the
 * full source-verified spec this was built from, and AUDIT_HISTORY.md's
 * 2026-08-06 Insights entry for what "fake" meant concretely.
 *
 * Aggregates 13 real `db.watch()` streams (real reactivity from day one --
 * no one-shot reload() to retrofit later, unlike Goals/Budgets earlier this
 * session) into generators.ts's GenContext shape in-memory (rather than 14
 * hand-written raw-SQL aggregate queries per platform -- see the spec's
 * "why in-memory" note), then runs composeStack() to rank the top 12 cards.
 */
class InsightsViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val budgetRepository: BudgetRepository by inject()
    private val goalsRepository: GoalsRepository by inject()
    private val subscriptionsRepository: SubscriptionsRepository by inject()
    private val investmentsRepository: InvestmentsRepository by inject()
    private val prefsRepository: PrefsRepository by inject()
    private val authRepository: AuthRepository by inject()

    /**
     * Handed to the domain generators as `GenContext.fmt`.
     *
     * Insights roll up across accounts, so they report in the user's base
     * currency — which is now read, not assumed. The old version pinned both
     * currency and locale to INR and had a fallback that divided by 100 by hand.
     */
    private fun formatMoney(minor: Long): String =
        formatMoney(minor, baseCurrencyNow())

    private val _cards = MutableStateFlow<List<InsightCard>>(emptyList())
    val cards: StateFlow<List<InsightCard>> = _cards

    private val _isPaid = MutableStateFlow(false)
    val isPaid: StateFlow<Boolean> = _isPaid

    private val _entitlementLoaded = MutableStateFlow(false)
    val entitlementLoaded: StateFlow<Boolean> = _entitlementLoaded

    private val _activeIndex = MutableStateFlow(0)
    val activeIndex: StateFlow<Int> = _activeIndex
    fun setActiveIndex(i: Int) { _activeIndex.value = i.coerceIn(0, maxOf(0, _cards.value.size - 1)) }

    init {
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value ?: return@launch

            val group1 = combine(
                ledgerRepository.watchAllTransactions(),
                ledgerRepository.watchCategories(),
                ledgerRepository.watchTransactionLabelNames(),
                budgetRepository.watchBudgets(),
                budgetRepository.watchBudgetCategories(),
            ) { txns, cats, labelMap, budgets, budgetCats -> Group1(txns, cats, labelMap, budgets, budgetCats) }

            val group2 = combine(
                goalsRepository.watchGoals(userId),
                goalsRepository.watchAllocations(userId),
                subscriptionsRepository.watchActive(),
                investmentsRepository.watchHoldings(userId),
                investmentsRepository.watchDividends(),
            ) { goals, allocs, subs, holdings, divs -> Group2(goals, allocs, subs, holdings, divs) }

            val group3 = combine(
                investmentsRepository.watchQuotes(),
                ledgerRepository.watchRates(),
                prefsRepository.watchEntitlement(),
            ) { quotes, rates, ent -> Group3(quotes, rates, ent) }

            combine(group1, group2, group3) { g1, g2, g3 -> Triple(g1, g2, g3) }.collect { (g1, g2, g3) ->
                val ent = g3.entitlement
                _isPaid.value = domainIsPaid(ent?.tier, ent?.premiumTrialStartDate, ent?.compTier, ent?.compUntil, System.currentTimeMillis())
                _entitlementLoaded.value = true

                val ctx = buildGenContext(g1, g2, g3)
                _cards.value = composeStack(ctx)
                if (_activeIndex.value >= _cards.value.size) _activeIndex.value = maxOf(0, _cards.value.size - 1)
            }
        }
    }

    private data class Group1(
        val txns: List<TransactionRow>, val cats: List<CategoryRow>, val labelMap: Map<String, List<String>>,
        val budgets: List<BudgetLike>, val budgetCats: List<Pair<String, String>>,
    )
    private data class Group2(
        val goals: List<com.sanvya.app.data.repository.Goal>, val allocs: List<com.sanvya.app.data.repository.GoalAllocation>,
        val subs: List<com.sanvya.app.data.repository.SubscriptionRow>, val holdings: List<com.sanvya.app.data.repository.Holding>,
        val divs: List<DividendRow>,
    )
    private data class Group3(val quotes: List<QuoteRow>, val rates: RateLookup, val entitlement: com.sanvya.app.data.repository.EntitlementRow?)

    private fun buildGenContext(g1: Group1, g2: Group2, g3: Group3): GenContext {
        val now = LocalDate.now(ZoneOffset.UTC)
        val nowIso = Instant.now().toString()
        val thisM = "%04d-%02d".format(now.year, now.monthValue)

        fun iso(d: LocalDate) = d.toString()

        // ---- 14-day continuous daily series ----
        data class DayBucket(var income: Long = 0, var expense: Long = 0)
        val dayMap = LinkedHashMap<String, DayBucket>()
        for (t in g1.txns) {
            if (t.type != "income" && t.type != "expense") continue
            val day = t.occurredAt.take(10)
            val b = dayMap.getOrPut(day) { DayBucket() }
            if (t.type == "income") b.income += t.amount else b.expense += t.amount
        }
        val days = (13 downTo 0).map { i ->
            val d = iso(now.minusDays(i.toLong())); val b = dayMap[d] ?: DayBucket()
            DayAgg(d, b.income, b.expense)
        }

        // ---- 8-month continuous series ----
        data class MonthBucket(var income: Long = 0, var expense: Long = 0)
        val monthMap = LinkedHashMap<String, MonthBucket>()
        for (t in g1.txns) {
            if (t.type != "income" && t.type != "expense") continue
            val ym = t.occurredAt.take(7)
            val b = monthMap.getOrPut(ym) { MonthBucket() }
            if (t.type == "income") b.income += t.amount else b.expense += t.amount
        }
        val months = (7 downTo 0).map { i ->
            val d = now.minusMonths(i.toLong()); val ym = "%04d-%02d".format(d.year, d.monthValue)
            val b = monthMap[ym] ?: MonthBucket()
            MonthAgg(ym, b.income, b.expense)
        }

        // ---- this month's category/label expense ----
        val catNameById = g1.cats.associateBy({ it.id }, { it.name })
        val thisMonthExpenseTxns = g1.txns.filter { it.type == "expense" && it.occurredAt.take(7) == thisM }
        val catExpenseById = LinkedHashMap<String, Long>() // by category_id, for budgets scoping
        val catExpenseByName = LinkedHashMap<String, Long>()
        for (t in thisMonthExpenseTxns) {
            val cid = t.categoryId
            if (cid != null) catExpenseById[cid] = (catExpenseById[cid] ?: 0L) + t.amount
            val name = cid?.let { catNameById[it] } ?: "Uncategorised"
            catExpenseByName[name] = (catExpenseByName[name] ?: 0L) + t.amount
        }
        val cats = catExpenseByName.entries.map { CatAgg(it.key, it.value) }.sortedByDescending { it.expense }
        val totalMonthExpenseAll = thisMonthExpenseTxns.sumOf { it.amount }

        val labelExpense = LinkedHashMap<String, Long>()
        for (t in thisMonthExpenseTxns) {
            val names = g1.labelMap[t.id] ?: continue
            for (n in names) labelExpense[n] = (labelExpense[n] ?: 0L) + t.amount
        }
        val labels = labelExpense.entries.map { CatAgg(it.key, it.value) }.sortedByDescending { it.expense }.take(8)

        // ---- budgets (simplified monthly spend vs limit) ----
        val budgetCatsByBudget = LinkedHashMap<String, MutableList<String>>()
        for ((bid, cid) in g1.budgetCats) budgetCatsByBudget.getOrPut(bid) { mutableListOf() }.add(cid)
        val budgets = g1.budgets.filter { it.period.isBlank() || it.period == "monthly" }.map { b ->
            val scoped = budgetCatsByBudget[b.id] ?: emptyList()
            val spent = if (scoped.isNotEmpty()) scoped.sumOf { catExpenseById[it] ?: 0L } else totalMonthExpenseAll
            BudgetAgg(b.name?.trim()?.ifBlank { "Budget" } ?: "Budget", b.limitAmount, spent)
        }

        // ---- streak + last-7-day counts ----
        val daySet = LinkedHashSet<String>()
        val countByDay = LinkedHashMap<String, Int>()
        for (t in g1.txns) {
            val day = t.occurredAt.take(10)
            if (LocalDate.parse(day) < now.minusDays(30)) continue
            daySet.add(day); countByDay[day] = (countByDay[day] ?: 0) + 1
        }
        var streak = 0
        var cur = if (daySet.contains(iso(now))) now else now.minusDays(1)
        while (daySet.contains(iso(cur))) { streak++; cur = cur.minusDays(1) }
        val txnDays7 = (6 downTo 0).map { i -> val d = iso(now.minusDays(i.toLong())); TxnDayCount(d, countByDay[d] ?: 0) }

        // ---- expense-by-day map (70d) for weekday / pace / no-spend / avg ----
        val expDay = LinkedHashMap<String, Long>()
        for (t in g1.txns) {
            if (t.type != "expense") continue
            val day = t.occurredAt.take(10)
            if (LocalDate.parse(day) < now.minusDays(70)) continue
            expDay[day] = (expDay[day] ?: 0L) + t.amount
        }

        // weekday averages, last 60 days
        // Every chart below plots MAJOR units. One scale for the whole pass:
        // insights are computed in the user's base currency throughout.
        //
        // The shape is web's `major = (minor) => Math.round(minor) / 100`:
        // round the MINOR value, THEN scale. Android used to scale first and
        // round the result to two decimal places, which is a different number
        // and disagreed with iOS on every chart point.
        val scale = majorScale(baseCurrencyNow())
        val wdSum = DoubleArray(7); val wdCnt = IntArray(7)
        for (i in 0 until 60) {
            val d = now.minusDays(i.toLong())
            val wd = d.dayOfWeek.value % 7 // MONDAY(1)->1 .. SUNDAY(7)->0
            wdSum[wd] += (expDay[iso(d)] ?: 0L).toDouble(); wdCnt[wd] += 1
        }
        val wdLabels = arrayOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
        val weekday = wdLabels.indices.map { i -> SeriesPoint(wdLabels[i], if (wdCnt[i] > 0) (wdSum[i] / wdCnt[i]).roundToLong() / scale else 0.0) }
        val weekdayTop = weekday.maxByOrNull { it.value }?.label ?: wdLabels[0]

        // month pace / no-spend / avg
        val dayOfMonth = now.dayOfMonth
        val daysInMonth = now.lengthOfMonth()
        val lastMonthDate = now.minusMonths(1).withDayOfMonth(1)
        val lastYm = "%04d-%02d".format(lastMonthDate.year, lastMonthDate.monthValue)
        val daysInLastMonth = now.withDayOfMonth(1).minusDays(1).dayOfMonth
        var thisSoFar = 0.0; var spendDays = 0; val cumulative = mutableListOf<SeriesPoint>()
        for (dd in 1..dayOfMonth) {
            val k = "$thisM-${dd.toString().padStart(2, '0')}"
            val v = (expDay[k] ?: 0L).toDouble(); thisSoFar += v; if (v > 0) spendDays++
            cumulative.add(SeriesPoint(dd.toString(), thisSoFar / scale))
        }
        var lastSameSoFar = 0.0; var lastFull = 0.0
        for (dd in 1..daysInLastMonth) {
            val k = "$lastYm-${dd.toString().padStart(2, '0')}"
            val v = (expDay[k] ?: 0L).toDouble(); lastFull += v; if (dd <= dayOfMonth) lastSameSoFar += v
        }
        val pace = PaceAgg(thisSoFar, lastSameSoFar, lastFull, dayOfMonth, daysInMonth, cumulative)
        val noSpend = NoSpendAgg(maxOf(0, dayOfMonth - spendDays), dayOfMonth, spendDays)
        val avgDaily = AvgDailyAgg(if (dayOfMonth > 0) thisSoFar / dayOfMonth else 0.0, if (daysInLastMonth > 0) lastFull / daysInLastMonth else 0.0)

        // ---- top expenses (this month) ----
        val topExpenses = thisMonthExpenseTxns.sortedByDescending { it.amount }.take(6)
            .map { TopExpense((it.description ?: it.note ?: "Expense").trim(), it.amount) }

        // ---- subscriptions (monthly-normalised) ----
        fun norm(amt: Long, cycle: String?): Long = when (cycle) {
            "yearly" -> amt / 12; "weekly" -> (amt * 52) / 12; "quarterly" -> amt / 3; else -> amt
        }
        val subs = g2.subs.map { SubAgg(it.name?.trim()?.ifBlank { "Subscription" } ?: "Subscription", norm(it.amount, it.billingCycle)) }
        val subsTotal = subs.sumOf { it.monthly }

        // ---- goals ----
        val savedByGoal = LinkedHashMap<String, Long>()
        for (a in g2.allocs) savedByGoal[a.goalId] = (savedByGoal[a.goalId] ?: 0L) + a.amountBlocked
        val goals = g2.goals.map { GoalAgg(it.name.trim().ifBlank { "Goal" }, it.targetAmount, savedByGoal[it.id] ?: 0L, it.isEmergencyFund) }

        // ---- category spike (this month vs prior 3 months average, per category) ----
        val fourMonthsAgo = now.minusMonths(4)
        data class CatMonth(var thisMonth: Long = 0L, val prior: MutableList<Long> = mutableListOf())
        val byCat = LinkedHashMap<String, CatMonth>()
        run {
            val priorByCatYm = LinkedHashMap<Pair<String, String>, Long>()
            for (t in g1.txns) {
                if (t.type != "expense") continue
                val day = LocalDate.parse(t.occurredAt.take(10))
                if (day < fourMonthsAgo) continue
                val name = t.categoryId?.let { catNameById[it] } ?: "Uncategorised"
                val ym = t.occurredAt.take(7)
                val key = name to ym
                priorByCatYm[key] = (priorByCatYm[key] ?: 0L) + t.amount
            }
            for ((key, total) in priorByCatYm) {
                val (name, ym) = key
                val e = byCat.getOrPut(name) { CatMonth() }
                if (ym == thisM) e.thisMonth = total else e.prior.add(total)
            }
        }
        var catSpike: CatSpike? = null
        for ((name, v) in byCat) {
            if (v.thisMonth <= 0 || v.prior.isEmpty()) continue
            val avgPrior = v.prior.sum().toDouble() / v.prior.size
            if (avgPrior <= 0 || v.thisMonth < avgPrior * 1.3 || v.thisMonth < 5000) continue
            if (catSpike == null || v.thisMonth.toDouble() / avgPrior > catSpike!!.thisMonth / catSpike!!.avgPrior) {
                catSpike = CatSpike(name, v.thisMonth.toDouble(), avgPrior)
            }
        }

        // ---- investments: dividends + projection ----
        var dividends: DividendAgg? = null
        var projection: ProjectionAgg? = null
        if (g2.holdings.isNotEmpty()) {
            val lite = g2.holdings.map { HoldingLite(it.symbol, it.exchange, it.quantity, it.currency) }
            val divRows = g2.divs.map { DivRow(it.symbol, it.exchange, it.exDate, it.payDate, it.amount, it.currency) }
            val events: List<DivEvent> = computeDividendEvents(lite, divRows, g3.rates, baseCurrencyNow())
            val summary = dividendSummary(events)
            val buckets = bucketize(events, DividendPeriod.MONTH).map { SeriesPoint(it.label, it.value.roundToLong() / majorScale(baseCurrencyNow())) }
            dividends = DividendAgg(g2.holdings.size, summary.trailing12, summary.upcoming12, summary.total, buckets)

            val qKey = { s: String, e: String? -> "${s.uppercase()}|${(e ?: "").uppercase()}" }
            val bySymEx = LinkedHashMap<String, QuoteRow>(); val bySym = LinkedHashMap<String, QuoteRow>()
            for (q in g3.quotes) { bySymEx[qKey(q.symbol, q.exchange)] = q; bySym.putIfAbsent(q.symbol.uppercase(), q) }
            var currentValue = 0.0
            for (h in g2.holdings) {
                val q = bySymEx[qKey(h.symbol, h.exchange)] ?: bySym[h.symbol.uppercase()]
                val perShare = q?.price?.toDouble() ?: (h.avgCost?.toDouble() ?: 0.0)
                val ccy = q?.currency ?: h.currency
                val rate = if (ccy == baseCurrencyNow()) 1.0 else g3.rates(ccy, baseCurrencyNow())
                currentValue += perShare * h.quantity * rate
            }
            val projGrowthPct = 7; val projYears = 15
            val yieldRate = if (currentValue > 0) (if (summary.trailing12 > 0) summary.trailing12 else summary.upcoming12).toDouble() / currentValue else 0.0
            val mGrowth = (1 + projGrowthPct / 100.0).pow(1.0 / 12.0) - 1
            var value = currentValue
            val projScale = majorScale(baseCurrencyNow())
            val series = mutableListOf(SeriesPoint("Now", currentValue.roundToLong() / projScale))
            for (m in 1..(projYears * 12)) {
                value *= (1 + mGrowth)
                value += (value * yieldRate) / 12
                if (m % 12 == 0 && (m / 12) % 3 == 0) series.add(SeriesPoint("${m / 12}y", value.roundToLong() / projScale))
            }
            projection = ProjectionAgg(g2.holdings.size, currentValue, value, currentValue, projYears, projGrowthPct, series)
        }

        // ---- mindfulness input transactions ----
        val mindfulnessTxns: List<TransactionForInsight> = g1.txns
            .filter { it.type == "expense" && (LocalDate.parse(it.occurredAt.take(10)) >= now.minusDays(30) || it.intent != null) }
            .map { TransactionForInsight(it.id, it.amount, it.currency, it.occurredAt, it.intent, it.categoryId) }

        return GenContext(
            currency = baseCurrencyNow(), now = now, nowIso = nowIso, fmt = ::formatMoney,
            days = days, months = months, cats = cats, labels = labels, budgets = budgets,
            streak = streak, txnDays7 = txnDays7, topExpenses = topExpenses,
            weekday = weekday, weekdayTop = weekdayTop, subs = subs, subsTotal = subsTotal,
            goals = goals, pace = pace, noSpend = noSpend, avgDaily = avgDaily, catSpike = catSpike,
            dividends = dividends, projection = projection, mindfulnessTxns = mindfulnessTxns,
        )
    }
}
