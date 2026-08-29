package com.sanvya.app.ui.investments

import android.content.res.Resources
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.insights.DividendPeriod
import com.sanvya.app.domain.insights.SeriesPoint
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.ui.components.Eyebrow
import com.sanvya.app.ui.components.SanvyaAreaChart
import com.sanvya.app.ui.components.SanvyaBarsChart
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.components.SanvyaPage
import kotlinx.coroutines.launch

/**
 * Ported from apps/web/app/investments/page.tsx per
 * docs/mobile/screen-specs/investments.md.
 *
 * Web's grouping (by exchange for stocks, by asset class for everything else)
 * + drill-in navigation is preserved as in-screen state (selected group key),
 * not a separate nav route -- it's just a filtered view of the same list,
 * matching web's own DrillIn being page-local state rather than a route. Edit
 * is inline within the holding row (web's own EditHolding behavior).
 *
 * The insights section (dividends-this-FY card, allocation donut, gain/loss
 * bars) and the two interactive panels below it are page.tsx's, in page.tsx's
 * order, and were absent from this port entirely until now. They render only
 * on the group grid, never inside a drill-in, because they describe the WHOLE
 * portfolio and web hides them the same way.
 *
 * Every label on this screen resolves through `S.Investments`. The view model
 * hands over keys and numbers, never sentences -- see InvestmentsViewModel's
 * HoldingUiModel comment for why that boundary moved.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InvestmentsScreen(
    onBack: () -> Unit = {},
    onAddInvestment: (groupKey: String?) -> Unit = {},
    onNoInvestmentAccount: () -> Unit = {},
    viewModel: InvestmentsViewModel = viewModel(),
) {
    val groups by viewModel.groups.collectAsState()
    val totalValue by viewModel.totalValueFormatted.collectAsState()
    val totalCost by viewModel.totalCostFormatted.collectAsState()
    val totalGain by viewModel.totalGainFormatted.collectAsState()
    val totalGainPositive by viewModel.totalGainPositive.collectAsState()
    val invAccounts by viewModel.invAccounts.collectAsState()
    val colors = LocalSanvyaColors.current
    val res = sRes()
    val scope = rememberCoroutineScope()

    // Drill-in state: which group tile is expanded, or null for the group
    // grid. Bundle-savable (a plain String), matching this session's
    // fold/rotation lifecycle-retrofit convention (P3.19).
    var drilledKey by rememberSaveable { mutableStateOf<String?>(null) }
    val drilledGroup = groups.find { it.key == drilledKey }

    SanvyaPage(
        title = drilledGroup?.let { groupDisplayLabel(it.key, res) } ?: S.Translation.navInvestments(res),
        action = {
            if (invAccounts.isNotEmpty()) {
                IconButton(onClick = { onAddInvestment(drilledGroup?.key) }) {
                    Icon(Icons.Default.Add, contentDescription = S.Investments.addInvestment(res), tint = colors.accent)
                }
            }
        },
    ) {
        if (invAccounts.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("▲", fontSize = 26.sp, color = colors.accent)
                    Text(S.Investments.noInvAccountTitle(res), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    // Web writes this sentence in three pieces so "Demat" can be
                    // emphasised mid-sentence; the pieces are joined here rather
                    // than a fourth key being invented for the whole line.
                    Text(
                        S.Investments.noInvAccountBodyPre(res) + S.Investments.demat(res) + S.Investments.noInvAccountBodyPost(res),
                        fontSize = 14.sp,
                        color = colors.text2,
                        textAlign = TextAlign.Center,
                    )
                    Button(onClick = onNoInvestmentAccount, modifier = Modifier.padding(top = 4.dp)) {
                        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(S.Investments.addInvAccount(res))
                    }
                }
            }
            return@SanvyaPage
        }

        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (drilledGroup == null) {
                PortfolioTotalCard(totalValue, totalCost, totalGain, totalGainPositive)
                if (groups.isEmpty()) {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                        Text(S.Investments.noInvestments(res), fontSize = 14.sp, color = colors.text2, textAlign = TextAlign.Center)
                    }
                } else {
                    Eyebrow(S.Investments.byExchangeScheme(res))
                    groups.forEach { g ->
                        GroupTile(group = g, onClick = { drilledKey = g.key })
                    }
                    InsightsSection(viewModel)
                    DividendPanel(viewModel)
                    ProjectionPanel(viewModel)
                }
            } else {
                drilledGroup.holdings.forEach { h ->
                    HoldingTile(
                        holding = h,
                        onUpdate = { qty, avgCost, curVal, rate ->
                            scope.launch { viewModel.updateHolding(h.id, qty, avgCost, curVal, rate, h.currency) }
                        },
                        onDelete = { viewModel.deleteHolding(h.id) },
                        onStopSip = { viewModel.stopSip(h.id) },
                    )
                }
                TextButton(onClick = { onAddInvestment(drilledGroup.key) }) {
                    Text(
                        S.Investments.addTo(res, groupDisplayLabel(drilledGroup.key, res)),
                        color = colors.accent,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}

// --- label resolution -------------------------------------------------------

/**
 * The display name of a group key.
 *
 * Domain's `groupLabel()` returns web's English ("Mutual Funds", "Stocks
 * (other)") and is kept exactly as it is, because it is also the SORT key that
 * orders the tiles identically on all three platforms. Translating it there
 * would reorder the screen per language. So the English one sorts and this one
 * shows. An exchange group is its exchange CODE -- "NSE_IN" is a proper noun,
 * not a word.
 */
internal fun groupDisplayLabel(key: String, res: Resources): String {
    if (key.startsWith("ex:")) {
        val ex = key.substring(3)
        return if (ex == "OTHER") S.Investments.groupTitleStocksOther(res) else ex
    }
    return when (key.removePrefix("cls:")) {
        "stock" -> S.Investments.groupTitleStock(res)
        "mf" -> S.Investments.groupTitleMf(res)
        "sip" -> S.Investments.groupTitleSip(res)
        "crypto" -> S.Investments.groupTitleCrypto(res)
        "fd" -> S.Investments.groupTitleFd(res)
        "other" -> S.Investments.groupTitleOther(res)
        else -> S.Investments.groupTitleFallback(res)
    }
}

/** The display name of an asset class. Same split as [groupDisplayLabel]:
 * Domain keeps web's English for parity, the screen shows the user's. */
internal fun assetClassDisplayLabel(key: String, res: Resources): String = when (key) {
    "stock" -> S.Investments.assetClassStock(res)
    "mf" -> S.Investments.assetClassMf(res)
    "sip" -> S.Investments.assetClassSip(res)
    "crypto" -> S.Investments.assetClassCrypto(res)
    "fd" -> S.Investments.assetClassFd(res)
    else -> S.Investments.assetClassOther(res)
}

/** "shares" / "units" / "coins". Null in, null out -- a fixed deposit has a
 * principal, not a countable unit. */
internal fun unitWordLabel(key: String?, res: Resources): String? = when (key) {
    "shares" -> S.Investments.unitWordShares(res)
    "units" -> S.Investments.unitWordUnits(res)
    "coins" -> S.Investments.unitWordCoins(res)
    else -> null
}

/** Localises a view-model failure. The view model has no `Resources` and must
 * not hold one (see I18n.kt), so the enum crosses the boundary and the message
 * is built here. */
internal fun investmentFormMessage(failure: InvestmentFormFailure, res: Resources): String = when (failure.error) {
    InvestmentFormError.QUANTITY -> S.Investments.errQuantity(res)
    InvestmentFormError.NAME -> S.Investments.errName(res)
    InvestmentFormError.INSTRUMENT -> S.Investments.errInstrument(res)
    InvestmentFormError.FUNDING_ACCOUNT -> S.Investments.errFundingAccount(res)
    InvestmentFormError.OVER_FUNDS -> S.Investments.overFunds(res, failure.accountName ?: "")
    InvestmentFormError.SIP_AMOUNT -> S.Investments.errSipAmount(res)
    InvestmentFormError.SIP_SOURCE -> S.Investments.errSipSource(res)
    InvestmentFormError.NO_USER -> S.Investments.errNoUser(res)
    InvestmentFormError.ADD_FAILED -> S.Investments.errAddFailed(res)
    InvestmentFormError.SAVE_FAILED -> S.Investments.errSaveFailed(res)
    InvestmentFormError.HOLDING_NOT_FOUND -> S.Investments.errHoldingNotFound(res)
    InvestmentFormError.INVALID_QUANTITY -> S.Investments.errInvalidQuantity(res)
}

// --- pieces -----------------------------------------------------------------

@Composable
private fun SectionCard(content: @Composable () -> Unit) {
    val colors = LocalSanvyaColors.current
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
    }
}

/** One figure with its caption. Takes a [modifier] so a row of three can
 * share the width evenly -- three money strings side by side overflow a phone
 * otherwise, and Compose clips rather than wrapping. */
@Composable
private fun Stat(label: String, value: String, modifier: Modifier = Modifier, color: Color? = null) {
    val colors = LocalSanvyaColors.current
    Column(modifier = modifier) {
        Text(label, fontSize = 12.sp, color = colors.text2, maxLines = 2)
        Text(value, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = color ?: colors.text, maxLines = 1)
    }
}

@Composable
private fun PortfolioTotalCard(valueFormatted: String, costFormatted: String, gainFormatted: String, gainPositive: Boolean) {
    val colors = LocalSanvyaColors.current
    val res = sRes()
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(S.Investments.currentValue(res), fontSize = 12.sp, fontWeight = FontWeight.Medium, color = colors.text2)
            Text(valueFormatted, fontSize = 30.sp, fontWeight = FontWeight.Bold, color = colors.text)
            // Web's grand total puts Invested next to Current value: without the
            // cost there is no way to read what the gain figure is a gain ON.
            Text(S.Investments.investedLabel(res, costFormatted), fontSize = 12.sp, color = colors.text2)
            Text(
                gainFormatted,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (gainPositive) colors.positive else colors.negative,
            )
            Text(S.Investments.syncNote(res), fontSize = 11.sp, color = colors.text3)
        }
    }
}

@Composable
private fun GroupTile(group: GroupUiModel, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val res = sRes()
    val tint = if (group.gainPositive) colors.positive else colors.negative
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column {
                    Text(groupDisplayLabel(group.key, res), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    Text(S.Investments.holdingsCount(res, group.holdingsCount), fontSize = 12.sp, color = colors.text2)
                }
                Text(group.gainPctFormatted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = tint)
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(group.valueFormatted, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = colors.text)
                Text(group.gainFormatted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = tint)
            }
            Text(S.Investments.investedLabel(res, group.costFormatted), fontSize = 12.sp, color = colors.text2)
        }
    }
}

/**
 * Web's Insights band: the dividends-this-financial-year card, the allocation
 * donut and the gain/loss-by-group bars, in that order. Three side-by-side
 * cards on a desktop grid; three stacked cards on a phone.
 */
@Composable
private fun InsightsSection(viewModel: InvestmentsViewModel) {
    val colors = LocalSanvyaColors.current
    val res = sRes()
    val allocation by viewModel.allocation.collectAsState()
    val gainBars by viewModel.gainByGroup.collectAsState()
    val dividendFy by viewModel.dividendFyFormatted.collectAsState()
    val fy by viewModel.currentFy.collectAsState()
    val totalValue by viewModel.totalValueFormatted.collectAsState()

    Spacer(Modifier.height(2.dp))
    Eyebrow(S.Investments.insights(res))

    SectionCard {
        Text(
            S.Investments.dividendsEarned(res, S.Investments.fyLabel(res, fy.startYear, fy.endYearShort)),
            fontSize = 12.sp,
            color = colors.text2,
        )
        Text(dividendFy, fontSize = 28.sp, fontWeight = FontWeight.Bold, color = colors.positive)
        Text(S.Investments.dividendsNote(res), fontSize = 11.sp, color = colors.text3)
    }

    SectionCard {
        Eyebrow(S.Investments.allocation(res))
        AllocationDonut(
            slices = allocation.map {
                DonutSlice(groupDisplayLabel(it.groupKey, res), it.valueMajor, it.valueFormatted, it.sharePct)
            },
            centerLabel = S.Investments.total(res),
            centerValue = totalValue,
            emptyLabel = S.Investments.allocationEmpty(res),
        )
    }

    SectionCard {
        Eyebrow(S.Investments.gainLossByGroup(res))
        SignedBarsChart(
            bars = gainBars.map {
                SignedBar(groupDisplayLabel(it.groupKey, res), it.gainMajor, it.gainFormatted, it.positive)
            },
            emptyLabel = S.Investments.gainsEmpty(res),
        )
    }
}

/**
 * Web's DividendPanel: period chips over a bar chart of income by bucket,
 * with trailing / forward / all-time totals above it.
 *
 * Self-hides with no holdings, exactly as web's does -- a dividend chart on an
 * empty portfolio is a chart of nothing.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DividendPanel(viewModel: InvestmentsViewModel) {
    val colors = LocalSanvyaColors.current
    val res = sRes()
    val panel by viewModel.dividendPanel.collectAsState()
    val period by viewModel.dividendPeriod.collectAsState()
    if (!panel.hasHoldings) return

    SectionCard {
        Text(S.Investments.dividendIncome(res), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = colors.text)
        // Five period chips do not fit across a phone, so the row scrolls
        // rather than wrapping -- web wraps because it has the width.
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        ) {
            DIVIDEND_PERIODS.forEach { p ->
                FilterChip(
                    selected = p == period,
                    onClick = { viewModel.dividendPeriod.value = p },
                    label = { Text(dividendPeriodLabel(p, res), fontSize = 12.sp) },
                )
            }
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Stat(S.Investments.last12Months(res), panel.trailing12Formatted, Modifier.weight(1f))
            Stat(S.Investments.next12Months(res), panel.upcoming12Formatted, Modifier.weight(1f), colors.accent)
            Stat(S.Investments.allTime(res), panel.totalFormatted, Modifier.weight(1f))
        }
        if (!panel.hasEvents) {
            Text(S.Investments.noDividendData(res), fontSize = 12.sp, color = colors.text2)
        } else {
            Box(Modifier.fillMaxWidth().height(180.dp)) {
                SanvyaBarsChart(
                    series = panel.buckets.map {
                        // Upcoming buckets are the warning tone, matching web's
                        // amber bars -- the chart mixes money already received
                        // with money merely scheduled, and nothing else on the
                        // card says which is which.
                        SeriesPoint(it.label, it.valueMajor, if (it.upcoming) "warning" else "positive")
                    },
                    horizontal = false,
                    accent = colors.accent,
                    colors = colors,
                )
            }
        }
        Text(S.Investments.dividendFootnote(res), fontSize = 11.sp, color = colors.text3)
    }
}

private val DIVIDEND_PERIODS = listOf(
    DividendPeriod.WEEK, DividendPeriod.MONTH, DividendPeriod.QUARTER, DividendPeriod.YEAR, DividendPeriod.ALL,
)

private fun dividendPeriodLabel(p: DividendPeriod, res: Resources): String = when (p) {
    DividendPeriod.WEEK -> S.Investments.divPeriodWeek(res)
    DividendPeriod.MONTH -> S.Investments.divPeriodMonth(res)
    DividendPeriod.QUARTER -> S.Investments.divPeriodQuarter(res)
    DividendPeriod.YEAR -> S.Investments.divPeriodYear(res)
    DividendPeriod.ALL -> S.Investments.divPeriodAll(res)
}

/**
 * Web's ProjectionPanel: the compounded curve, with the three assumptions and
 * the reinvest switch under it.
 *
 * The maths is `domain.investments.projectPortfolio` and is vector-pinned; the
 * only thing here is the controls. Self-hides with no holdings, like web's.
 *
 * Note the current value it starts from is the portfolio's book value, not a
 * live one -- this port has no quote source, so the same simplification that
 * `valuation()` documents applies to the projection's opening balance.
 */
@Composable
private fun ProjectionPanel(viewModel: InvestmentsViewModel) {
    val colors = LocalSanvyaColors.current
    val res = sRes()
    val panel by viewModel.projectionPanel.collectAsState()
    val growth by viewModel.projectionGrowthPct.collectAsState()
    val monthly by viewModel.projectionMonthlyMajor.collectAsState()
    val years by viewModel.projectionYears.collectAsState()
    val reinvest by viewModel.projectionReinvest.collectAsState()
    if (!panel.hasHoldings) return

    SectionCard {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
            Text(S.Investments.projectedWealth(res), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = colors.text)
            Text(S.Investments.inYears(res, years), fontSize = 12.sp, color = colors.text2)
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Stat(S.Investments.projectedValue(res), panel.endValueFormatted, Modifier.weight(1f), colors.accent)
            Stat(S.Investments.youPutIn(res), panel.contributedFormatted, Modifier.weight(1f))
            Stat(S.Investments.growthPlusDividends(res), panel.growthFormatted, Modifier.weight(1f), colors.positive)
        }
        Box(Modifier.fillMaxWidth().height(180.dp)) {
            SanvyaAreaChart(series = panel.series.map { SeriesPoint(it.first, it.second) }, accent = colors.accent)
        }
        AssumptionSlider(
            label = S.Investments.assumedGrowth(res),
            display = "${"%.1f".format(growth)}%",
            value = growth.toFloat(),
            range = 0f..15f,
            steps = 29,
            onChange = { viewModel.projectionGrowthPct.value = it.toDouble() },
        )
        AssumptionSlider(
            label = S.Investments.monthlyContribution(res, baseCurrencyNow()),
            display = "%.0f".format(monthly),
            value = monthly.toFloat(),
            range = 0f..5000f,
            steps = 99,
            onChange = { viewModel.projectionMonthlyMajor.value = it.toDouble() },
        )
        AssumptionSlider(
            label = S.Investments.horizon(res),
            display = years.toString(),
            value = years.toFloat(),
            range = 1f..40f,
            steps = 38,
            onChange = { viewModel.projectionYears.value = it.toInt() },
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Switch(checked = reinvest, onCheckedChange = { viewModel.projectionReinvest.value = it })
            Text(S.Investments.reinvestDividends(res), fontSize = 13.sp, color = colors.text)
            if (panel.hasYield) {
                Text(S.Investments.reinvestYield(res, panel.yieldPctFormatted), fontSize = 12.sp, color = colors.text2)
            }
        }
        Text(S.Investments.projectionFootnote(res), fontSize = 11.sp, color = colors.text3)
    }
}

@Composable
private fun AssumptionSlider(
    label: String,
    display: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    steps: Int,
    onChange: (Float) -> Unit,
) {
    val colors = LocalSanvyaColors.current
    Column {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, fontSize = 12.sp, color = colors.text2)
            Text(display, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
        }
        Slider(value = value, onValueChange = onChange, valueRange = range, steps = steps)
    }
}

/** "Zerodha-style" holding row, matching web's HoldingTile: left side is
 * label + off-list "untracked" chip + qty; right side is value + gain;
 * bottom row is asset-class meta + FD extras. Tapping the edit icon
 * expands an inline edit form in place (web's EditHolding). */
@Composable
private fun HoldingTile(
    holding: HoldingUiModel,
    onUpdate: (String, String, String, String) -> Unit,
    onDelete: () -> Unit,
    onStopSip: () -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val res = sRes()
    var editing by rememberSaveable(holding.id) { mutableStateOf(false) }
    var showDeleteConfirm by rememberSaveable(holding.id) { mutableStateOf(false) }
    var showStopSipConfirm by rememberSaveable(holding.id) { mutableStateOf(false) }
    var quantityText by rememberSaveable(holding.id, editing) { mutableStateOf(holding.quantityPlain) }
    var avgCostText by rememberSaveable(holding.id, editing) { mutableStateOf(holding.rawAvgCostMajor) }
    var currentValueText by rememberSaveable(holding.id, editing) { mutableStateOf(holding.rawCurrentValueMajor) }
    var annualRateText by rememberSaveable(holding.id, editing) { mutableStateOf(holding.rawAnnualRate) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Top) {
                Column(modifier = Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(holding.label, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = colors.text)
                        if (holding.offList) {
                            Box(
                                modifier = Modifier.clip(RoundedCornerShape(50)).background(colors.accentGhost)
                                    .padding(horizontal = 6.dp, vertical = 2.dp),
                            ) { Text(S.Investments.untracked(res), fontSize = 10.sp, color = colors.accent) }
                        }
                    }
                    val unit = unitWordLabel(holding.unitWordKey, res)
                    if (unit != null) {
                        Text("${holding.quantityPlain} $unit", fontSize = 12.sp, color = colors.text2)
                    }
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(holding.valueFormatted, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    if (holding.hasCostBasis) {
                        Text(
                            holding.gainFormatted,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (holding.gainPositive) colors.positive else colors.negative,
                        )
                    }
                }
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                // A running SIP is a standing debit on a real account and has no
                // other home in the app -- recurring savings are not browsable
                // under Recurring -- so it has to be legible and stoppable right
                // here, exactly as web's HoldingTile does it.
                Text(holdingMetaLine(holding, res), fontSize = 11.sp, color = colors.text2, modifier = Modifier.weight(1f))
                Row {
                    if (holding.sipOn) {
                        TextButton(onClick = { showStopSipConfirm = true }, contentPadding = PaddingValues(horizontal = 8.dp)) {
                            Text(S.Investments.stopSip(res), fontSize = 11.sp, color = colors.warning)
                        }
                    }
                    IconButton(onClick = { editing = !editing }, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Default.Edit, contentDescription = S.Investments.edit(res), tint = colors.text2, modifier = Modifier.size(16.dp))
                    }
                    IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Default.Delete, contentDescription = S.Investments.remove(res), tint = colors.negative, modifier = Modifier.size(16.dp))
                    }
                }
            }

            if (editing) {
                HorizontalDivider()
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = quantityText, onValueChange = { quantityText = it },
                        label = { Text(unitWordLabel(holding.unitWordKey, res) ?: S.Investments.quantity(res)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = avgCostText, onValueChange = { avgCostText = it },
                        label = { Text(S.Investments.avgCost(res, holding.currency)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    // Web's EditHolding shows the current-value and rate fields
                    // only for an UNPRICED holding: a listed one's value comes
                    // from the market, so a field for it would be a lie.
                    if (!holding.isListedClass) {
                        OutlinedTextField(
                            value = currentValueText, onValueChange = { currentValueText = it },
                            label = { Text(S.Investments.currentValueCur(res, holding.currency)) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        if (holding.assetClassKey == "fd") {
                            OutlinedTextField(
                                value = annualRateText, onValueChange = { annualRateText = it },
                                label = { Text(S.Investments.interestPa(res)) },
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = { editing = false }) { Text(S.Investments.cancel(res)) }
                        Button(onClick = {
                            onUpdate(quantityText, avgCostText, currentValueText, annualRateText)
                            editing = false
                        }) { Text(S.Investments.save(res)) }
                    }
                }
            }

            if (showStopSipConfirm) {
                AlertDialog(
                    onDismissRequest = { showStopSipConfirm = false },
                    title = { Text(S.Investments.stopSipTitle(res)) },
                    text = { Text(S.Investments.stopSipMsg(res)) },
                    confirmButton = {
                        TextButton(onClick = { onStopSip(); showStopSipConfirm = false }) { Text(S.Investments.stopSip(res)) }
                    },
                    dismissButton = { TextButton(onClick = { showStopSipConfirm = false }) { Text(S.Investments.cancel(res)) } },
                )
            }

            if (showDeleteConfirm) {
                AlertDialog(
                    onDismissRequest = { showDeleteConfirm = false },
                    title = { Text(S.Investments.removeTitle(res)) },
                    text = { Text(S.Investments.removeMsg(res, holding.label)) },
                    confirmButton = {
                        TextButton(onClick = { onDelete(); showDeleteConfirm = false }) { Text(S.Investments.remove(res), color = colors.negative) }
                    },
                    dismissButton = { TextButton(onClick = { showDeleteConfirm = false }) { Text(S.Investments.cancel(res)) } },
                )
            }
        }
    }
}

/**
 * The dot-separated meta line under a holding: class, exchange, FD rate and
 * maturity, then the live SIP amount -- web's order exactly.
 *
 * Built here rather than in the view model because every piece of it is a
 * translated word. A `·` separator is punctuation, not copy.
 */
private fun holdingMetaLine(h: HoldingUiModel, res: Resources): String {
    val parts = mutableListOf(assetClassDisplayLabel(h.assetClassKey, res))
    h.exchange?.let { parts.add(it) }
    h.annualRatePlain?.let { parts.add(S.Investments.perAnnum(res, it)) }
    h.maturityDate?.let { parts.add("${S.Investments.matures(res)} $it") }
    h.sipAmountFormatted?.let { parts.add("${S.Investments.sipLine(res)} $it") }
    return parts.joinToString(" · ")
}
