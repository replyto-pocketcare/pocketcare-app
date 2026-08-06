package com.sanvya.app.ui.budgets

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.BudgetLike
import com.sanvya.app.data.repository.BudgetRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.domain.budget.budgetProgress
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.money.toMajor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.text.NumberFormat
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

enum class ProgressColor { POSITIVE, WARNING, NEGATIVE }

data class BudgetUiModel(
    val id: String,
    val title: String,
    val timeframeText: String,
    val scopeLabel: String,
    val spentFormatted: String,
    val remainingOrOverText: String,
    val progress: Double,
    val progressColor: ProgressColor,
    // Edit-form prefill -- raw, unformatted.
    val rawName: String,
    val limitMajor: String,
    val currency: String,
    val period: String,
    val thresholdPct: Int,
    val alertTimeLocal: String,
    val isCustomDated: Boolean,
    val startDate: String?,
    val endDate: String?,
    val categoryIds: List<String>,
    val labelNames: List<String>,
)

data class CategoryOption(val id: String, val name: String)

/**
 * Ported from apps/web/app/budgets/page.tsx per
 * docs/mobile/screen-specs/budgets.md. Was list-read-only with a hardcoded
 * `categories = listOf("All")` placeholder before this pass (2026-08-06) --
 * BudgetRepository now has real create/update/delete/scope methods (see
 * BudgetRepository.kt), so this reads real category/label names via
 * LedgerRepository.watchCategories()/watchLabels() (same pattern
 * TransactionsViewModel already established). Mirrors iOS's
 * BudgetsViewModel.swift field-for-field.
 */
class BudgetsViewModel : ViewModel(), KoinComponent {
    private val budgetRepository: BudgetRepository by inject()
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 0
    }

    private val _budgets = MutableStateFlow<List<BudgetUiModel>>(emptyList())
    val budgets: StateFlow<List<BudgetUiModel>> = _budgets

    private val _expenseCategories = MutableStateFlow<List<CategoryOption>>(emptyList())
    val expenseCategories: StateFlow<List<CategoryOption>> = _expenseCategories

    private val _labelNames = MutableStateFlow<List<String>>(emptyList())
    val labelNames: StateFlow<List<String>> = _labelNames

    init {
        viewModelScope.launch {
            ledgerRepository.watchCategories().collect { rows ->
                _expenseCategories.value = rows.filter { it.kind == "expense" }.map { CategoryOption(it.id, it.name) }
            }
        }
        viewModelScope.launch {
            ledgerRepository.watchLabels().collect { rows -> _labelNames.value = rows.map { it.name } }
        }
        viewModelScope.launch { reload() }
    }

    suspend fun reload() {
        try {
            val list = budgetRepository.list()
            val today = LocalDate.now(ZoneOffset.UTC)
            val uis = list.map { b ->
                val spent = budgetRepository.spentThisPeriod(b, today)
                val limit = money(b.limitAmount, b.currency)
                val progress = budgetProgress(limit, spent, b.thresholdPct.toDouble())
                val catIds = budgetRepository.categoryIds(b.id)
                val labels = budgetRepository.labelNames(b.id)
                val catNames = catIds.mapNotNull { id -> _expenseCategories.value.find { it.id == id }?.name }
                val scopeNames = catNames + labels
                val scopeLabel = if (scopeNames.isEmpty()) "All spending" else scopeNames.joinToString(", ")
                val win = periodWindow(b.period, b.startDate, b.endDate)
                val isCustom = b.startDate != null && b.endDate != null
                val timeframeText = if (isCustom) win.label else "${periodLabel(b.period)} · ${win.label}"
                val color = when {
                    progress.overLimit -> ProgressColor.NEGATIVE
                    progress.atOrOverThreshold -> ProgressColor.WARNING
                    else -> ProgressColor.POSITIVE
                }
                val remainingOrOver = if (progress.overLimit) {
                    "Over by ${formatMoney(money(spent.amount - limit.amount, b.currency))}"
                } else {
                    "${formatMoney(progress.remaining)} left"
                }
                BudgetUiModel(
                    id = b.id,
                    title = b.name?.takeIf { it.isNotBlank() } ?: scopeLabel,
                    timeframeText = timeframeText,
                    scopeLabel = scopeLabel,
                    spentFormatted = "Spent ${formatMoney(spent)}",
                    remainingOrOverText = remainingOrOver,
                    progress = if (progress.pct.isFinite()) progress.pct / 100 else 1.0,
                    progressColor = color,
                    rawName = b.name ?: "",
                    limitMajor = formatMajorPlain(b.limitAmount),
                    currency = b.currency,
                    period = b.period,
                    thresholdPct = b.thresholdPct,
                    alertTimeLocal = utcToLocalTime(b.alertTimeUtc),
                    isCustomDated = isCustom,
                    startDate = b.startDate,
                    endDate = b.endDate,
                    categoryIds = catIds,
                    labelNames = labels,
                )
            }
            _budgets.value = uis
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /** Matches web's addBudget(): limit must be > 0, custom mode requires
     * both dates. Returns an error string on validation failure. */
    suspend fun create(
        name: String,
        limitMajorText: String,
        currency: String,
        thresholdPctText: String,
        alertTimeLocal: String,
        categoryIds: List<String>,
        labelNamesInput: List<String>,
        isCustomDated: Boolean,
        period: String,
        startDate: String?,
        endDate: String?,
    ): String? {
        val limitMajor = limitMajorText.toDoubleOrNull()
        if (limitMajor == null || limitMajor <= 0) return "Enter a limit greater than 0."
        if (isCustomDated && (startDate.isNullOrEmpty() || endDate.isNullOrEmpty())) return "Pick both a start and end date."
        val userId = authRepository.currentUserId.value ?: return "Couldn't determine the current user."
        return try {
            val thresholdPct = min(100, max(1, thresholdPctText.toIntOrNull() ?: 80))
            val id = budgetRepository.create(
                userId = userId,
                name = name.trim().ifBlank { null },
                period = period,
                startDate = if (isCustomDated) startDate else null,
                endDate = if (isCustomDated) endDate else null,
                limitAmount = fromMajor(limitMajor, currency).amount,
                currency = currency,
                thresholdPct = thresholdPct,
                alertTimeUtc = localToUtcTime(alertTimeLocal),
            )
            budgetRepository.writeScope(userId, id, categoryIds, labelNamesInput)
            reload()
            null
        } catch (e: Exception) {
            "Couldn't create the budget: ${e.message}"
        }
    }

    /** Matches web's saveEdit(): name/limit/period/threshold/alert-time only
     * -- currency and start/end dates are not editable after creation. */
    suspend fun update(
        id: String,
        name: String,
        limitMajorText: String,
        currency: String,
        period: String,
        thresholdPctText: String,
        alertTimeLocal: String,
        categoryIds: List<String>,
        labelNamesInput: List<String>,
    ): String? {
        val userId = authRepository.currentUserId.value ?: return "Couldn't determine the current user."
        return try {
            val limitMajor = limitMajorText.toDoubleOrNull() ?: 0.0
            val thresholdPct = min(100, max(1, thresholdPctText.toIntOrNull() ?: 80))
            budgetRepository.update(
                id = id,
                name = name.trim().ifBlank { null },
                limitAmount = fromMajor(limitMajor, currency).amount,
                period = period,
                thresholdPct = thresholdPct,
                alertTimeUtc = localToUtcTime(alertTimeLocal),
            )
            budgetRepository.writeScope(userId, id, categoryIds, labelNamesInput)
            reload()
            null
        } catch (e: Exception) {
            "Couldn't save changes: ${e.message}"
        }
    }

    fun delete(id: String) {
        viewModelScope.launch {
            try {
                budgetRepository.delete(id)
                reload()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun formatMoney(m: com.sanvya.app.domain.money.Money): String = numberFormat.format(toMajor(m))

    private fun formatMajorPlain(minor: Long): String {
        val major = minor / 100.0
        return if (major == Math.floor(major)) major.toLong().toString() else major.toString()
    }
}

private fun periodLabel(period: String): String = when (period) {
    "daily" -> "Daily"
    "weekly" -> "Weekly"
    "yearly" -> "Yearly"
    else -> "Monthly"
}

private data class Window(val start: String, val end: String, val label: String)

/** The active date window + label for a budget (current period for
 * recurring) -- matches web's page-local periodWindow() exactly (page.tsx
 * re-derives this client-side for display rather than sharing it with the
 * repository's own window math). UTC-anchored (this codebase's established
 * convention for date math, matching BudgetRepository.spentThisPeriod's own
 * UTC boundaries) rather than web's local-device-time version -- a
 * display-only label, not the query boundary itself. */
private fun periodWindow(period: String, startDate: String?, endDate: String?): Window {
    val dayFmt = DateTimeFormatter.ofPattern("d MMM", Locale.ENGLISH)
    fun fmtDay(isoDay: String): String = try {
        LocalDate.parse(isoDay.take(10)).format(dayFmt)
    } catch (e: Exception) {
        isoDay
    }

    if (startDate != null && endDate != null) {
        val s = startDate.take(10)
        val e = endDate.take(10)
        return Window(s, e, "${fmtDay(s)} – ${fmtDay(e)}")
    }

    val today = LocalDate.now(ZoneOffset.UTC)
    val start: LocalDate
    val end: LocalDate
    when (period) {
        "daily" -> { start = today; end = today }
        "weekly" -> {
            val dow = today.dayOfWeek.value - 1 // 0=Monday...6=Sunday
            start = today.minusDays(dow.toLong())
            end = start.plusDays(6)
        }
        "yearly" -> { start = today.withDayOfYear(1); end = LocalDate.of(today.year, 12, 31) }
        else -> { start = today.withDayOfMonth(1); end = start.plusMonths(1).minusDays(1) }
    }
    return Window(start.toString(), end.toString(), "${fmtDay(start.toString())} – ${fmtDay(end.toString())}")
}

/**
 * Ported from apps/web/src/time.ts's utcToLocalTime/localToUtcTime exactly
 * -- both apply the given "HH:MM" to *today's* date (not a fixed epoch) in
 * the source timezone, then read the clock time back in the target
 * timezone, matching JS's Date.setUTCHours/setHours + toTimeString()
 * behavior (today's date matters for DST correctness).
 */
fun utcToLocalTime(utcTime: String?, defaultLocal: String = "09:00"): String {
    if (utcTime.isNullOrBlank()) return defaultLocal
    val parts = utcTime.split(":")
    if (parts.size != 2) return defaultLocal
    val h = parts[0].toIntOrNull() ?: return defaultLocal
    val m = parts[1].toIntOrNull() ?: return defaultLocal
    val today = LocalDate.now()
    val utc = ZonedDateTime.of(today, java.time.LocalTime.of(h, m), ZoneOffset.UTC)
    val local = utc.withZoneSameInstant(ZoneId.systemDefault())
    return String.format("%02d:%02d", local.hour, local.minute)
}

fun localToUtcTime(localTime: String): String {
    if (localTime.isBlank()) return "00:00"
    val parts = localTime.split(":")
    if (parts.size != 2) return "00:00"
    val h = parts[0].toIntOrNull() ?: return "00:00"
    val m = parts[1].toIntOrNull() ?: return "00:00"
    val today = LocalDate.now()
    val local = ZonedDateTime.of(today, java.time.LocalTime.of(h, m), ZoneId.systemDefault())
    val utc = local.withZoneSameInstant(ZoneOffset.UTC)
    return String.format("%02d:%02d", utc.hour, utc.minute)
}
