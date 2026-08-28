package com.sanvya.app.ui.investments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.AddHoldingInput
import com.sanvya.app.data.repository.Holding
import com.sanvya.app.data.repository.HoldingFunding
import com.sanvya.app.data.repository.InvestmentsRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.domain.investments.AssetClass
import com.sanvya.app.domain.investments.HoldingRow
import com.sanvya.app.domain.investments.assetClassOf
import com.sanvya.app.domain.investments.buildGroups
import com.sanvya.app.domain.investments.groupKeyOf
import com.sanvya.app.domain.investments.holdingLabel
import com.sanvya.app.domain.investments.isListed
import com.sanvya.app.domain.investments.portfolioTotals
import com.sanvya.app.domain.investments.valuation
import com.sanvya.app.domain.money.convert
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.money.toMajor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.formatMajorPlain


private val DEMAT_TYPES = setOf("demat", "stocks", "mutual_funds")

data class InvAccountOption(val id: String, val name: String, val currency: String)
data class FundingAccountOption(val id: String, val name: String, val currency: String, val balanceFormatted: String, val balanceMinor: Long)

data class HoldingUiModel(
    val id: String,
    val label: String,
    val metaLine: String, // "▤ Stock · NSE" / "▦ Fixed deposit"
    val quantityLine: String, // "10 shares" / "" for FD
    val valueFormatted: String,
    val costFormatted: String,
    val gainFormatted: String,
    val gainPositive: Boolean,
    val offList: Boolean,
    val isListedClass: Boolean,
    val fdExtra: String?, // "8.5% p.a. · Matures 2027-04-01"
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
    val label: String,
    val holdingsCount: Int,
    val valueFormatted: String,
    val costFormatted: String,
    val gainFormatted: String,
    val gainPositive: Boolean,
    val gainPctFormatted: String,
    val holdings: List<HoldingUiModel>,
)

/**
 * Ported from apps/web/app/investments/page.tsx per
 * docs/mobile/screen-specs/investments.md (task #26). Replaces the
 * pre-existing dead-code InvestmentsViewModel described in ui/UiModels.kt's
 * header comment (constructor-injected, no consuming Screen.kt, no nav
 * route, reverse-engineered placeholder shape) with a real port.
 *
 * Deferred (see spec's Deferred section): live market quotes/LTP, the
 * instrument catalog picker, SIP recurring-transfer setup, the
 * dividend/projection panels, and the allocation-donut/gain-bar charts.
 * Everything else -- grouped list, drill-in, add/edit/delete with real
 * funding-transaction writes -- is real, matching web's actual
 * money-movement behavior (write.ts's addHolding()), not a mock.
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

    private var latestHoldings: List<Holding> = emptyList()

    init {
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value ?: return@launch
            combine(
                investmentsRepository.watchHoldings(userId),
                ledgerRepository.watchAccountBalances(),
                ledgerRepository.watchRates(),
            ) { holdings, balances, rates ->
                latestHoldings = holdings

                _invAccounts.value = balances
                    .filter { it.account.type in DEMAT_TYPES }
                    .map { InvAccountOption(it.account.id, it.account.name, it.account.currency) }

                _fundingAccounts.value = balances
                    .filter { it.account.type !in DEMAT_TYPES }
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
                    if (currency == baseCurrencyNow()) amount
                    else convert(money(amount, currency), baseCurrencyNow(), rates(currency, baseCurrencyNow())).amount
                }
                val byGroupKey = holdings.groupBy { groupKeyOf(it.toHoldingRow()) }

                _groups.value = groupsResult.map { g ->
                    GroupUiModel(
                        key = g.key,
                        label = g.label,
                        holdingsCount = g.holdings.size,
                        valueFormatted = formatMoney(g.value, baseCurrencyNow()),
                        costFormatted = formatMoney(g.cost, baseCurrencyNow()),
                        gainFormatted = "${if (g.gain >= 0) "+" else ""}${formatMoney(g.gain, baseCurrencyNow())} (${"%+.1f".format(g.gainPct)}%)",
                        gainPositive = g.gain >= 0,
                        gainPctFormatted = "%+.1f%%".format(g.gainPct),
                        holdings = (byGroupKey[g.key] ?: emptyList()).map { it.toUiModel() },
                    )
                }

                val totals = portfolioTotals(groupsResult)
                _totalValueFormatted.value = formatMoney(totals.value, baseCurrencyNow())
                _totalCostFormatted.value = formatMoney(totals.cost, baseCurrencyNow())
                _totalGainPositive.value = totals.gain >= 0
                _totalGainFormatted.value = "${if (totals.gain >= 0) "+" else ""}${formatMoney(totals.gain, baseCurrencyNow())} (${"%+.1f".format(totals.gainPct)}%)"
            }.collect {}
        }
    }

    private fun Holding.toHoldingRow(): HoldingRow = HoldingRow(
        id = id, accountId = accountId, symbol = symbol, exchange = exchange, quantity = quantity,
        avgCost = avgCost, currency = currency, offList = offList, name = name, assetClass = assetClass,
        currentValue = currentValue,
    )

    private fun Holding.toUiModel(): HoldingUiModel {
        val row = toHoldingRow()
        // Web's `sipOn`: a SIP is running only while it still has an amount AND
        // its recurring item is alive.
        val sipLive = plannedId != null && (sipAmount ?: 0L) > 0L
        val v = valuation(row)
        val cls = assetClassOf(row)
        val metaLine = buildString {
            append(cls.icon).append(' ').append(cls.label)
            if (cls == AssetClass.STOCK && !exchange.isNullOrBlank()) append(" · ").append(exchange)
        }
        val qtyLine = if (cls == AssetClass.FD || cls == AssetClass.OTHER) "" else {
            val qtyText = if (quantity == Math.floor(quantity)) quantity.toLong().toString() else quantity.toString()
            "$qtyText ${cls.unitWord}".trim()
        }
        val fdExtra = if (cls == AssetClass.FD) {
            val parts = mutableListOf<String>()
            annualRate?.let { parts.add("%.1f%% p.a.".format(it)) }
            maturityDate?.let { parts.add("Matures ${it.take(10)}") }
            parts.joinToString(" · ").ifBlank { null }
        } else null
        return HoldingUiModel(
            id = id,
            label = holdingLabel(row),
            metaLine = metaLine,
            quantityLine = qtyLine,
            valueFormatted = formatMoney(v.value, currency),
            costFormatted = formatMoney(v.cost, currency),
            gainFormatted = "${if (v.gain >= 0) "+" else ""}${formatMoney(v.gain, currency)}",
            gainPositive = v.gain >= 0,
            offList = offList,
            isListedClass = isListed(cls),
            fdExtra = fdExtra,
            rawQuantity = quantity,
            rawAvgCostMajor = avgCost?.let { formatMajorPlain(it, currency) } ?: "",
            rawCurrentValueMajor = currentValue?.let { formatMajorPlain(it, currency) } ?: "",
            rawAnnualRate = annualRate?.let { if (it == Math.floor(it)) it.toLong().toString() else it.toString() } ?: "",
            currency = currency,
            sipOn = sipLive,
            sipAmountFormatted = if (sipLive) formatMoney(sipAmount!!, currency) else null,
            plannedId = plannedId,
        )
    }


    /** Matches AddInvestmentDialog's scoped-down submit(): validates, funds
     * the pool (transfer/adjustment), then inserts the holding row. */
    suspend fun addHolding(
        investmentAccountId: String,
        assetClass: AssetClass,
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
    ): String? {
        val isLump = assetClass == AssetClass.FD
        val qty = if (isLump) 1.0 else (quantityText.toDoubleOrNull() ?: 0.0)
        if (!isLump && qty <= 0) return "Enter a quantity greater than 0."
        if (name.isBlank()) return "Enter a name."
        val avgCostMinor = avgCostMajorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount }
        val currentValueMinor = if (!isListed(assetClass)) currentValueMajorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount } else null
        val annualRate = if (assetClass == AssetClass.FD) annualRateText.toDoubleOrNull() else null

        if (!fundingExisting && fundingSourceAccountId.isNullOrBlank()) return "Choose an account to fund this from."
        if (!fundingExisting) {
            val costTotal = Math.round((avgCostMinor ?: 0L) * qty)
            val source = _fundingAccounts.value.find { it.id == fundingSourceAccountId }
            if (source != null && costTotal > source.balanceMinor) return "${source.name} doesn't have enough available (${source.balanceFormatted})."
        }

        val userId = authRepository.currentUserId.value ?: return "Couldn't determine the current user."
        return try {
            investmentsRepository.addHolding(
                userId,
                AddHoldingInput(
                    investmentAccountId = investmentAccountId,
                    assetClass = assetClass.key,
                    symbol = if (isListed(assetClass)) name.trim() else "",
                    exchange = if (assetClass == AssetClass.STOCK) exchange else null,
                    name = name.trim(),
                    quantity = qty,
                    avgCost = avgCostMinor,
                    currency = currency,
                    currentValue = currentValueMinor,
                    annualRate = annualRate,
                    maturityDate = if (assetClass == AssetClass.FD) maturityDate?.ifBlank { null } else null,
                    offList = true, // no catalog picker in this pass -- every holding is manually tracked (deferred: instrument catalog)
                    autoFetch = false,
                    funding = if (fundingExisting) HoldingFunding.Existing else HoldingFunding.New(fundingSourceAccountId!!),
                ),
            )
            null
        } catch (e: Exception) {
            "Couldn't add the investment: ${e.message}"
        }
    }

    /** Matches web's EditHolding.save(): quantity/avg-cost/current-value/
     * annual-rate only. */
    suspend fun updateHolding(id: String, quantityText: String, avgCostMajorText: String, currentValueMajorText: String, annualRateText: String, currency: String): String? {
        val holding = latestHoldings.find { it.id == id } ?: return "Holding not found."
        val cls = AssetClass.fromKey(holding.assetClass ?: holding.instrumentType)
        val isLump = cls == AssetClass.FD
        val qty = if (isLump) 1.0 else (quantityText.toDoubleOrNull() ?: return "Enter a valid quantity.")
        val avgCostMinor = avgCostMajorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount }
        val currentValueMinor = currentValueMajorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount }
        val annualRate = annualRateText.toDoubleOrNull()
        return try {
            investmentsRepository.updateHolding(id, qty, avgCostMinor, currentValueMinor, annualRate)
            null
        } catch (e: Exception) {
            "Couldn't save changes: ${e.message}"
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
