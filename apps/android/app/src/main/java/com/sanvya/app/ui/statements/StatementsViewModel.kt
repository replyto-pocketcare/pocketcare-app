package com.sanvya.app.ui.statements

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.domain.entitlements.isPaid
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.transactions.TransactionListItem
import com.sanvya.app.ui.transactions.transactionListItem
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
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
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.absoluteValue

/**
 * Which words the day header wears.
 *
 * The view model does not resolve it. `S.Statements.today` needs a `Resources`,
 * and this codebase's rule (I18n.kt, and the same note in
 * RecurringDirectionViewModel) is that a view model must not hold one — so the
 * *kind* of day crosses the boundary and the screen names it.
 */
enum class StatementDayKind { TODAY, YESTERDAY, OTHER }

/**
 * One calendar day of the statement — web's `groupTxnsByDay`.
 *
 * The day is the LOCAL calendar day, not `occurred_at.slice(0, 10)`. Web slices
 * the stored UTC timestamp, so east of Greenwich a 02:00 purchase is filed
 * under yesterday's header while the row beside it prints "2:00 AM" — the
 * header and its own rows disagree. The rows here read local (that is what
 * `transactionListItem` already does), so the header does too.
 */
data class StatementDayGroup(
    val dayIso: String,
    val kind: StatementDayKind,
    /** Day net, sign stripped — the screen prepends + or − from [netIsPositive]. */
    val netFormatted: String,
    val netIsPositive: Boolean,
    val items: List<TransactionListItem>,
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
    /** Web's third summary row — a plain count, not money. */
    val transactionCount: Int = 0,
    val days: List<StatementDayGroup> = emptyList(),
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
 *
 * The rows are `transactionListItem`s, the same model Transactions, Search and
 * the dashboard's recent activity render — web renders one `<TransactionTile>`
 * on all four. The one substitution is the right-hand meta: web's Statements
 * passes the TIME there rather than the date, because the date is already the
 * header of the group the row sits in.
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

    /**
     * Everything the row model needs beyond the transaction itself.
     *
     * Its own `combine` because Kotlin's tops out at five flows and the state
     * below already spends four — and because these three are range-independent,
     * so they are not re-read every time the user nudges a date.
     */
    private data class RowContext(
        val accounts: List<com.sanvya.app.data.repository.Account>,
        val categories: List<com.sanvya.app.data.repository.CategoryRow>,
        val labelNames: Map<String, List<String>>,
    )

    private val rowContext: Flow<RowContext> = combine(
        ledgerRepository.watchAccounts(includeArchived = true),
        ledgerRepository.watchCategories(),
        ledgerRepository.watchTransactionLabelNames(),
    ) { accounts, categories, labelNames -> RowContext(accounts, categories, labelNames) }

    val uiState: StateFlow<StatementsUiState> =
        combine(entitlement, rows, rowContext, _start, _end) { ent, txns, ctx, start, end ->
            val (paid, known) = ent
            val base = baseCurrencyNow()
            val income = txns.filter { it.type == "income" }.sumOf { it.amount }
            val expense = txns.filter { it.type == "expense" }.sumOf { it.amount }
            val net = income - expense
            val accountMap = ctx.accounts.associateBy { it.id }
            val categoryMap = ctx.categories.associateBy { it.id }

            val today = LocalDate.now()
            val days = txns
                .groupBy { localDayOf(it.occurredAt) }
                .entries
                // Newest day first, and newest row first inside it — web's
                // `.sort((a, b) => b[0].localeCompare(a[0]))` and the same on
                // the rows.
                .sortedByDescending { it.key }
                .map { (dayIso, items) ->
                    val dayNet = items.sumOf {
                        when (it.type) {
                            "income" -> it.amount
                            "expense" -> -it.amount
                            else -> 0L
                        }
                    }
                    StatementDayGroup(
                        dayIso = dayIso,
                        kind = when (dayIso) {
                            today.toString() -> StatementDayKind.TODAY
                            today.minusDays(1).toString() -> StatementDayKind.YESTERDAY
                            else -> StatementDayKind.OTHER
                        },
                        netFormatted = formatMoney(dayNet.absoluteValue, base),
                        netIsPositive = dayNet >= 0,
                        items = items
                            .sortedByDescending { it.occurredAt }
                            .map { txn ->
                                transactionListItem(
                                    txn = txn,
                                    accountMap = accountMap,
                                    categoryMap = categoryMap,
                                    labels = ctx.labelNames[txn.id],
                                ).copy(
                                    // Web's Statements passes a TIME as the
                                    // row's meta, not a date: the date is the
                                    // header this row already sits under, and
                                    // repeating it on every line says nothing.
                                    dateFormatted = timeOf(txn.occurredAt),
                                )
                            },
                    )
                }

            StatementsUiState(
                isPaid = paid,
                entitlementKnown = known,
                start = start,
                end = end,
                incomeFormatted = formatMoney(income, base),
                expenseFormatted = formatMoney(expense, base),
                netFormatted = formatMoney(net.absoluteValue, base),
                netIsPositive = net >= 0,
                transactionCount = txns.size,
                days = days,
            )
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = StatementsUiState(),
        )
}

/**
 * The local calendar day a timestamp fell on, as `yyyy-MM-dd`.
 *
 * Falls back to the stored date part when the string is not a timestamp this
 * can parse — the same defensive shape `transactionListItem` uses, because a
 * row that cannot be parsed still has to land in some group.
 */
private fun localDayOf(occurredAt: String): String = runCatching {
    OffsetDateTime.parse(occurredAt).atZoneSameInstant(ZoneId.systemDefault()).toLocalDate().toString()
}.getOrDefault(occurredAt.take(10))

/**
 * "2:30 PM" — web's `toLocaleTimeString(undefined, { hour: "numeric", minute:
 * "2-digit" })`. `ofLocalizedTime(SHORT)` rather than a pattern: whether the
 * clock is 12- or 24-hour is a locale fact, and a pattern picks one for
 * everybody.
 */
private fun timeOf(occurredAt: String): String = runCatching {
    OffsetDateTime.parse(occurredAt)
        .atZoneSameInstant(ZoneId.systemDefault())
        .format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))
}.getOrDefault("")
