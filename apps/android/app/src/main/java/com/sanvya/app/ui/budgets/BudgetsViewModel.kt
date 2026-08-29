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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import com.sanvya.app.ui.formatMoneyAware
import com.sanvya.app.ui.formatMajorPlain
import com.sanvya.app.ui.shortDateLabel
import com.sanvya.app.data.repository.BudgetTxn
import com.sanvya.app.domain.budget.SpendPoint
import com.sanvya.app.domain.budget.cumulativeSpendSeries
import com.sanvya.app.domain.money.Money

enum class ProgressColor { POSITIVE, WARNING, NEGATIVE }

data class BudgetUiModel(
    val id: String,
    /**
     * The budget's own name, or its scope read back as a list. BLANK when it
     * has neither -- the screen substitutes `S.Budgets.allSpending` there,
     * because a ViewModel outside composition has no `Resources` and a
     * hardcoded "All spending" is exactly the English that leaked into two
     * translated apps the last time this was composed here.
     */
    val title: String,
    /** `1 Aug – 31 Aug`. The period word in front of it is the screen's, for
     * the same reason [title]'s fallback is. */
    val winLabel: String,
    val scopeLabel: String,
    /** Just the money. The "{{amount}} spent" sentence around it is the
     * screen's -- see [title]. */
    val spentAmountFormatted: String,
    /** Minor units, so the drill-down can say when its rows disagree. */
    val spentMinor: Long,
    /** Either what is left or what is over, depending on [overLimit]. */
    val remainderAmountFormatted: String,
    val overLimit: Boolean,
    val progress: Double,
    /**
     * The rounded percentage, or null when the limit is zero and the ratio is
     * infinite -- web prints an em dash there rather than "Infinity%".
     */
    val pctRounded: Int?,
    val progressColor: ProgressColor,
    /** Cumulative spend across the active window, for the card's chart. */
    val spendSeries: List<SpendPoint>,
    /** The limit in MINOR units, for the chart's reference line -- minor so
     * the chart converts once, with `majorScale`, instead of converting back. */
    val limitMinor: Long,
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
 * One expense behind a budget's "spent" figure, formatted for the drill-down.
 *
 * The pieces stay separate rather than pre-joined into a sentence: the title
 * falls back through description -> note -> category -> a translated "Expense",
 * and that last step needs the `Resources` only the screen has.
 */
data class BudgetTxnUiModel(
    val id: String,
    val description: String?,
    val note: String?,
    val categoryName: String?,
    val accountName: String?,
    val dateLabel: String,
    val amountFormatted: String,
)

/**
 * The open "what is this figure made of" drill-down -- web's
 * apps/web/src/budgets/SpentBreakdown.tsx.
 *
 * [rows] is null while the query is in flight, which is the spinner state; an
 * empty list is the genuinely-nothing-here state. Web draws the same
 * distinction and it matters: a budget with no spend yet and a budget still
 * loading look identical if both are an empty list.
 */
data class SpentBreakdownState(
    val budgetId: String,
    val title: String,
    val spentAmountFormatted: String,
    val rows: List<BudgetTxnUiModel>?,
    val count: Int,
    val listedTotalFormatted: String,
    /**
     * The rows do not sum to the card's figure. They share a scope clause, so
     * the only way this happens is a scope change landing mid-read -- worth
     * saying out loud rather than quietly showing a total that contradicts the
     * card the user just tapped.
     */
    val mismatch: Boolean,
)

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

    private val _budgets = MutableStateFlow<List<BudgetUiModel>>(emptyList())
    val budgets: StateFlow<List<BudgetUiModel>> = _budgets

    /** The rows as the database has them, kept beside the UI models because
     * every repository read below takes a [BudgetLike], not a view model. */
    private val _rawBudgets = MutableStateFlow<List<BudgetLike>>(emptyList())

    private val _expenseCategories = MutableStateFlow<List<CategoryOption>>(emptyList())
    val expenseCategories: StateFlow<List<CategoryOption>> = _expenseCategories

    private val _labelNames = MutableStateFlow<List<String>>(emptyList())
    val labelNames: StateFlow<List<String>> = _labelNames

    /** The open spent drill-down, or null.
     *
     * Declared ABOVE `init` on purpose. `viewModelScope.launch` runs on
     * `Dispatchers.Main.immediate`, which executes a coroutine body eagerly
     * when it is already on the main thread -- so a property `rebuild()` reads
     * must be initialised before the init block, or the first emission finds a
     * null field. */
    private val _breakdown = MutableStateFlow<SpentBreakdownState?>(null)
    val breakdown: StateFlow<SpentBreakdownState?> = _breakdown

    init {
        viewModelScope.launch {
            ledgerRepository.watchCategories().collect { rows ->
                _expenseCategories.value = rows.filter { it.kind == "expense" }.map { CategoryOption(it.id, it.name) }
            }
        }
        viewModelScope.launch {
            ledgerRepository.watchLabels().collect { rows -> _labelNames.value = rows.map { it.name } }
        }
        viewModelScope.launch {
            budgetRepository.watchBudgets().collect { list -> rebuild(list) }
        }
    }

    /** Recomputes the list's UI rows (spend/scope/progress) whenever
     * [budgetRepository]'s live `budgets` watch emits -- i.e. on any local
     * write from any screen, not just this ViewModel's own instance. Fixed
     * 2026-08-06: this used to be a suspend `reload()` called once at init
     * and again explicitly after each mutation, which only ever updated
     * THIS instance -- since Add/Edit Budget are separate nav routes with
     * their own BudgetsViewModel, a save there never reached the list
     * screen's instance, so new/edited budgets didn't appear until the
     * whole "budgets" route was torn down and recreated. Per-budget spend
     * (spentThisPeriod/categoryIds/labelNames) is still a one-shot suspend
     * read per row -- it recomputes on every `budgets`-table change, which
     * covers create/edit/delete, but won't itself react to a new
     * transaction changing spend without a `budgets` row also changing
     * (pre-existing scope, unrelated to this fix). */
    private suspend fun rebuild(list: List<BudgetLike>) {
        try {
            _rawBudgets.value = list
            val today = LocalDate.now(ZoneOffset.UTC)
            val uis = list.map { b ->
                val spent = budgetRepository.spentThisPeriod(b, today)
                val limit = money(b.limitAmount, b.currency)
                val progress = budgetProgress(limit, spent, b.thresholdPct.toDouble())
                val catIds = budgetRepository.categoryIds(b.id)
                val labels = budgetRepository.labelNames(b.id)
                val catNames = catIds.mapNotNull { id -> _expenseCategories.value.find { it.id == id }?.name }
                val scopeNames = catNames + labels
                val scopeLabel = scopeNames.joinToString(", ")
                val win = periodWindow(b.period, b.startDate, b.endDate)
                val isCustom = b.startDate != null && b.endDate != null
                val color = when {
                    progress.overLimit -> ProgressColor.NEGATIVE
                    progress.atOrOverThreshold -> ProgressColor.WARNING
                    else -> ProgressColor.POSITIVE
                }
                // The window comes back WITH the daily totals rather than from
                // periodWindow() above: the two agree today, and the day they
                // stop agreeing is the day the chart's axis stops describing
                // the rows under it. The label is display-only and can stay
                // where web put it; the axis cannot.
                val daily = budgetRepository.dailySpendThisPeriod(b, today)
                BudgetUiModel(
                    id = b.id,
                    title = b.name?.takeIf { it.isNotBlank() } ?: scopeLabel,
                    winLabel = win.label,
                    scopeLabel = scopeLabel,
                    spentAmountFormatted = formatMoney(spent),
                    spentMinor = spent.amount,
                    remainderAmountFormatted = if (progress.overLimit) {
                        formatMoney(money(spent.amount - limit.amount, b.currency))
                    } else {
                        formatMoney(progress.remaining)
                    },
                    overLimit = progress.overLimit,
                    progress = if (progress.pct.isFinite()) progress.pct / 100 else 1.0,
                    pctRounded = if (progress.pct.isFinite()) progress.pct.roundToInt() else null,
                    progressColor = color,
                    spendSeries = cumulativeSpendSeries(
                        dailyTotals = daily.totals,
                        startIso = daily.startIso,
                        endIso = daily.endIso,
                        todayIso = today.toString(),
                    ),
                    limitMinor = b.limitAmount,
                    rawName = b.name ?: "",
                    limitMajor = formatMajorPlain(b.limitAmount, b.currency),
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
            // A budget the drill-down is open on may have just changed scope.
            // Re-reading it here is what makes the mismatch note in
            // SpentBreakdownState a real signal rather than a stale one.
            _breakdown.value?.let { open -> refreshBreakdown(open.budgetId) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ---- spent breakdown (web: apps/web/src/budgets/SpentBreakdown.tsx) ----

    /**
     * Opens the drill-down for [budgetId], showing the spinner immediately and
     * filling the rows when the query lands -- web resets `rows` to null on
     * every open for exactly this reason.
     */
    fun openBreakdown(budgetId: String) {
        val budget = _budgets.value.firstOrNull { it.id == budgetId } ?: return
        _breakdown.value = SpentBreakdownState(
            budgetId = budgetId,
            title = budget.title,
            spentAmountFormatted = budget.spentAmountFormatted,
            rows = null,
            count = 0,
            listedTotalFormatted = "",
            mismatch = false,
        )
        viewModelScope.launch { refreshBreakdown(budgetId) }
    }

    fun closeBreakdown() {
        _breakdown.value = null
    }

    /** Reads the rows behind [budgetId]'s figure through the repository's
     * shared scope clause, so the list cannot disagree with the total for any
     * reason other than a scope change landing mid-read. */
    private suspend fun refreshBreakdown(budgetId: String) {
        // The stored DB row, not one rebuilt from the UI model: scopeClause()
        // reads the budget's period and dates, and a reconstructed BudgetLike
        // is one field away from asking a different question than the card did.
        val row = _rawBudgets.value.firstOrNull { it.id == budgetId } ?: return
        val budget = _budgets.value.firstOrNull { it.id == budgetId } ?: return
        val rows: List<BudgetTxn> = try {
            budgetRepository.transactionsThisPeriod(row, LocalDate.now(ZoneOffset.UTC))
        } catch (e: Exception) {
            e.printStackTrace()
            emptyList()
        }
        val listed = rows.sumOf { it.amount }
        _breakdown.value = _breakdown.value?.takeIf { it.budgetId == budgetId }?.copy(
            title = budget.title,
            spentAmountFormatted = budget.spentAmountFormatted,
            rows = rows.map { r ->
                BudgetTxnUiModel(
                    id = r.id,
                    description = r.description,
                    note = r.note,
                    categoryName = r.categoryName,
                    accountName = r.accountName,
                    dateLabel = shortDateLabel(r.occurredAt),
                    amountFormatted = formatMoney(money(r.amount, r.currency)),
                )
            },
            count = rows.size,
            listedTotalFormatted = formatMoney(money(listed, row.currency)),
            mismatch = listed != budget.spentMinor,
        )
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
            null
        } catch (e: Exception) {
            "Couldn't save changes: ${e.message}"
        }
    }

    fun delete(id: String) {
        viewModelScope.launch {
            try {
                budgetRepository.delete(id)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun formatMoney(m: Money): String = formatMoneyAware(m)

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
