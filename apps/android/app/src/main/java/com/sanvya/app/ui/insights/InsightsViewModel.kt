package com.sanvya.app.ui.insights

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.ui.InsightUiModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

class InsightsViewModel(
    private val ledgerRepository: LedgerRepository
) : ViewModel() {

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 0
    }

    private val _insights = MutableStateFlow<List<InsightUiModel>>(emptyList())
    val insights: StateFlow<List<InsightUiModel>> = _insights

    private val _thisMonthSpending = MutableStateFlow("₹0")
    val thisMonthSpending: StateFlow<String> = _thisMonthSpending
    
    private val _lastMonthSpending = MutableStateFlow("₹0")
    val lastMonthSpending: StateFlow<String> = _lastMonthSpending

    init {
        viewModelScope.launch {
            try {
                ledgerRepository.watchAllTransactions().collectLatest { transactions ->
                    val now = LocalDate.now()
                    val thisMonth = now.withDayOfMonth(1)
                    val lastMonth = thisMonth.minusMonths(1)
                    
                    var thisMonthTotal = 0L
                    var lastMonthTotal = 0L
                    var diningTotal = 0L
                    var hasSubscription = false
                    
                    for (tx in transactions) {
                        if (tx.type != "expense") continue
                        
                        try {
                            val txDate = LocalDate.parse(tx.occurredAt.substringBefore("T"))
                            if (txDate >= thisMonth) {
                                thisMonthTotal += tx.amount
                                if (tx.description?.lowercase()?.contains("dining") == true || tx.note?.lowercase()?.contains("food") == true) {
                                    diningTotal += tx.amount
                                }
                                if (tx.description?.lowercase()?.contains("streamtv") == true) {
                                    hasSubscription = true
                                }
                            } else if (txDate >= lastMonth && txDate < thisMonth) {
                                lastMonthTotal += tx.amount
                            }
                        } catch (e: Exception) {
                            // ignore parse errors
                        }
                    }
                    
                    _thisMonthSpending.value = numberFormat.format(thisMonthTotal / 100.0)
                    _lastMonthSpending.value = numberFormat.format(lastMonthTotal / 100.0)
                    
                    val generatedInsights = mutableListOf<InsightUiModel>()
                    
                    if (thisMonthTotal > lastMonthTotal && lastMonthTotal > 0) {
                        val pct = ((thisMonthTotal - lastMonthTotal) * 100) / lastMonthTotal
                        generatedInsights.add(
                            InsightUiModel(
                                id = "1",
                                title = "Spending up this month",
                                description = "You've spent $pct% more than last month so far.",
                                highlightAmount = _thisMonthSpending.value,
                                isPositive = false
                            )
                        )
                    } else if (lastMonthTotal > 0) {
                        val pct = ((lastMonthTotal - thisMonthTotal) * 100) / lastMonthTotal
                        generatedInsights.add(
                            InsightUiModel(
                                id = "1",
                                title = "Spending down this month",
                                description = "You've spent $pct% less than last month so far. Great job!",
                                highlightAmount = _thisMonthSpending.value,
                                isPositive = true
                            )
                        )
                    } else {
                        generatedInsights.add(
                            InsightUiModel("1", "Welcome to Insights", "Track your spending habits here as you use the app.", null, true)
                        )
                    }
                    
                    if (diningTotal > 0) {
                        generatedInsights.add(
                            InsightUiModel("2", "Food & Dining", "Your total dining expenses this month.", numberFormat.format(diningTotal / 100.0), true)
                        )
                    }
                    
                    if (hasSubscription) {
                        generatedInsights.add(
                            InsightUiModel("3", "Unusual Subscription", "We noticed a recurring charge from 'StreamTV'.", "₹499", false)
                        )
                    }
                    
                    _insights.value = generatedInsights
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
