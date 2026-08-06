package com.sanvya.app.ui.goals

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.GoalsRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.ui.budgets.localToUtcTime
import com.sanvya.app.ui.budgets.utcToLocalTime
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale
import kotlin.math.abs
import kotlin.math.min

data class GoalUiModel(
    val id: String,
    val name: String,
    val savedFormatted: String,
    val targetFormatted: String,
    val progress: Double, // 0..1
    val funded: Boolean,
    val isEmergencyFund: Boolean,
    val locked: Boolean,
    val remainingMinor: Long,
    // Edit-form prefill -- raw, unformatted.
    val rawName: String,
    val targetMajor: String,
    val currency: String,
    val alertTimeLocal: String,
)

data class SavingsAccountOption(val id: String, val name: String)

/**
 * Ported from apps/web/app/goals/page.tsx per
 * docs/mobile/screen-specs/goals.md. Was a broken placeholder before this
 * pass (2026-08-06, task #25): `GoalUiModel.targetDate` read a real-but-
 * unused DB column (confirmed nowhere in the real Goals UI, only in the AI
 * assistant's tool schema), no create/update/delete/allocate existed, used
 * constructor injection with no Koin module registering it (no consuming
 * Screen existed either), and observed allocations per-goal via
 * `watchGoalAllocations(goal.id).firstOrNull()` inside a `collectLatest`
 * loop -- a one-time read on every goals-list emission, not a real
 * reactive subscription to allocation changes. Rewritten to
 * KoinComponent/by-inject() (matches BudgetsViewModel.kt's established
 * convention -- constructor injection doesn't work with this app's plain
 * `viewModel()` Compose default factory) with one-shot suspend reads +
 * explicit reload(), matching BudgetsViewModel.kt's reload() pattern.
 */
class GoalsViewModel : ViewModel(), KoinComponent {
    private val goalsRepository: GoalsRepository by inject()
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _goals = MutableStateFlow<List<GoalUiModel>>(emptyList())
    val goals: StateFlow<List<GoalUiModel>> = _goals

    private val _savingsAccounts = MutableStateFlow<List<SavingsAccountOption>>(emptyList())
    val savingsAccounts: StateFlow<List<SavingsAccountOption>> = _savingsAccounts

    val hasEmergencyFund: Boolean get() = _goals.value.any { it.isEmergencyFund }

    init {
        viewModelScope.launch {
            ledgerRepository.watchAccounts(includeArchived = false).collect { rows ->
                _savingsAccounts.value = rows.filter { it.type == "savings" }.map { SavingsAccountOption(it.id, it.name) }
            }
        }
        viewModelScope.launch { reload() }
    }

    suspend fun reload() {
        val userId = authRepository.currentUserId.value ?: return
        try {
            val dbGoals = goalsRepository.list(userId)
            val allocs = goalsRepository.listAllocations(userId)
            fun saved(goalId: String): Long = allocs.filter { it.goalId == goalId }.sumOf { it.amountBlocked }

            val ef = dbGoals.firstOrNull { it.isEmergencyFund }
            val efFunded = ef?.let { saved(it.id) >= it.targetAmount } ?: true

            _goals.value = dbGoals.map { g ->
                val savedAmount = saved(g.id)
                val pct = if (g.targetAmount > 0) min(1.0, savedAmount.toDouble() / g.targetAmount.toDouble()) else 0.0
                val funded = g.targetAmount > 0 && savedAmount >= g.targetAmount
                val remaining = maxOf(0L, g.targetAmount - savedAmount)
                GoalUiModel(
                    id = g.id,
                    name = g.name,
                    savedFormatted = compactMoney(savedAmount, g.currency),
                    targetFormatted = compactMoney(g.targetAmount, g.currency),
                    progress = pct,
                    funded = funded,
                    isEmergencyFund = g.isEmergencyFund,
                    locked = !g.isEmergencyFund && !efFunded,
                    remainingMinor = remaining,
                    rawName = g.name,
                    targetMajor = formatMajorPlain(g.targetAmount),
                    currency = g.currency,
                    alertTimeLocal = utcToLocalTime(g.alertTimeUtc),
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /** Matches web's addGoal(): validation, priority = current goal count. */
    suspend fun create(name: String, targetMajorText: String, currency: String, isEmergencyFund: Boolean, alertTimeLocal: String): String? {
        val trimmedName = name.trim()
        if (trimmedName.isEmpty()) return "Enter a goal name."
        val targetMajor = targetMajorText.toDoubleOrNull()
        if (targetMajor == null || targetMajor <= 0) return "Enter a target greater than 0."
        val userId = authRepository.currentUserId.value ?: return "Couldn't determine the current user."
        return try {
            goalsRepository.create(
                userId = userId,
                name = trimmedName,
                targetAmount = Math.round(targetMajor * 100),
                currency = currency,
                isEmergencyFund = isEmergencyFund && !hasEmergencyFund,
                priority = _goals.value.size.toLong(),
                alertTimeUtc = localToUtcTime(alertTimeLocal),
            )
            reload()
            null
        } catch (e: Exception) {
            "Couldn't create the goal: ${e.message}"
        }
    }

    /** Matches web's saveEdit(): name/target/alert-time only. */
    suspend fun update(id: String, name: String, targetMajorText: String, alertTimeLocal: String): String? {
        return try {
            val targetMajor = targetMajorText.toDoubleOrNull() ?: 0.0
            goalsRepository.update(
                id = id,
                name = name.trim(),
                targetAmount = Math.round(targetMajor * 100),
                alertTimeUtc = localToUtcTime(alertTimeLocal),
            )
            reload()
            null
        } catch (e: Exception) {
            "Couldn't save changes: ${e.message}"
        }
    }

    /** Soft-deletes the goal only -- no cascade to its allocations, matching
     * web (see GoalsRepository.kt's doc comment). */
    fun delete(id: String) {
        viewModelScope.launch {
            try {
                goalsRepository.delete(id)
                reload()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    /** Matches web's allocate(): caps at the goal's remaining amount before
     * inserting. */
    suspend fun allocate(goalId: String, sourceAccountId: String, amountMajorText: String, remainingMinor: Long): String? {
        val amountMajor = amountMajorText.toDoubleOrNull()
        if (amountMajor == null || amountMajor <= 0) return "Enter an amount."
        val userId = authRepository.currentUserId.value ?: return "Couldn't determine the current user."
        val requested = Math.round(amountMajor * 100)
        val capped = min(requested, remainingMinor)
        if (capped <= 0) return null
        return try {
            goalsRepository.createAllocation(userId, goalId, sourceAccountId, capped)
            reload()
            null
        } catch (e: Exception) {
            "Couldn't allocate funds: ${e.message}"
        }
    }

    private fun formatMajorPlain(minor: Long): String {
        val major = minor / 100.0
        return if (major == Math.floor(major)) major.toLong().toString() else major.toString()
    }
}

/** Locale-aware compact currency (e.g. ₹1.5L for INR, $1.2K otherwise) --
 * approximates web's `Intl.NumberFormat(..., { notation: "compact" })`
 * rather than reimplementing its exact breakpoints, per the spec's
 * "Deferred" note (acceptable drift, not pixel-critical). */
private fun compactMoney(minor: Long, currency: String): String {
    val major = minor / 100.0
    val fmt = NumberFormat.getCurrencyInstance(Locale.US).apply {
        try { this.currency = Currency.getInstance(currency) } catch (e: IllegalArgumentException) { /* unknown code, keep default */ }
        maximumFractionDigits = if (abs(major) >= 1000) 1 else 0
    }
    return when {
        abs(major) >= 10_000_000 -> fmt.format(major / 10_000_000) + "Cr"
        abs(major) >= 100_000 -> fmt.format(major / 100_000) + "L"
        abs(major) >= 1000 -> fmt.format(major / 1000) + "K"
        else -> fmt.format(major)
    }
}
