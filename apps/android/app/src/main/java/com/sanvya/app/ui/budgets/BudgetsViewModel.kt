package com.sanvya.app.ui.budgets

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.BudgetRepository
import com.sanvya.app.ui.BudgetUiModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale
import java.time.LocalDate
import java.time.ZoneOffset

class BudgetsViewModel(
    private val budgetRepository: BudgetRepository
) : ViewModel() {

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 0
    }

    private val _budgets = MutableStateFlow<List<BudgetUiModel>>(emptyList())
    val budgets: StateFlow<List<BudgetUiModel>> = _budgets

    init {
        viewModelScope.launch {
            loadBudgets()
        }
    }

    private suspend fun loadBudgets() {
        try {
            val list = budgetRepository.list()
            val uis = list.map { budgetLike ->
                val spent = budgetRepository.spentThisPeriod(budgetLike, LocalDate.now(ZoneOffset.UTC))
                
                val spentAmt = spent.amount / 100.0
                val limitAmt = budgetLike.limitAmount / 100.0
                val progress = if (limitAmt > 0) (spentAmt / limitAmt).toFloat() else 0f
                
                BudgetUiModel(
                    id = budgetLike.id,
                    name = budgetLike.name ?: "Untitled Budget",
                    period = budgetLike.period,
                    spentFormatted = numberFormat.format(spentAmt),
                    limitFormatted = numberFormat.format(limitAmt),
                    progress = progress,
                    categories = listOf("All") // Categories name lookup requires another DB query not exposed easily in BudgetLike yet
                )
            }
            _budgets.value = uis
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
