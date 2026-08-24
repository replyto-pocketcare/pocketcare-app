package com.sanvya.app.ui.recurring

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.RecurringRepository
import com.sanvya.app.domain.finance.monthlyEquivalent
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.formatMoney
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * One side of the recurring picture: Income or Expense.
 *
 * **The route segment is the USER-facing word**, not the stored one. `expense`
 * in the URL, `expense` in the column — but web's UI calls the stored `expense`
 * a "payment" in some places, so the mapping is pinned here and nowhere else,
 * exactly as web pins it in its own `SLUGS` table.
 *
 * There is no `saving` slug. A recurring saving is a SIP and belongs to the
 * holding it funds — created and stopped in Investments, not here.
 */
enum class RecurringDirectionSlug(val slug: String, val dbDirection: String) {
    INCOME("income", "income"),
    EXPENSE("expense", "expense");

    companion object {
        fun from(slug: String?): RecurringDirectionSlug? =
            entries.firstOrNull { it.slug == slug?.lowercase() }
    }
}

data class RecurringCategorySlice(
    val id: String,
    /** Empty when [isUncategorised]; the view supplies the localised label. */
    val name: String,
    /**
     * The view, not the view model, names the "no category" bucket.
     *
     * Web hardcodes the English "Uncategorised" in `summarise()`. A view model
     * has no `Resources` and should not hold one, so the flag crosses the
     * boundary and `S.Cashflow.noCategory` is resolved where i18n belongs.
     */
    val isUncategorised: Boolean,
    /** 0..100, already rounded — the view should not do arithmetic. */
    val sharePct: Int,
)

data class RecurringItemUiModel(
    val id: String,
    val name: String,
    val subtitle: String,
    val amountFormatted: String,
)

data class RecurringDirectionUiState(
    val monthlyFormatted: String = "",
    val categories: List<RecurringCategorySlice> = emptyList(),
    val items: List<RecurringItemUiModel> = emptyList(),
)

class RecurringDirectionViewModel : ViewModel(), KoinComponent {
    private val recurringRepository: RecurringRepository by inject()
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val direction = MutableStateFlow(RecurringDirectionSlug.EXPENSE)
    private val busy = MutableStateFlow(false)

    fun setDirection(slug: RecurringDirectionSlug) { direction.value = slug }

    val uiState: StateFlow<RecurringDirectionUiState> = combine(
        recurringRepository.watchActiveItems(),
        ledgerRepository.watchCategories(),
        direction,
    ) { allItems, categories, dir ->
        val categoryNames = categories.associate { it.id to it.name }
        val mine = allItems.filter { it.direction == dir.dbDirection }
        val base = baseCurrencyNow()

        // Monthly equivalents throughout -- never sum raw amounts across
        // frequencies. Same vector-tested helper the summary card uses.
        val perMonth = mine.associate { it.id to monthlyEquivalent(it.amount ?: 0L, it.frequency) }
        val monthly = perMonth.values.sum()

        val byCategory = mine.groupBy { it.categoryId ?: UNCATEGORISED }
            .map { (id, group) -> id to group.sumOf { perMonth[it.id] ?: 0L } }
            .sortedByDescending { it.second }

        RecurringDirectionUiState(
            monthlyFormatted = formatMoney(monthly, base),
            categories = byCategory.map { (id, amount) ->
                RecurringCategorySlice(
                    id = id,
                    name = if (id == UNCATEGORISED) "" else categoryNames[id] ?: "",
                    isUncategorised = id == UNCATEGORISED,
                    // Integer percent, rounded once here. A zero total means no
                    // shares rather than a division by zero.
                    sharePct = if (monthly > 0L) Math.round(amount * 100.0 / monthly).toInt() else 0,
                )
            },
            items = mine.map { item ->
                RecurringItemUiModel(
                    id = item.id,
                    name = item.name,
                    subtitle = buildList {
                        add(item.frequency)
                        item.categoryId?.let { categoryNames[it] }?.takeIf { it.isNotBlank() }?.let(::add)
                        item.nextDue.takeIf { it.isNotBlank() }?.let(::add)
                    }.joinToString(" · "),
                    amountFormatted = formatMoney(item.amount ?: 0L, item.currency ?: base),
                )
            },
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = RecurringDirectionUiState(),
    )

    /** Post one occurrence now and advance. */
    fun recordNow(id: String) {
        if (busy.value) return
        viewModelScope.launch {
            busy.value = true
            try {
                val userId = authRepository.currentUserId.value ?: return@launch
                recurringRepository.postOnce(id, userId, baseCurrencyNow())
            } catch (_: Exception) {
            } finally {
                busy.value = false
            }
        }
    }

    /** Stop the commitment. Soft delete — see RecurringRepository.remove. */
    fun remove(id: String) {
        if (busy.value) return
        viewModelScope.launch {
            busy.value = true
            try {
                recurringRepository.remove(id)
            } catch (_: Exception) {
            } finally {
                busy.value = false
            }
        }
    }

    private companion object {
        /** Group key for items with no category. Never a real category id. */
        const val UNCATEGORISED = "uncategorised"
    }
}
