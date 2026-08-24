package com.sanvya.app.ui.recurring

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
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
import java.time.LocalDate

/**
 * One row of the "Due now" list.
 *
 * `amountFormatted` is null when the item has no amount — web renders nothing
 * rather than a zero, because an amount-less commitment is a reminder, not a
 * figure.
 */
data class DueUiModel(
    val id: String,
    val name: String,
    val nextDue: String,
    val amountFormatted: String?,
)

data class RecurringUiState(
    val netMonthlyMinor: Long = 0L,
    val incomeMonthlyMinor: Long = 0L,
    val expenseMonthlyMinor: Long = 0L,
    val incomeCount: Int = 0,
    val expenseCount: Int = 0,
    val due: List<DueUiModel> = emptyList(),
)

class RecurringViewModel : ViewModel(), KoinComponent {
    private val recurringRepository: RecurringRepository by inject()
    private val authRepository: AuthRepository by inject()

    /**
     * Today, captured once when the view model is created rather than read per
     * emission. A `StateFlow` that recomputed `LocalDate.now()` on every
     * upstream tick would silently change what "due" means mid-session; the
     * screen is rebuilt on the next launch anyway.
     */
    private val todayIso: String = LocalDate.now().toString()

    private val busy = MutableStateFlow(false)

    val uiState: StateFlow<RecurringUiState> = combine(
        recurringRepository.watchActiveItems(),
        recurringRepository.watchDueItems(todayIso),
    ) { items, due ->
        // Everything is a MONTHLY equivalent, so a weekly bill and a yearly
        // subscription are comparable. monthlyEquivalent() is the shared
        // domain port, vector-tested -- never sum raw amounts across
        // frequencies.
        fun monthlyOf(direction: String) = items
            .filter { it.direction == direction }
            .sumOf { monthlyEquivalent(it.amount ?: 0L, it.frequency) }

        val income = monthlyOf("income")
        // The column stores 'expense'; web's UI calls the same thing a
        // "payment". Only the label differs -- see RecurringRepository.typeFor.
        val expense = monthlyOf("expense")

        RecurringUiState(
            // Savings are deliberately EXCLUDED, not merely unlisted. A SIP is a
            // transfer between your own accounts: the money leaves the current
            // account but not your net worth, so counting it as an outflow would
            // understate what you actually have spare. Web's summary.ts says the
            // same thing at length.
            netMonthlyMinor = income - expense,
            incomeMonthlyMinor = income,
            expenseMonthlyMinor = expense,
            incomeCount = items.count { it.direction == "income" },
            expenseCount = items.count { it.direction == "expense" },
            due = due.map {
                DueUiModel(
                    id = it.id,
                    name = it.name,
                    nextDue = it.nextDue,
                    // formatMoney(minor, currency), not formatMoneyAware(Money):
                    // the (minor, code) shape is the convenience overload, and
                    // it still respects the hide-amounts toggle.
                    amountFormatted = it.amount?.let { minor ->
                        formatMoney(minor, it.currency ?: baseCurrencyNow())
                    },
                )
            },
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = RecurringUiState(),
    )

    /**
     * Confirm a due occurrence: post the transaction and advance `next_due`.
     *
     * Guarded by [busy] because both buttons mutate the same row and a
     * double-tap would post twice — the engine's own catch-up guard protects
     * against missed occurrences, not against the user.
     */
    fun record(id: String) {
        if (busy.value) return
        viewModelScope.launch {
            busy.value = true
            try {
                val userId = authRepository.currentUserId.value ?: return@launch
                recurringRepository.postOnce(id, userId, baseCurrencyNow())
            } catch (_: Exception) {
                // Left deliberately quiet for now: there is no error surface on
                // this screen yet, and the row stays due, so the failure is
                // visible as "it is still in the list".
            } finally {
                busy.value = false
            }
        }
    }

    /** Advance past one occurrence without posting anything. */
    fun skip(id: String) {
        if (busy.value) return
        viewModelScope.launch {
            busy.value = true
            try {
                recurringRepository.skipOnce(id)
            } catch (_: Exception) {
            } finally {
                busy.value = false
            }
        }
    }
}
