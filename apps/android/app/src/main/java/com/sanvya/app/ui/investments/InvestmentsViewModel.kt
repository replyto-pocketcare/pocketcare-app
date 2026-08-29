package com.sanvya.app.ui.investments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.AddHoldingInput
import com.sanvya.app.data.repository.DividendRow
import com.sanvya.app.data.repository.Holding
import com.sanvya.app.data.repository.HoldingFunding
import com.sanvya.app.data.repository.InvestmentsRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.SipSetup
import com.sanvya.app.domain.insights.DivEvent
import com.sanvya.app.domain.insights.DivRow
import com.sanvya.app.domain.insights.DividendPeriod
import com.sanvya.app.domain.insights.HoldingLite
import com.sanvya.app.domain.insights.bucketize
import com.sanvya.app.domain.insights.computeDividendEvents
import com.sanvya.app.domain.insights.dividendSummary
import com.sanvya.app.domain.investments.AssetClass
import com.sanvya.app.domain.investments.FinancialYear
import com.sanvya.app.domain.investments.Group
import com.sanvya.app.domain.investments.HoldingRow
import com.sanvya.app.domain.investments.Instrument
import com.sanvya.app.domain.investments.PortfolioTotals
import com.sanvya.app.domain.investments.SEED_INSTRUMENTS
import com.sanvya.app.domain.investments.allocationSlices
import com.sanvya.app.domain.investments.assetClassOf
import com.sanvya.app.domain.investments.buildGroups
import com.sanvya.app.domain.investments.clampSipDay
import com.sanvya.app.domain.investments.dividendYieldRate
import com.sanvya.app.domain.investments.dividendsThisFy
import com.sanvya.app.domain.investments.financialYear
import com.sanvya.app.domain.investments.gainBars
import com.sanvya.app.domain.investments.groupKeyOf
import com.sanvya.app.domain.investments.holdingLabel
import com.sanvya.app.domain.investments.isListed
import com.sanvya.app.domain.investments.knownExchanges
import com.sanvya.app.domain.investments.portfolioTotals
import com.sanvya.app.domain.investments.projectPortfolio
import com.sanvya.app.domain.investments.searchInstruments
import com.sanvya.app.domain.investments.valuation
import com.sanvya.app.domain.money.convert
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.money.money
import com.sanvya.app.ui.FormOptions
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.formatMajorPlain
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.majorScale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.LocalDate

data class InvAccountOption(val id: String, val name: String, val currency: String)
data class FundingAccountOption(val id: String, val name: String, val currency: String, val balanceFormatted: String, val balanceMinor: Long)

/**
 * A holding row, reduced to the pieces the screen needs -- and no further.
 *
 * The display STRINGS that used to live here (`metaLine`, `quantityLine`,
 * `fdExtra`) were built in this view model out of English literals and the
 * Domain enum's English `label`, so the holding row was the one part of the
 * screen no locale could reach. What crosses the boundary now is the asset
 * class KEY, the exchange code and the raw numbers; the composable joins them
 * with `S.Investments.*`. Same convention as GroupDetailViewModel's `nameOf`
 * and RecurringDirectionViewModel's category flag.
 */
data class HoldingUiModel(
    val id: String,
    val label: String,
    val assetClassKey: String,
    val exchange: String?,
    /** Plain quantity, no unit word -- the screen appends the localised one. */
    val quantityPlain: String,
    /** "shares" / "units" / "coins", or null for a lump asset with no unit. */
    val unitWordKey: String?,
    val valueFormatted: String,
    val costFormatted: String,
    val gainFormatted: String,
    val gainPositive: Boolean,
    val hasCostBasis: Boolean,
    val offList: Boolean,
    val isListedClass: Boolean,
    /** FD only: the rate as a plain number, for `investments:perAnnum`. */
    val annualRatePlain: String?,
    /** FD only: `yyyy-MM-dd`, for `investments:matures`. */
    val maturityDate: String?,
    // raw fields for the inline edit form
    val rawQuantity: Double,
    val rawAvgCostMajor: String,
    val rawCurrentValueMajor: String,
    val rawAnnualRate: String,
    val currency: String,
    /** True only while the holding still has a live SIP: `planned_id` alone
     * can point at a recurring row that was already stopped, so web gates on
     * `planned_id && sip_amount > 0` and so does this. */
    val sipOn: Boolean,
    val sipAmountFormatted: String?,
    /** The recurring row this SIP debits through, so Stop SIP can cancel it. */
    val plannedId: String?,
)

data class GroupUiModel(
    val key: String,
    val holdingsCount: Int,
    val valueFormatted: String,
    val costFormatted: String,
    val gainFormatted: String,
    val gainPositive: Boolean,
    val gainPctFormatted: String,
    val holdings: List<HoldingUiModel>,
)

/** One donut slice. `valueMajor` is a plottable Double; the formatted string
 * is what the legend shows, so no screen divides anything by anything. */
data class AllocationSliceUi(val groupKey: String, val valueMajor: Double, val sharePct: Double, val valueFormatted: String)

/** One signed gain/loss bar. */
data class GainBarUi(val groupKey: String, val gainMajor: Double, val gainFormatted: String, val positive: Boolean)

data class DividendBucketUi(val label: String, val valueMajor: Double, val upcoming: Boolean)

data class DividendPanelUi(
    val hasHoldings: Boolean = false,
    val hasEvents: Boolean = false,
    val buckets: List<DividendBucketUi> = emptyList(),
    val trailing12Formatted: String = "",
    val upcoming12Formatted: String = "",
    val totalFormatted: String = "",
)

data class ProjectionPanelUi(
    val hasHoldings: Boolean = false,
    val series: List<Pair<String, Double>> = emptyList(),
    val endValueFormatted: String = "",
    val contributedFormatted: String = "",
    val growthFormatted: String = "",
    /** The reinvestment yield as a percentage, for `investments:reinvestYield`. */
    val yieldPctFormatted: String = "",
    val hasYield: Boolean = false,
)

/** Everything the panels derive from, recomputed only when the DATABASE
 * changes -- the period chips and the projection sliders combine over this
 * rather than re-running the queries behind it. */
private data class PortfolioSnapshot(
    val holdingsCount: Int = 0,
    val events: List<DivEvent> = emptyList(),
    val totalValueMinor: Long = 0L,
)

/**
 * Why the add/edit failures are an enum and not a String.
 *
 * A view model has no `Resources` and should not hold one (see I18n.kt), so
 * the FAILURE crosses the boundary and the composable resolves it against the
 * caller's resources. The previous version returned ready-made English
 * sentences, which is why this screen's error line was the only text on it
 * that never translated.
 */
enum class InvestmentFormError {
    QUANTITY, NAME, INSTRUMENT, FUNDING_ACCOUNT, OVER_FUNDS,
    SIP_AMOUNT, SIP_SOURCE, NO_USER, ADD_FAILED, SAVE_FAILED, HOLDING_NOT_FOUND, INVALID_QUANTITY,
}

/** [accountName] is only set for [InvestmentFormError.OVER_FUNDS], whose
 * message names the account that is short. */
data class InvestmentFormFailure(val error: InvestmentFormError, val accountName: String? = null)

/**
 * Ported from apps/web/app/investments/page.tsx per
 * docs/mobile/screen-specs/investments.md. Replaces the pre-existing
 * dead-code InvestmentsViewModel described in ui/UiModels.kt's header comment
 * with a real port.
 *
 * This pass added the five things page.tsx has and the port did not: the
 * SIP collection and its recurring-transfer write (mobile could not create a
 * SIP at all before it), the instrument-catalog picker (every mobile holding
 * was `off_list`), the allocation donut and gain/loss bars, the
 * dividends-this-financial-year card, and the dividend + projection panels.
 *
 * Still deferred, and deliberately: live market quotes (so `valuation()` is
 * called with no quote and listed holdings value at `current_value ?? cost`,
 * exactly as an off-list holding does on web), the 63k-row daily instrument
 * download behind the seed catalog, and CSV/XLSX broker import.
 */
class InvestmentsViewModel : ViewModel(), KoinComponent {
    private val investmentsRepository: InvestmentsRepository by inject()
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _groups = MutableStateFlow<List<GroupUiModel>>(emptyList())
    val groups: StateFlow<List<GroupUiModel>> = _groups

    private val _totalValueFormatted = MutableStateFlow(formatMoney(0, baseCurrencyNow()))
    val totalValueFormatted: StateFlow<String> = _totalValueFormatted

    /** Web's grand-total row shows Current value / Invested / Gain-loss side
     * by side; the cost figure is what makes the gain readable at all. */
    private val _totalCostFormatted = MutableStateFlow(formatMoney(0, baseCurrencyNow()))
    val totalCostFormatted: StateFlow<String> = _totalCostFormatted

    private val _totalGainFormatted = MutableStateFlow("")
    val totalGainFormatted: StateFlow<String> = _totalGainFormatted

    private val _totalGainPositive = MutableStateFlow(true)
    val totalGainPositive: StateFlow<Boolean> = _totalGainPositive

    private val _invAccounts = MutableStateFlow<List<InvAccountOption>>(emptyList())
    val invAccounts: StateFlow<List<InvAccountOption>> = _invAccounts

    private val _fundingAccounts = MutableStateFlow<List<FundingAccountOption>>(emptyList())
    val fundingAccounts: StateFlow<List<FundingAccountOption>> = _fundingAccounts

    private val _allocation = MutableStateFlow<List<AllocationSliceUi>>(emptyList())
    val allocation: StateFlow<List<AllocationSliceUi>> = _allocation

    private val _gainByGroup = MutableStateFlow<List<GainBarUi>>(emptyList())
    val gainByGroup: StateFlow<List<GainBarUi>> = _gainByGroup

    private val _dividendFyFormatted = MutableStateFlow(formatMoney(0, baseCurrencyNow()))
    val dividendFyFormatted: StateFlow<String> = _dividendFyFormatted

    // Named `currentFy`, not `financialYear`: a property with the same name as
    // the imported Domain function would make every `financialYear(today)` call
    // in this class a resolution puzzle for the next reader, and Kotlin gives
    // no warning either way.
    private val _currentFy = MutableStateFlow(financialYear(todayIso()))
    val currentFy: StateFlow<FinancialYear> = _currentFy

    private val snapshot = MutableStateFlow(PortfolioSnapshot())

    // --- panel controls (UI state, not database state) ----------------------

    val dividendPeriod = MutableStateFlow(DividendPeriod.MONTH)

    /** Web's defaults: 7% a year, nothing extra put in, fifteen years,
     * dividends reinvested. */
    val projectionGrowthPct = MutableStateFlow(7.0)
    val projectionMonthlyMajor = MutableStateFlow(0.0)
    val projectionYears = MutableStateFlow(15)
    val projectionReinvest = MutableStateFlow(true)

    val dividendPanel: StateFlow<DividendPanelUi> =
        combine(snapshot, dividendPeriod) { snap, period ->
            val base = baseCurrencyNow()
            val scale = majorScale(base)
            val summary = dividendSummary(snap.events)
            DividendPanelUi(
                hasHoldings = snap.holdingsCount > 0,
                hasEvents = snap.events.isNotEmpty(),
                // The bucket value is ALREADY Long minor units, so this is the
                // one conversion to a plottable Double and it goes through
                // majorScale -- a literal 100 here would flatten every JPY
                // portfolio to a hundredth of its height.
                buckets = bucketize(snap.events, period).map { DividendBucketUi(it.label, it.value / scale, it.upcoming) },
                trailing12Formatted = formatMoney(summary.trailing12, base),
                upcoming12Formatted = formatMoney(summary.upcoming12, base),
                totalFormatted = formatMoney(summary.total, base),
            )
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), DividendPanelUi())

    val projectionPanel: StateFlow<ProjectionPanelUi> =
        combine(snapshot, projectionGrowthPct, projectionMonthlyMajor, projectionYears, projectionReinvest) {
                snap, growthPct, monthlyMajor, years, reinvest ->
            val base = baseCurrencyNow()
            val scale = majorScale(base)
            val summary = dividendSummary(snap.events)
            // Web's own fallback: use the last twelve months of income when
            // there is any, else next twelve months' scheduled income.
            val annual = if (summary.trailing12 > 0L) summary.trailing12 else summary.upcoming12
            val yieldRate = dividendYieldRate(annual, snap.totalValueMinor)
            val projection = projectPortfolio(
                currentValueBase = snap.totalValueMinor,
                growthPctPerYear = growthPct,
                monthlyContributionBase = fromMajor(monthlyMajor, base).amount,
                years = years,
                reinvestDividends = reinvest,
                dividendYieldRate = yieldRate,
            )
            ProjectionPanelUi(
                hasHoldings = snap.holdingsCount > 0,
                series = projection.points.map { it.yearsOut.toString() to (it.valueBase / scale) },
                endValueFormatted = formatMoney(projection.endValueBase, base),
                contributedFormatted = formatMoney(projection.contributedBase, base),
                growthFormatted = formatMoney(projection.growthBase, base),
                yieldPctFormatted = "%.1f".format(yieldRate * 100.0),
                hasYield = yieldRate > 0.0,
            )
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ProjectionPanelUi())

    // --- instrument catalog -------------------------------------------------

    /** The exchange the picker is scoped to, or null for all of them. */
    val instrumentExchange = MutableStateFlow<String?>(null)
    val instrumentQuery = MutableStateFlow("")

    /** Every exchange the bundled catalog knows about. Static today -- it
     * becomes reactive for free the day a downloaded catalog replaces the
     * seed, because `knownExchanges` reads whatever list it is handed. */
    val catalogExchanges: List<String> = knownExchanges(SEED_INSTRUMENTS)

    val instrumentResults: StateFlow<List<Instrument>> =
        combine(instrumentQuery, instrumentExchange) { query, exchange ->
            searchInstruments(SEED_INSTRUMENTS, query, exchange)
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private var latestHoldings: List<Holding> = emptyList()

    init {
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value ?: return@launch
            combine(
                investmentsRepository.watchHoldings(userId),
                ledgerRepository.watchAccountBalances(),
                ledgerRepository.watchRates(),
                investmentsRepository.watchDividends(),
            ) { holdings, balances, rates, dividends ->
                latestHoldings = holdings
                val base = baseCurrencyNow()

                _invAccounts.value = balances
                    .filter { FormOptions.isInvestmentAccount(it.account.type) }
                    .map { InvAccountOption(it.account.id, it.account.name, it.account.currency) }

                _fundingAccounts.value = balances
                    .filter { !FormOptions.isInvestmentAccount(it.account.type) }
                    .map {
                        FundingAccountOption(
                            id = it.account.id,
                            name = it.account.name,
                            currency = it.account.currency,
                            balanceFormatted = formatMoney(it.balance.amount, it.account.currency),
                            balanceMinor = it.balance.amount,
                        )
                    }

                val rows = holdings.map { it.toHoldingRow() }
                val groupsResult = buildGroups(rows) { amount, currency ->
                    if (currency == base) amount
                    else convert(money(amount, currency), base, rates(currency, base)).amount
                }
                val byGroupKey = holdings.groupBy { groupKeyOf(it.toHoldingRow()) }

                _groups.value = groupsResult.map { g -> g.toUiModel(byGroupKey[g.key] ?: emptyList(), base) }

                val totals = portfolioTotals(groupsResult)
                publishTotals(totals, base)
                publishCharts(groupsResult, base)

                // Dividends: only listed, catalog-matched holdings can be
                // matched to a `market_dividends` row at all -- an off-list
                // holding has no symbol the market data knows, so counting it
                // would silently attribute someone else's dividend to it.
                val lite = holdings
                    .filter { isListed(assetClassOf(it.toHoldingRow())) && !it.offList }
                    .map { HoldingLite(it.symbol, it.exchange, it.quantity, it.currency) }
                val events = computeDividendEvents(lite, dividends.map { it.toDivRow() }, rates, base)
                val today = todayIso()
                _currentFy.value = financialYear(today)
                _dividendFyFormatted.value = formatMoney(dividendsThisFy(events, today), base)

                snapshot.value = PortfolioSnapshot(
                    holdingsCount = holdings.size,
                    events = events,
                    totalValueMinor = totals.value,
                )
            }.collect {}
        }
    }

    private fun publishTotals(totals: PortfolioTotals, base: String) {
        _totalValueFormatted.value = formatMoney(totals.value, base)
        _totalCostFormatted.value = formatMoney(totals.cost, base)
        _totalGainPositive.value = totals.gain >= 0
        _totalGainFormatted.value = signedGain(totals.gain, totals.gainPct, base)
    }

    private fun publishCharts(groupsResult: List<Group>, base: String) {
        val scale = majorScale(base)
        _allocation.value = allocationSlices(groupsResult).map {
            AllocationSliceUi(
                groupKey = it.key,
                valueMajor = it.valueBase / scale,
                sharePct = it.sharePct,
                valueFormatted = formatMoney(it.valueBase, base),
            )
        }
        _gainByGroup.value = gainBars(groupsResult).map {
            GainBarUi(
                groupKey = it.key,
                gainMajor = it.gainBase / scale,
                gainFormatted = formatMoney(it.gainBase, base),
                positive = it.gainBase >= 0L,
            )
        }
    }

    /** "+₹1,200 (+4.5%)" / "-₹300 (-2.0%)" -- web's own grand-total shape. */
    private fun signedGain(gain: Long, gainPct: Double, currency: String): String =
        "${if (gain >= 0) "+" else ""}${formatMoney(gain, currency)} (${"%+.1f".format(gainPct)}%)"

    private fun Group.toUiModel(rows: List<Holding>, base: String) = GroupUiModel(
        key = key,
        holdingsCount = holdings.size,
        valueFormatted = formatMoney(value, base),
        costFormatted = formatMoney(cost, base),
        gainFormatted = signedGain(gain, gainPct, base),
        gainPositive = gain >= 0,
        gainPctFormatted = "%+.1f%%".format(gainPct),
        holdings = rows.map { it.toUiModel() },
    )

    private fun Holding.toHoldingRow(): HoldingRow = HoldingRow(
        id = id, accountId = accountId, symbol = symbol, exchange = exchange, quantity = quantity,
        avgCost = avgCost, currency = currency, offList = offList, name = name, assetClass = assetClass,
        currentValue = currentValue,
    )

    private fun DividendRow.toDivRow(): DivRow = DivRow(symbol, exchange, exDate, payDate, amount, currency)

    private fun Holding.toUiModel(): HoldingUiModel {
        val row = toHoldingRow()
        // Web's `sipOn`: a SIP is running only while it still has an amount AND
        // its recurring item is alive.
        val sipLive = plannedId != null && (sipAmount ?: 0L) > 0L
        val v = valuation(row)
        val cls = assetClassOf(row)
        return HoldingUiModel(
            id = id,
            label = holdingLabel(row),
            assetClassKey = cls.key,
            exchange = exchange?.takeIf { it.isNotBlank() },
            quantityPlain = plainNumber(quantity),
            unitWordKey = cls.unitWord.takeIf { it.isNotBlank() },
            valueFormatted = formatMoney(v.value, currency),
            costFormatted = formatMoney(v.cost, currency),
            // Web's HoldingTile prints the percentage next to the amount, to
            // two places rather than the group tile's one -- a single holding
            // moving 0.4% is a different fact from a whole group doing it.
            gainFormatted = "${if (v.gain >= 0) "+" else ""}${formatMoney(v.gain, currency)} (${"%+.2f".format(v.gainPct)}%)",
            gainPositive = v.gain >= 0,
            // Web hides the gain line entirely when there is neither a cost
            // basis nor a current value: "+₹0" on a holding nobody has priced
            // reads as "flat", which is a claim the data does not support.
            hasCostBasis = avgCost != null || currentValue != null,
            offList = offList,
            isListedClass = isListed(cls),
            annualRatePlain = if (cls == AssetClass.FD) annualRate?.let { "%.1f".format(it) } else null,
            maturityDate = if (cls == AssetClass.FD) maturityDate?.take(10) else null,
            rawQuantity = quantity,
            rawAvgCostMajor = avgCost?.let { formatMajorPlain(it, currency) } ?: "",
            rawCurrentValueMajor = currentValue?.let { formatMajorPlain(it, currency) } ?: "",
            rawAnnualRate = annualRate?.let { plainNumber(it) } ?: "",
            currency = currency,
            sipOn = sipLive,
            sipAmountFormatted = if (sipLive) formatMoney(sipAmount ?: 0L, currency) else null,
            plannedId = plannedId,
        )
    }

    /** "10", not "10.0"; "10.5" stays "10.5". Quantities are fractional for
     * mutual-fund units and whole for shares, and a share count printed with a
     * decimal point reads like a rounding error. */
    private fun plainNumber(v: Double): String =
        if (v == Math.floor(v) && !v.isInfinite()) v.toLong().toString() else v.toString()

    /** Today, as the `yyyy-MM-dd` the financial-year helpers compare against. */
    /**
     * Today as a LOCAL calendar day.
     *
     * Local, not UTC, and deliberately: every value it is compared against is a
     * `yyyy-MM-dd` CALENDAR DAY, not an instant -- an ex-dividend date, a SIP
     * start date, a financial-year boundary. The question those answer is
     * "which day is it where the person is", and a UTC day answers a different
     * one, moving the financial year a day early for every user east of
     * Greenwich. iOS's `IsoDay.today()` is local for the same reason, so the
     * two platforms agree.
     *
     * Not to be copied into anything comparing TIMESTAMPS: `TileViewModels`
     * uses `LocalDate.now(ZoneOffset.UTC)` where the other side of the
     * comparison is a stored UTC instant, and that is right there.
     */
    private fun todayIso(): String = LocalDate.now().toString()

    /**
     * Add a holding -- web's AddInvestmentDialog.submit(), including its SIP
     * branch. Returns null on success, or the failure for the screen to
     * localise.
     */
    suspend fun addHolding(
        investmentAccountId: String,
        assetClass: AssetClass,
        instrument: Instrument?,
        name: String,
        exchange: String?,
        quantityText: String,
        avgCostMajorText: String,
        currentValueMajorText: String,
        annualRateText: String,
        maturityDate: String?,
        currency: String,
        fundingExisting: Boolean,
        fundingSourceAccountId: String?,
        sipAmountMajorText: String = "",
        sipFrequency: String = "monthly",
        sipStartDate: String = "",
        sipDayText: String = "",
        sipSourceAccountId: String? = null,
    ): InvestmentFormFailure? {
        val isSip = assetClass == AssetClass.SIP
        val isLump = assetClass == AssetClass.FD
        // Web's SIP branch collects an amount, not units: quantity and cost
        // are not asked for and the holding starts at zero units, because the
        // units only exist once instalments have actually posted.
        val qty = when {
            isSip -> 0.0
            isLump -> 1.0
            else -> quantityText.toDoubleOrNull() ?: 0.0
        }
        if (!isSip && !isLump && qty <= 0) return InvestmentFormFailure(InvestmentFormError.QUANTITY)

        // A catalog pick supplies symbol, exchange and trading currency; free
        // text supplies only a name and is written off_list.
        val fromCatalog = instrument != null
        if (isListed(assetClass) && !fromCatalog && name.isBlank()) return InvestmentFormFailure(InvestmentFormError.NAME)
        if (!isListed(assetClass) && name.isBlank()) return InvestmentFormFailure(InvestmentFormError.NAME)

        val avgCostMinor = if (isSip) null else avgCostMajorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount }
        val currentValueMinor =
            if (!isSip && !isListed(assetClass)) currentValueMajorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount } else null
        val annualRate = if (assetClass == AssetClass.FD) annualRateText.toDoubleOrNull() else null

        var sip: SipSetup? = null
        if (isSip) {
            val amount = sipAmountMajorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount } ?: 0L
            if (amount <= 0L) return InvestmentFormFailure(InvestmentFormError.SIP_AMOUNT)
            if (sipSourceAccountId.isNullOrBlank()) return InvestmentFormFailure(InvestmentFormError.SIP_SOURCE)
            val start = sipStartDate.ifBlank { todayIso() }
            sip = SipSetup(
                amount = amount,
                frequency = sipFrequency,
                // Web sends the start date as the first due date too: the
                // engine posts from there forward, so a SIP started last month
                // catches up rather than silently skipping its first month.
                firstDue = start,
                sourceAccountId = sipSourceAccountId,
                startDate = start,
                day = clampSipDay(sipDayText.toIntOrNull() ?: 0),
            )
        } else {
            if (!fundingExisting && fundingSourceAccountId.isNullOrBlank()) {
                return InvestmentFormFailure(InvestmentFormError.FUNDING_ACCOUNT)
            }
            if (!fundingExisting) {
                val costTotal = Math.round((avgCostMinor ?: 0L) * qty)
                val source = _fundingAccounts.value.find { it.id == fundingSourceAccountId }
                if (source != null && costTotal > source.balanceMinor) {
                    return InvestmentFormFailure(InvestmentFormError.OVER_FUNDS, source.name)
                }
            }
        }

        val userId = authRepository.currentUserId.value
            ?: return InvestmentFormFailure(InvestmentFormError.NO_USER)
        return try {
            investmentsRepository.addHolding(
                userId,
                AddHoldingInput(
                    investmentAccountId = investmentAccountId,
                    assetClass = assetClass.key,
                    symbol = instrument?.symbol ?: "",
                    exchange = instrument?.exchange ?: if (assetClass == AssetClass.STOCK) exchange else null,
                    name = instrument?.symbol ?: name.trim(),
                    quantity = qty,
                    avgCost = avgCostMinor,
                    currency = currency,
                    currentValue = currentValueMinor,
                    annualRate = annualRate,
                    maturityDate = if (assetClass == AssetClass.FD) maturityDate?.ifBlank { null } else null,
                    // The whole point of the picker: a catalog-matched holding
                    // is ON the list, so it can be priced and matched to a
                    // dividend row. Before it existed every mobile holding was
                    // written off_list = 1.
                    offList = !fromCatalog,
                    autoFetch = fromCatalog,
                    // A SIP tracks the units already bought as already-owned;
                    // its money movement IS the recurring transfer, so it never
                    // takes the existing-vs-new funding branch.
                    funding = if (!isSip && !fundingExisting) HoldingFunding.New(fundingSourceAccountId!!) else HoldingFunding.Existing,
                    sip = sip,
                ),
            )
            null
        } catch (e: Exception) {
            e.printStackTrace()
            InvestmentFormFailure(InvestmentFormError.ADD_FAILED)
        }
    }

    /** Matches web's EditHolding.save(): quantity/avg-cost/current-value/
     * annual-rate only. */
    suspend fun updateHolding(
        id: String,
        quantityText: String,
        avgCostMajorText: String,
        currentValueMajorText: String,
        annualRateText: String,
        currency: String,
    ): InvestmentFormFailure? {
        val holding = latestHoldings.find { it.id == id }
            ?: return InvestmentFormFailure(InvestmentFormError.HOLDING_NOT_FOUND)
        val cls = AssetClass.fromKey(holding.assetClass ?: holding.instrumentType)
        val isLump = cls == AssetClass.FD
        val qty = if (isLump) 1.0 else (quantityText.toDoubleOrNull()
            ?: return InvestmentFormFailure(InvestmentFormError.INVALID_QUANTITY))
        val avgCostMinor = avgCostMajorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount }
        val currentValueMinor = currentValueMajorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount }
        val annualRate = annualRateText.toDoubleOrNull()
        return try {
            investmentsRepository.updateHolding(id, qty, avgCostMinor, currentValueMinor, annualRate)
            null
        } catch (e: Exception) {
            e.printStackTrace()
            InvestmentFormFailure(InvestmentFormError.SAVE_FAILED)
        }
    }

    /** Web's remove(): kills the SIP with the holding, or it keeps debiting
     * forever for an investment that no longer exists. */
    fun deleteHolding(id: String) {
        viewModelScope.launch {
            try {
                investmentsRepository.deleteHolding(id, latestHoldings.find { it.id == id }?.plannedId)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    /** Web's Stop SIP chip: cancel the recurring item, then clear the
     * holding's own SIP fields so nothing still reads as running. The holding
     * itself stays -- the units already bought are still owned. */
    fun stopSip(id: String) {
        viewModelScope.launch {
            try {
                investmentsRepository.stopSipForHolding(latestHoldings.find { it.id == id }?.plannedId)
                investmentsRepository.clearSipFields(id)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
