package com.sanvya.app.ui.investments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.InvestmentsRepository
import com.sanvya.app.ui.HoldingUiModel
import com.sanvya.app.data.auth.AuthRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale

class InvestmentsViewModel(
    private val investmentsRepository: InvestmentsRepository,
    private val authRepository: AuthRepository
) : ViewModel() {

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 0
    }

    private val percentFormat = NumberFormat.getPercentInstance(Locale("en", "IN")).apply {
        minimumFractionDigits = 1
        maximumFractionDigits = 2
    }

    private val _holdings = MutableStateFlow<List<HoldingUiModel>>(emptyList())
    val holdings: StateFlow<List<HoldingUiModel>> = _holdings

    private val _totalValueFormatted = MutableStateFlow("₹0")
    val totalValueFormatted: StateFlow<String> = _totalValueFormatted

    private val _totalReturnFormatted = MutableStateFlow("+₹0 (0%)")
    val totalReturnFormatted: StateFlow<String> = _totalReturnFormatted
    
    private val _isTotalReturnPositive = MutableStateFlow(true)
    val isTotalReturnPositive: StateFlow<Boolean> = _isTotalReturnPositive

    init {
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value ?: return@launch
            try {
                investmentsRepository.watchHoldings(userId).collectLatest { dbHoldings ->
                    var totalCost = 0.0
                    var totalValue = 0.0
                    
                    val uiHoldings = dbHoldings.map { holding ->
                        val qty = holding.quantity
                        val avgCost = holding.avgCost / 100.0
                        val curVal = (holding.currentValue ?: holding.avgCost) / 100.0
                        
                        val costBasis = qty * avgCost
                        val valueBasis = qty * curVal
                        
                        totalCost += costBasis
                        totalValue += valueBasis
                        
                        val retAmt = valueBasis - costBasis
                        val retPct = if (costBasis > 0) retAmt / costBasis else 0.0
                        val isPos = retAmt >= 0
                        
                        val sign = if (isPos) "+" else ""
                        val retStr = "$sign${percentFormat.format(retPct)}"
                        
                        HoldingUiModel(
                            id = holding.id,
                            name = holding.name ?: holding.symbol,
                            symbolExchange = "${holding.symbol} • ${holding.exchange}",
                            assetClass = holding.assetClass ?: holding.instrumentType,
                            quantity = "${holding.quantity} shares",
                            currentValueFormatted = numberFormat.format(valueBasis),
                            returnFormatted = retStr,
                            isPositiveReturn = isPos
                        )
                    }
                    
                    _holdings.value = uiHoldings
                    _totalValueFormatted.value = numberFormat.format(totalValue)
                    
                    val totRetAmt = totalValue - totalCost
                    val totRetPct = if (totalCost > 0) totRetAmt / totalCost else 0.0
                    val isPosRet = totRetAmt >= 0
                    val signRet = if (isPosRet) "+" else ""
                    _isTotalReturnPositive.value = isPosRet
                    
                    val retSign2 = if (isPosRet) "▲" else "▼"
                    val retFormattedAmt = numberFormat.format(Math.abs(totRetAmt))
                    _totalReturnFormatted.value = "$retSign2 $signRet$retFormattedAmt ($signRet${percentFormat.format(totRetPct)})"
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
