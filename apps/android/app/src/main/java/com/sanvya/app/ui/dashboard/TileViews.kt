package com.sanvya.app.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.DASHBOARD_CHART_COLORS
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.components.Eyebrow
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.domain.insights.SeriesPoint
import com.sanvya.app.domain.money.Money
import com.sanvya.app.domain.money.toMajor
import com.sanvya.app.ui.components.SanvyaBarsChart
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import com.sanvya.app.domain.dashboard.TrendPeriod
import com.sanvya.app.ui.components.SanvyaAreaChart
import com.sanvya.app.ui.components.SanvyaChip
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import com.sanvya.app.ui.transactions.TransactionRowCard

/**
 * Which tiles actually render something.
 *
 * The `when` has **no `else` branch**, and that is the guard: `TileId` is
 * generated from web's catalog, so the day a fifteenth tile appears there this
 * file stops compiling until somebody decides whether it is built. The
 * Add-a-widget picker reads this same property, so it is structurally
 * impossible for the picker to offer a tile that renders an empty card — the
 * dead control this audit keeps finding.
 */
val TileId.isBuilt: Boolean
    get() = when (this) {
        TileId.RECENT,
        TileId.SPENDING,
        TileId.UPCOMING,
        TileId.BUDGETS,
        TileId.GOALS,
        TileId.SPLITS,
        TileId.BY_CATEGORY,
        TileId.BY_LABEL,
        TileId.MONTH_COMPARE,
        TileId.TRENDS,
        TileId.SUBSCRIPTIONS,
        TileId.CASHFLOW,
        TileId.NET_TREND,
        TileId.CURRENCIES -> true
    }

/**
 * One tile's content.
 *
 * Each tile owns its own data, exactly as web does — every tile in `tiles.tsx`
 * runs its own `useQuery`. A tile the user has not enabled is never composed,
 * so its query never runs, which is what lets the catalog hold fourteen.
 */
@Composable
fun TileView(id: TileId, editing: Boolean, onOpen: () -> Unit) {
    // While editing, the tile is drawn but not clickable, mirroring web's
    // `pointer-events: none` on the tile body. A tap during edit belongs to the
    // move/remove controls, never to whatever is underneath them.
    val open: (() -> Unit)? = if (editing) null else onOpen
    when (id) {
        TileId.RECENT -> RecentTile(open)
        TileId.SPENDING -> SpendingTile(open)
        TileId.UPCOMING -> UpcomingTile(open)
        TileId.BUDGETS -> BudgetsTile(open)
        TileId.GOALS -> GoalsTile(open)
        TileId.SPLITS -> SplitsTile(open)
        TileId.BY_CATEGORY -> ByCategoryTile(open)
        TileId.BY_LABEL -> ByLabelTile(open)
        TileId.MONTH_COMPARE -> MonthCompareTile(open)
        TileId.TRENDS -> TrendsTile(open)
        TileId.CASHFLOW -> CashflowTile(open)
        TileId.NET_TREND -> NetTrendTile(open)
        TileId.SUBSCRIPTIONS -> SubscriptionsTile(open)
        TileId.CURRENCIES -> CurrenciesTile(open)
    }
}

@Composable
private fun TileShell(
    title: String,
    onOpen: (() -> Unit)?,
    trailing: @Composable (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    SanvyaCard(
        modifier = Modifier.fillMaxWidth(),
        padding = PaddingValues(20.dp),
        onClick = onOpen,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Box(Modifier.weight(1f)) { Eyebrow(title) }
            trailing?.invoke()
        }
        Spacer(Modifier.height(10.dp))
        content()
    }
}

@Composable
private fun TileEmpty(text: String) {
    SanvyaText(text, style = SanvyaType.statLabel, color = LocalSanvyaColors.current.text2)
}

/* ------------------------------ Recent ------------------------------ */

@Composable
private fun RecentTile(onOpen: (() -> Unit)?) {
    val viewModel: RecentTileViewModel = viewModel()
    val rows by viewModel.rows.collectAsState()

    TileShell(S.Dashboard.tileRecent(sRes()), onOpen) {
        if (rows.isEmpty()) {
            TileEmpty(S.Dashboard.emptyRecent(sRes()))
            return@TileShell
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            // The SAME row web renders on Transactions, Search and Statements.
            // It was private inside TransactionsScreen until this tile needed
            // it; a second copy here is the re-inlining the component
            // inventory exists to prevent.
            rows.forEach { item ->
                TransactionRowCard(item = item, onClick = { onOpen?.invoke() })
            }
        }
    }
}

/* ----------------------------- Spending ----------------------------- */

@Composable
private fun SpendingTile(onOpen: (() -> Unit)?) {
    val colors = LocalSanvyaColors.current
    val viewModel: SpendingTileViewModel = viewModel()
    val state by viewModel.state.collectAsState()
    val currency = baseCurrencyNow()

    TileShell(
        title = S.Dashboard.tileSpending(sRes()),
        onOpen = onOpen,
        trailing = if (state.slices.isEmpty()) null else {
            { SanvyaText(formatMoney(state.totalMinor, currency), style = SanvyaType.body) }
        },
    ) {
        if (state.slices.isEmpty()) {
            TileEmpty(S.Dashboard.emptySpending(sRes()))
            return@TileShell
        }
        // Ranked horizontal bars, not a donut. Web's own comment: "a calmer,
        // more legible read than a donut", and bars are sized against the
        // LARGEST category so the leader always fills its track.
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            state.slices.forEachIndexed { index, slice ->
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row(modifier = Modifier.fillMaxWidth()) {
                        SanvyaText(
                            slice.name,
                            style = SanvyaType.statLabel,
                            color = colors.text,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        SanvyaText(
                            "${formatMoney(slice.totalMinor, currency)} · ${slice.sharePct}%",
                            style = SanvyaType.statLabel,
                            color = colors.text2,
                        )
                    }
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(7.dp)
                            .clip(RoundedCornerShape(999.dp))
                            .background(colors.surface2),
                    ) {
                        Box(
                            Modifier
                                .fillMaxWidth(slice.fillPct / 100f)
                                .height(7.dp)
                                .clip(RoundedCornerShape(999.dp))
                                .background(DASHBOARD_CHART_COLORS[index % DASHBOARD_CHART_COLORS.size]),
                        )
                    }
                }
            }
            if (state.hiddenCount > 0) {
                SanvyaText(
                    S.Dashboard.moreItems(sRes(), state.hiddenCount),
                    style = SanvyaType.statLabel,
                    color = colors.text2,
                )
            }
        }
    }
}

/* ----------------------------- Upcoming ----------------------------- */

@Composable
private fun UpcomingTile(onOpen: (() -> Unit)?) {
    val colors = LocalSanvyaColors.current
    val viewModel: UpcomingTileViewModel = viewModel()
    val rows by viewModel.rows.collectAsState()
    val currency = baseCurrencyNow()

    TileShell(S.Dashboard.tileUpcoming(sRes()), onOpen) {
        if (rows.isEmpty()) {
            TileEmpty(S.Dashboard.emptyUpcoming(sRes()))
            return@TileShell
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            rows.forEach { row ->
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.weight(1f)) {
                        SanvyaText(
                            row.name,
                            style = SanvyaType.body,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        SanvyaText(
                            S.Cashflow.next(sRes(), row.dueIso),
                            style = SanvyaType.statLabel,
                            color = colors.text2,
                        )
                    }
                    row.amountMinor?.let {
                        SanvyaText(formatMoney(it, row.currency ?: currency), style = SanvyaType.body)
                    }
                }
            }
        }
    }
}

/* ------------------------------ Budgets ----------------------------- */

@Composable
private fun BudgetsTile(onOpen: (() -> Unit)?) {
    val viewModel: BudgetsTileViewModel = viewModel()
    val rows by viewModel.rows.collectAsState()

    HeroTile(S.Dashboard.tileBudgets(sRes()), HeroTint.BUDGETS, onOpen) {
        if (rows.isEmpty()) {
            SanvyaText(S.Dashboard.emptyBudgets(sRes()), style = SanvyaType.body, color = heroInkMuted)
            return@HeroTile
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            rows.forEach { budget ->
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(modifier = Modifier.fillMaxWidth()) {
                        SanvyaText(
                            budget.label,
                            style = SanvyaType.statLabel,
                            color = heroInk,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        SanvyaText(
                            formatMoney(budget.spentMinor, budget.currency) +
                                " / " + formatMoney(budget.limitMinor, budget.currency),
                            style = SanvyaType.statLabel,
                            color = heroInkMuted,
                            maxLines = 1,
                        )
                    }
                    // Three fills, not one: over-limit, at-threshold, and fine.
                    // Web's own colours -- they are pale on purpose, because
                    // the track sits on a gradient and a saturated bar would
                    // fight it.
                    LightBar(
                        pct = budget.pct,
                        color = when {
                            budget.overLimit -> Color(0xFFF0D8C9)
                            budget.atOrOverThreshold -> Color(0xFFF3E4C6)
                            else -> Color(0xFFDDE7C9)
                        },
                    )
                }
            }
        }
    }
}

/* ------------------------------- Goals ------------------------------ */

@Composable
private fun GoalsTile(onOpen: (() -> Unit)?) {
    val viewModel: GoalsTileViewModel = viewModel()
    val rows by viewModel.rows.collectAsState()

    HeroTile(S.Dashboard.tileGoals(sRes()), HeroTint.GOALS, onOpen) {
        if (rows.isEmpty()) {
            SanvyaText(S.Dashboard.emptyGoals(sRes()), style = SanvyaType.body, color = heroInkMuted)
            return@HeroTile
        }
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            rows.forEach { goal ->
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(modifier = Modifier.fillMaxWidth()) {
                        SanvyaText(
                            goal.name + if (goal.isEmergencyFund) " · " + S.Dashboard.efShort(sRes()) else "",
                            style = SanvyaType.statLabel,
                            color = heroInk,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        SanvyaText(
                            formatMoney(goal.savedMinor, goal.currency) +
                                " / " + formatMoney(goal.targetMinor, goal.currency),
                            style = SanvyaType.statLabel,
                            color = heroInkMuted,
                            maxLines = 1,
                        )
                    }
                    LightBar(
                        pct = goal.pct,
                        color = if (goal.isEmergencyFund) Color(0xFFC6CDB3) else Color(0xFFF3E4C6),
                    )
                }
            }
        }
    }
}

/* ------------------------------ Splits ------------------------------ */

@Composable
private fun SplitsTile(onOpen: (() -> Unit)?) {
    val colors = LocalSanvyaColors.current
    val viewModel: SplitsTileViewModel = viewModel()
    val state by viewModel.state.collectAsState()
    val currency = baseCurrencyNow()

    TileShell(S.Dashboard.tileSplits(sRes()), onOpen) {
        Row(horizontalArrangement = Arrangement.spacedBy(20.dp), modifier = Modifier.fillMaxWidth()) {
            Column {
                SanvyaText(S.Dashboard.youAreOwed(sRes()), style = SanvyaType.statLabel, color = colors.text2)
                SanvyaText(formatMoney(state.owedMinor, currency), style = SanvyaType.statValue, color = colors.positive)
            }
            Column {
                SanvyaText(S.Dashboard.youOwe(sRes()), style = SanvyaType.statLabel, color = colors.text2)
                SanvyaText(formatMoney(state.oweMinor, currency), style = SanvyaType.statValue, color = colors.negative)
            }
        }
        if (state.rows.isEmpty()) {
            Column(Modifier.padding(top = 10.dp)) {
                SanvyaText(S.Dashboard.emptySplits(sRes()), style = SanvyaType.statLabel, color = colors.text2)
            }
            return@TileShell
        }
        Column(
            verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.padding(top = 10.dp),
        ) {
            state.rows.forEach { row ->
                Row(modifier = Modifier.fillMaxWidth()) {
                    SanvyaText(
                        row.name,
                        style = SanvyaType.statLabel,
                        color = colors.text,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    SanvyaText(
                        if (row.netMinor > 0) {
                            // Web builds this as `owes you ${amount}` from the
                            // same two inline fragments; they exist as keys
                            // because Splits already renders them.
                            S.Splits.owesYouInline(sRes()) + " " + formatMoney(row.netMinor, currency)
                        } else {
                            S.Splits.youOweInline(sRes()) + " " + formatMoney(-row.netMinor, currency)
                        },
                        style = SanvyaType.statLabel,
                        color = if (row.netMinor > 0) colors.positive else colors.negative,
                        maxLines = 1,
                    )
                }
            }
            if (state.hiddenCount > 0) {
                SanvyaText(
                    S.Dashboard.moreItems(sRes(), state.hiddenCount),
                    style = SanvyaType.statLabel,
                    color = colors.text2,
                )
            }
        }
    }
}

/* -------------------- By category / by label ------------------- */

/**
 * Web's `HBarTile` — a ranked horizontal bar per row.
 *
 * The bars are the shared `SanvyaBarsChart`, which was `private` inside the
 * Insights screen until 2026-08-26. Two tiles differing only in what they group
 * by is exactly the case for one shell, which is what web does too.
 */
@Composable
private fun HBarTile(
    title: String,
    rows: List<NamedTotalRow>,
    emptyText: String,
    onOpen: (() -> Unit)?,
) {
    val colors = LocalSanvyaColors.current
    val currency = baseCurrencyNow()
    val uncategorised = S.Transactions.uncategorised(sRes())

    TileShell(title, onOpen) {
        if (rows.isEmpty()) {
            TileEmpty(emptyText)
            return@TileShell
        }
        SanvyaBarsChart(
            series = rows.map { row ->
                SeriesPoint(
                    label = row.name?.takeIf { it.isNotBlank() } ?: uncategorised,
                    // MAJOR units: the chart labels its own values, and a bar
                    // labelled in minor units would read as 100x the money.
                    value = toMajor(Money(row.totalMinor, currency)),
                )
            },
            horizontal = true,
            accent = colors.accent,
            colors = colors,
        )
    }
}

@Composable
private fun ByCategoryTile(onOpen: (() -> Unit)?) {
    val viewModel: ByCategoryTileViewModel = viewModel()
    val rows by viewModel.rows.collectAsState()
    HBarTile(S.Dashboard.tileByCategory(sRes()), rows, S.Dashboard.emptySpending(sRes()), onOpen)
}

@Composable
private fun ByLabelTile(onOpen: (() -> Unit)?) {
    val viewModel: ByLabelTileViewModel = viewModel()
    val rows by viewModel.rows.collectAsState()
    HBarTile(S.Dashboard.tileByLabel(sRes()), rows, S.Dashboard.emptyLabels(sRes()), onOpen)
}

/* ---------------------- This month vs last --------------------- */

@Composable
private fun MonthCompareTile(onOpen: (() -> Unit)?) {
    val colors = LocalSanvyaColors.current
    val viewModel: MonthCompareTileViewModel = viewModel()
    val state by viewModel.state.collectAsState()
    val currency = baseCurrencyNow()

    TileShell(S.Dashboard.tileMonthCompare(sRes()), onOpen) {
        if (state.isEmpty) {
            TileEmpty(S.Dashboard.emptySpending(sRes()))
            return@TileShell
        }
        // Four bars, not a grouped pair per month: the shared bars chart draws
        // one series, and web's grouping is a recharts affordance rather than
        // information. The colour carries income-vs-expense, and the legend
        // below names it -- which is what web's own ChartLegend does.
        SanvyaBarsChart(
            series = listOf(
                SeriesPoint(S.Dashboard.lastMonth(sRes()) + " · " + S.Cashflow.dirLabelIncome(sRes()), toMajor(Money(state.lastIncomeMinor, currency)), "positive"),
                SeriesPoint(S.Dashboard.lastMonth(sRes()) + " · " + S.Cashflow.dirLabelPayment(sRes()), toMajor(Money(state.lastExpenseMinor, currency)), "accent"),
                SeriesPoint(S.Dashboard.thisMonth(sRes()) + " · " + S.Cashflow.dirLabelIncome(sRes()), toMajor(Money(state.thisIncomeMinor, currency)), "positive"),
                SeriesPoint(S.Dashboard.thisMonth(sRes()) + " · " + S.Cashflow.dirLabelPayment(sRes()), toMajor(Money(state.thisExpenseMinor, currency)), "accent"),
            ),
            horizontal = true,
            accent = colors.accent,
            colors = colors,
        )
    }
}

/* ---------------------------- Trends --------------------------- */

/** Formats a bucket's start date for the axis. The DATE is what domain returns;
 *  the label is built here, with the device's locale, because web's version
 *  hardcodes English month names. */
private fun bucketLabel(startIso: String, period: TrendPeriod): String {
    val date = runCatching { LocalDate.parse(startIso) }.getOrNull() ?: return startIso
    val pattern = if (period == TrendPeriod.ONE_YEAR) "MMM" else "d MMM"
    return date.format(DateTimeFormatter.ofPattern(pattern))
}

@Composable
private fun trendPeriodLabel(period: TrendPeriod): String = when (period) {
    TrendPeriod.THREE_DAYS -> S.Dashboard.trendLast3d(sRes())
    TrendPeriod.ONE_WEEK -> S.Dashboard.trendLast1w(sRes())
    TrendPeriod.ONE_YEAR -> S.Dashboard.trendLast1y(sRes())
    else -> S.Dashboard.trendLast1m(sRes())
}

@Composable
private fun TrendsTile(onOpen: (() -> Unit)?) {
    val colors = LocalSanvyaColors.current
    val viewModel: TrendsTileViewModel = viewModel()
    val period by viewModel.period.collectAsState()
    val buckets by viewModel.buckets.collectAsState()
    val totalMinor by viewModel.totalMinor.collectAsState()
    val currency = baseCurrencyNow()

    TileShell(S.Dashboard.tileTrends(sRes()), onOpen) {
        // Chips, not web's <select>: this codebase has no select component, and
        // four options is what a chip row is for.
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TrendPeriod.entries.forEach { option ->
                SanvyaChip(
                    label = trendPeriodLabel(option),
                    active = option == period,
                    onClick = { viewModel.setPeriod(option) },
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        SanvyaText(
            S.Dashboard.spent(sRes(), formatMoney(totalMinor, currency)) + " · " + trendPeriodLabel(period),
            style = SanvyaType.statLabel,
            color = colors.text2,
        )
        Spacer(Modifier.height(8.dp))
        Box(Modifier.fillMaxWidth().height(140.dp)) {
            SanvyaAreaChart(
                series = buckets.map {
                    SeriesPoint(bucketLabel(it.startIso, period), toMajor(Money(it.totalMinor, currency)))
                },
                accent = colors.accent,
            )
        }
    }
}

/* ------------------- Cashflow / net trend ---------------------- */

@Composable
private fun CashflowTile(onOpen: (() -> Unit)?) {
    val viewModel: CashflowTileViewModel = viewModel()
    val months by viewModel.months.collectAsState()
    val currency = baseCurrencyNow()

    HeroTile(S.Dashboard.tileCashflow(sRes()), HeroTint.CASHFLOW, onOpen) {
        if (months.isEmpty()) {
            SanvyaText(S.Dashboard.emptyCashflow(sRes()), style = SanvyaType.body, color = heroInkMuted)
            return@HeroTile
        }
        val totalIn = months.sumOf { it.incomeMinor }
        val totalOut = months.sumOf { it.expenseMinor }
        val net = totalIn - totalOut
        Row(verticalAlignment = Alignment.Bottom) {
            SanvyaText(
                (if (net >= 0) "+" else "−") + formatMoney(kotlin.math.abs(net), currency),
                style = SanvyaType.statValue,
                color = heroInk,
            )
            SanvyaText(
                " " + S.Dashboard.net(sRes()),
                style = SanvyaType.statLabel,
                color = heroInkMuted,
                modifier = Modifier.padding(bottom = 4.dp),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            SanvyaText(
                S.Dashboard.inflow(sRes()) + " " + formatMoney(totalIn, currency),
                style = SanvyaType.statLabel,
                color = heroInkMuted,
            )
            SanvyaText(
                S.Dashboard.outflow(sRes()) + " " + formatMoney(totalOut, currency),
                style = SanvyaType.statLabel,
                color = heroInkMuted,
            )
        }
        Box(Modifier.fillMaxWidth().height(70.dp)) {
            SanvyaAreaChart(
                series = months.map { SeriesPoint(it.month, toMajor(Money(it.netMinor, currency))) },
                accent = heroInk,
            )
        }
    }
}

@Composable
private fun NetTrendTile(onOpen: (() -> Unit)?) {
    val colors = LocalSanvyaColors.current
    val viewModel: CashflowTileViewModel = viewModel()
    val months by viewModel.months.collectAsState()
    val currency = baseCurrencyNow()

    TileShell(S.Dashboard.tileNetTrend(sRes()), onOpen) {
        if (months.isEmpty()) {
            TileEmpty(S.Dashboard.emptyCashflow(sRes()))
            return@TileShell
        }
        Box(Modifier.fillMaxWidth().height(140.dp)) {
            SanvyaAreaChart(
                series = months.map { SeriesPoint(it.month, toMajor(Money(it.netMinor, currency))) },
                accent = colors.accent,
            )
        }
    }
}

/* ------------------------ Subscriptions ------------------------ */

@Composable
private fun SubscriptionsTile(onOpen: (() -> Unit)?) {
    val viewModel: SubscriptionsTileViewModel = viewModel()
    val state by viewModel.state.collectAsState()
    val currency = baseCurrencyNow()

    HeroTile(S.Dashboard.tileSubscriptions(sRes()), HeroTint.SUBS, onOpen) {
        if (state.rows.isEmpty()) {
            SanvyaText(S.Dashboard.emptySubscriptions(sRes()), style = SanvyaType.body, color = heroInkMuted)
            return@HeroTile
        }
        Row(verticalAlignment = Alignment.Bottom) {
            SanvyaText(formatMoney(state.monthlyMinor, currency), style = SanvyaType.statValue, color = heroInk)
            SanvyaText(
                " " + S.Dashboard.perMonth(sRes()),
                style = SanvyaType.statLabel,
                color = heroInkMuted,
                modifier = Modifier.padding(bottom = 4.dp),
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            state.rows.forEach { row ->
                Row(modifier = Modifier.fillMaxWidth()) {
                    SanvyaText(
                        row.name,
                        style = SanvyaType.statLabel,
                        color = heroInk,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    SanvyaText(row.dueIso, style = SanvyaType.statLabel, color = heroInkMuted)
                }
            }
            if (state.hiddenCount > 0) {
                SanvyaText(
                    S.Dashboard.moreItems(sRes(), state.hiddenCount),
                    style = SanvyaType.statLabel,
                    color = heroInkMuted,
                )
            }
        }
    }
}

/* ----------------------- Across currencies --------------------- */

@Composable
private fun CurrenciesTile(onOpen: (() -> Unit)?) {
    val colors = LocalSanvyaColors.current
    val viewModel: CurrenciesTileViewModel = viewModel()
    val slices by viewModel.slices.collectAsState()
    val base = baseCurrencyNow()

    TileShell(S.Dashboard.tileCurrencies(sRes()), onOpen) {
        // Web draws nothing below two currencies, and says so: one full-width
        // bar labelled with the only currency you hold is not information.
        if (slices.size < 2) {
            TileEmpty(S.Dashboard.singleCurrency(sRes(), base))
            return@TileShell
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(10.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(colors.surface2),
        ) {
            slices.forEachIndexed { index, slice ->
                if (slice.sharePct <= 0) return@forEachIndexed
                Box(
                    Modifier
                        .weight(slice.sharePct.toFloat())
                        .fillMaxHeight()
                        .background(DASHBOARD_CHART_COLORS[index % DASHBOARD_CHART_COLORS.size]),
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            slices.forEachIndexed { index, slice ->
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Spacer(
                        Modifier
                            .size(9.dp)
                            .clip(RoundedCornerShape(999.dp))
                            .background(DASHBOARD_CHART_COLORS[index % DASHBOARD_CHART_COLORS.size]),
                    )
                    Spacer(Modifier.width(6.dp))
                    SanvyaText(slice.currency, style = SanvyaType.statLabel, color = colors.text)
                    Spacer(Modifier.width(6.dp))
                    SanvyaText(
                        formatMoney(slice.nativeMinor, slice.currency),
                        style = SanvyaType.statLabel,
                        color = colors.text2,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    SanvyaText(
                        (if (slice.currency == base) "" else "≈ " + formatMoney(slice.baseMinor, base) + " · ") +
                            "${slice.sharePct}%",
                        style = SanvyaType.statLabel,
                        color = colors.text2,
                    )
                }
            }
        }
    }
}
