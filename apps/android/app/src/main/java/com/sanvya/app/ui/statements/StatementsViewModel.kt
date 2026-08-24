package com.sanvya.app.ui.statements

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.domain.entitlements.isPaid
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.formatMoney
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.LocalDate
import kotlin.math.absoluteValue

data class StatementTxUiModel(
    val id: String,
    val title: String,
    val occurredOn: String,
    val amountFormatted: String,
    val isIncome: Boolean,
)

data class StatementsUiState(
    val isPaid: Boolean = false,
    /**
     * False until the entitlement row has actually been read once.
     *
     * The screen shows neither the statement nor the upsell while this is
     * false. Defaulting `isPaid` to false and rendering immediately would flash
     * "Go Premium" at a paying user on every cold start, before the local
     * entitlement row has been read — a small thing that reads as being asked
     * to pay twice.
     */
    val entitlementKnown: Boolean = false,
    val start: String = "",
    val end: String = "",
    val incomeFormatted: String = "",
    val expenseFormatted: String = "",
    val netFormatted: String = "",
    val netIsPositive: Boolean = true,
    val transactions: List<StatementTxUiModel> = emptyList(),
)

/**
 * Ported from apps/web/app/statements/page.tsx.
 *
 * **iOS shipped a completely different, invented feature under this name** — a
 * searchable list of "July 2026" / "2025 Annual Statement" cards, with a
 * premium padlock on the annual one. No such documents exist anywhere in this
 * product. Web's Statements is a *date-ranged* view of real transactions with
 * an income/expense summary, gated behind a paid tier. Android had no screen at
 * all, which was at least honest.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class StatementsViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val prefsRepository: PrefsRepository by inject()

    /** Defaults to this calendar month so far, exactly as web does. */
    private val _start = MutableStateFlow(LocalDate.now().withDayOfMonth(1).toString())
    private val _end = MutableStateFlow(LocalDate.now().toString())

    fun setStart(iso: String) {
        _start.value = iso
        // Web drags `end` along rather than rejecting the input, which is the
        // kinder behaviour: the user is mid-thought, not making a mistake.
        if (iso > _end.value) _end.value = iso
    }

    fun setEnd(iso: String) {
        if (iso >= _start.value) _end.value = iso
    }

    private val entitlement = prefsRepository.watchEntitlement()
        .map { row ->
            isPaid(
                row?.tier,
                row?.premiumTrialStartDate,
                row?.compTier,
                row?.compUntil,
                System.currentTimeMillis(),
            ) to true
        }
        // Offline or unreadable: keep the gate CLOSED rather than guessing it
        // open, but report the entitlement as still unknown so the screen shows
        // nothing instead of the upsell.
        .catch { emit(false to false) }

    private val rows = combine(_start, _end) { s, e -> s to e }
        .flatMapLatest { (s, e) ->
            ledgerRepository.watchTransactionsInRange(
                startIso = "${s}T00:00:00.000Z",
                // `end` advanced one whole day, matching web: occurred_at is a
                // timestamp, so `< end` on the bare date would drop everything
                // that happened after midnight on the final day.
                endIso = "${LocalDate.parse(e).plusDays(1)}T00:00:00.000Z",
            )
        }

    val uiState: StateFlow<StatementsUiState> =
        combine(entitlement, rows, _start, _end) { ent, txns, start, end ->
            val (paid, known) = ent
            val base = baseCurrencyNow()
            val income = txns.filter { it.type == "income" }.sumOf { it.amount }
            val expense = txns.filter { it.type == "expense" }.sumOf { it.amount }
            val net = income - expense
            StatementsUiState(
                isPaid = paid,
                entitlementKnown = known,
                start = start,
                end = end,
                incomeFormatted = formatMoney(income, base),
                expenseFormatted = formatMoney(expense, base),
                netFormatted = formatMoney(net.absoluteValue, base),
                netIsPositive = net >= 0,
                transactions = txns.map { t ->
                    StatementTxUiModel(
                        id = t.id,
                        // Web's TransactionTile falls back through description
                        // then note; an untitled row shows as blank rather than
                        // as an invented label.
                        title = t.description?.takeIf { it.isNotBlank() }
                            ?: t.note?.takeIf { it.isNotBlank() }
                            ?: "",
                        occurredOn = t.occurredAt.take(10),
                        amountFormatted = formatMoney(t.amount, t.currency),
                        isIncome = t.type == "income",
                    )
                },
            )
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = StatementsUiState(),
        )
}
