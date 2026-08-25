package com.sanvya.app.ui.recurring

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.RecurringRepository
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.ui.FormOptions
import com.sanvya.app.ui.baseCurrencyNow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.LocalDate

data class PickerOption(val id: String, val label: String)

data class RecurringFormOptions(
    val accounts: List<PickerOption> = emptyList(),
    val categories: List<PickerOption> = emptyList(),
)

/**
 * Create / edit a recurring income or payment.
 *
 * Ported from `apps/web/src/cashflow/RecurringModal.tsx`. Absent on both native
 * platforms until now, which is why the Recurring screens had no "+".
 *
 * **Recurring SAVINGS are not created here**, matching web: a SIP is a transfer
 * into an investment account and is set up in Investments, next to the holding
 * it funds. The engine still posts `saving` items — this form just isn't how
 * they are born.
 */
class RecurringFormViewModel : ViewModel(), KoinComponent {
    private val recurringRepository: RecurringRepository by inject()
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    /**
     * Real spending accounts only.
     *
     * Web filters with `isInvestmentAccount(a.type)` and the same
     * `kind = 'real'` / not-archived conditions — a recurring payment cannot
     * come out of a holding, and offering one would produce a row the engine
     * then fails to post.
     */
    val options: StateFlow<RecurringFormOptions> = combine(
        ledgerRepository.watchAccounts(includeArchived = false),
        ledgerRepository.watchCategories(),
    ) { accounts, categories ->
        RecurringFormOptions(
            accounts = accounts
                .filterNot { FormOptions.isInvestmentAccount(it.type) }
                .map { PickerOption(it.id, it.name) },
            // Expense categories only -- web filters `c.kind === "expense"`.
            // The picker only shows for a payment, and an income category in it
            // would write a row that no expense breakdown can then read.
            categories = categories
                .filter { it.kind == "expense" }
                .map { PickerOption(it.id, it.name) },
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = RecurringFormOptions(),
    )

    /** Loads an existing item for editing. Null id = create. */
    fun load(id: String?): StateFlow<RecurringRepository.Item?> = recurringRepository
        .watchActiveItems()
        .map { items -> items.firstOrNull { it.id == id } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    fun clearError() { _error.value = null }

    /**
     * @param amountMajor what the user typed, in major units.
     * @param editingId null to create.
     */
    fun save(
        editingId: String?,
        direction: String,
        name: String,
        amountMajor: String,
        accountId: String?,
        categoryId: String?,
        frequency: String,
        firstDue: String,
        autoPost: Boolean,
        onSaved: () -> Unit,
    ) {
        if (_busy.value) return
        val currency = baseCurrencyNow()
        val major = amountMajor.toDoubleOrNull()
        if (name.isBlank() || major == null || accountId.isNullOrBlank()) return

        viewModelScope.launch {
            _busy.value = true
            _error.value = null
            try {
                val input = RecurringRepository.Input(
                    direction = direction,
                    name = name,
                    // fromMajor, not `* 100`. Web hardcodes the ×100 here and is
                    // wrong for JPY (no minor units) and BHD (three) --
                    // fromMajor asks minorUnits(currency), which is golden rule 1.
                    amountMinor = fromMajor(major, currency).amount,
                    currency = currency,
                    accountId = accountId,
                    // Web only attaches a category to a payment; an income
                    // category would show up in expense breakdowns.
                    categoryId = categoryId?.takeIf { direction == "expense" && it.isNotBlank() },
                    frequency = frequency,
                    firstDue = firstDue,
                    autoPost = autoPost,
                )
                if (editingId != null) {
                    recurringRepository.update(editingId, input)
                } else {
                    // Not `?: return@launch`. That is the silent no-op this
                    // audit has already found four times: the button clears its
                    // busy state and nothing was written. A guest session is
                    // created instead, which is what web does implicitly.
                    val userId = authRepository.currentUserId.value ?: authRepository.ensureGuest()
                    recurringRepository.create(userId, input)
                }
                onSaved()
            } catch (e: Exception) {
                _error.value = e.message ?: "Could not save. Please try again."
            } finally {
                _busy.value = false
            }
        }
    }

    companion object {
        /** Today, for a new item's first due date. Matches web's default. */
        fun todayIso(): String = LocalDate.now().toString()

        /**
         * Web's `FREQS`, which is the same list as the generated
         * `FormOptions.periods` — daily/weekly/monthly/yearly, in that order.
         * Referenced rather than retyped so it cannot drift from the catalogue.
         */
        val FREQUENCIES: List<String> get() = FormOptions.periods
    }
}
