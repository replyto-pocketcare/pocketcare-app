package com.sanvya.app.ui.goals

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.GoalsRepository
import com.sanvya.app.ui.GoalUiModel
import com.sanvya.app.data.auth.AuthRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale

class GoalsViewModel(
    private val goalsRepository: GoalsRepository,
    private val authRepository: AuthRepository
) : ViewModel() {

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 0
    }

    private val _goals = MutableStateFlow<List<GoalUiModel>>(emptyList())
    val goals: StateFlow<List<GoalUiModel>> = _goals

    init {
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value ?: return@launch
            try {
                goalsRepository.watchGoals(userId).collectLatest { dbGoals ->
                    val uiGoals = dbGoals.map { goal ->
                        // Fetch allocations for this goal to calculate current saved amount
                        val allocations = goalsRepository.watchGoalAllocations(goal.id).firstOrNull() ?: emptyList()
                        val savedAmount = allocations.sumOf { it.amountBlocked }
                        
                        val savedD = savedAmount / 100.0
                        val targetD = goal.targetAmount / 100.0
                        
                        val progress = if (targetD > 0) (savedD / targetD).toFloat() else 0f
                        
                        GoalUiModel(
                            id = goal.id,
                            name = goal.name,
                            currentFormatted = numberFormat.format(savedD),
                            targetFormatted = numberFormat.format(targetD),
                            targetDate = goal.targetDate ?: "No date",
                            progress = progress
                        )
                    }
                    _goals.value = uiGoals
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
