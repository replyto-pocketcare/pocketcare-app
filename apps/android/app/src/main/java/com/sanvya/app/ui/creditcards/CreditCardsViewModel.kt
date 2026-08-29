package com.sanvya.app.ui.creditcards

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.CardCharge
import com.sanvya.app.data.repository.CoveredEmi
import com.sanvya.app.data.repository.CreditCardDetails
import com.sanvya.app.data.repository.CreditCardRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.LoansRepository
import com.sanvya.app.data.repository.SettingsRepository
import com.sanvya.app.domain.budget.billingCycle
import com.sanvya.app.domain.money.fromMajor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.Instant
import java.time.LocalDate
import com.sanvya.app.ui.formatMajorPlain
import com.sanvya.app.ui.formatMoney

data class SettleSourceOption(val id: String, val name: String)

data class CreditCardUiModel(
    val accountId: String,
    val accountName: String,
    val accountColorHex: String?,
    val currency: String,
    val last4: String?,
    val owed: Long,
    val owedFormatted: String,
    val creditLimit: Long?,
    val creditLimitFormatted: String?,
    val availableCreditFormatted: String?,
    val hasCycle: Boolean,
    val statementDay: Int,
    val dueDay: Int,
    val statementDateIso: String?,
    val payByIso: String?,
    val dueThisCycle: Long?,
    val dueThisCycleFormatted: String?,
    val rolledToNext: Boolean,
    val pendingDueFormatted: String?,
    /**
     * Seed text for the "amount due" input, in MAJOR units and unformatted.
     *
     * Web seeds its input with `String(toMajor(money(pending_due, ccy)))`; the
     * same value has to reach the field here or a save that did not touch it
     * would write null over the user's amount. A formatted string could not
     * serve -- it carries a currency symbol, grouping and the privacy mask, so
     * it is not something the user can type back.
     */
    val pendingDueMajorText: String,
    /** Seed text for the "credit limit" input -- same reasoning as
     * [pendingDueMajorText]. */
    val creditLimitMajorText: String,
    val newSpend: Long,
    val newSpendFormatted: String?,
    /** Charges behind the balance. Only the COUNT is carried here -- the rows
     * themselves are read on demand when the user opens the list, so the
     * screen still knows whether to offer it. */
    val chargeCount: Int,
)

/** One row of the "View transactions" list. `description` stays nullable so
 * the screen, which owns `Resources`, applies the localised fallback -- the
 * same split already used for [CreditCardsViewModel.holderName]. */
data class CardChargeUiModel(
    val id: String,
    val description: String?,
    val amountFormatted: String,
    val occurredAtIso: String,
)

/** The open "View transactions" list: the charges behind one card's balance
 * plus their running total, which is web's `chargesTotal`. */
data class CardChargesUiModel(
    val accountId: String,
    val rows: List<CardChargeUiModel>,
    val totalFormatted: String,
)

/**
 * Real port of apps/web/app/cards/page.tsx (task #29), replacing an
 * entirely fake predecessor: hardcoded "Bank • Visa" network label, a fake
 * "Day N" due string instead of real billing-cycle math, a random
 * alternating gradient instead of the account's own color, no settle-up
 * flow, no covered-EMI confirm, no editable statement/due-day/limit/last4
 * form. Was also constructor-injected with no consuming screen (dead code,
 * same broken shape every other screen started this engagement in) --
 * converted to the established KoinComponent/by-inject() convention.
 * See docs/mobile/screen-specs/credit-cards.md for the full
 * source-verification notes.
 */
class CreditCardsViewModel : ViewModel(), KoinComponent {
    private val creditCardRepository: CreditCardRepository by inject()
    private val ledgerRepository: LedgerRepository by inject()
    private val loansRepository: LoansRepository by inject()
    private val authRepository: AuthRepository by inject()
    private val settingsRepository: SettingsRepository by inject()

    private val _cards = MutableStateFlow<List<CreditCardUiModel>>(emptyList())
    val cards: StateFlow<List<CreditCardUiModel>> = _cards

    private val _sources = MutableStateFlow<List<SettleSourceOption>>(emptyList())
    val sources: StateFlow<List<SettleSourceOption>> = _sources

    private val _loaded = MutableStateFlow(false)
    val loaded: StateFlow<Boolean> = _loaded

    /**
     * The signed-in user's display name, for the name printed on the card face.
     *
     * Web reads `session.username` (src/account) and falls back to the
     * `cardHolder` string only when it is blank -- so this stays the RAW name
     * and the screen applies the fallback, keeping the localised default in the
     * layer that owns `Resources`. Read once rather than watched: the name only
     * changes from Settings, which is a different screen.
     */
    private val _holderName = MutableStateFlow("")
    val holderName: StateFlow<String> = _holderName

    /** Covered EMIs from the most recent settle() -- non-empty triggers the
     * "Mark N EMI(s) paid?" confirm dialog. */
    private val _coveredEmis = MutableStateFlow<List<CoveredEmi>>(emptyList())
    val coveredEmis: StateFlow<List<CoveredEmi>> = _coveredEmis
    private var settledAt: String = ""

    /** The open "View transactions" list, or null when it is closed. Held on
     * the view model rather than per-panel state so the rows survive a
     * recomposition of the list behind the modal. */
    private val _charges = MutableStateFlow<CardChargesUiModel?>(null)
    val charges: StateFlow<CardChargesUiModel?> = _charges

    init {
        viewModelScope.launch {
            // Offline / signed-out reads throw; an empty name just falls back to
            // the "Card Holder" label, so a failure here must not kill the
            // collector below.
            _holderName.value = runCatching { settingsRepository.currentSession()?.username }.getOrNull().orEmpty().trim()
        }
        viewModelScope.launch {
            combine(
                ledgerRepository.watchAccountBalances(includeArchived = false),
                creditCardRepository.watchAllDetails(),
            ) { balances, details -> balances to details }.collect { (balances, details) ->
                val cardBalances = balances.filter { it.account.type.equals("credit_card", ignoreCase = true) }
                _sources.value = balances
                    .filter { !it.account.type.equals("credit_card", ignoreCase = true) }
                    .map { SettleSourceOption(it.account.id, it.account.name) }

                val detailsById = details.associateBy { it.accountId }
                val today = LocalDate.now()
                _cards.value = cardBalances.map { ab ->
                    val detail = detailsById[ab.account.id]
                    val owed = kotlin.math.abs(ab.balance.amount)
                    val currency = ab.account.currency

                    if (detail == null) {
                        CreditCardUiModel(
                            accountId = ab.account.id, accountName = ab.account.name, accountColorHex = ab.account.color,
                            currency = currency, last4 = null, owed = owed, owedFormatted = formatMoney(owed, currency),
                            creditLimit = null, creditLimitFormatted = null, availableCreditFormatted = null,
                            hasCycle = false, statementDay = 1, dueDay = 20, statementDateIso = null, payByIso = null,
                            dueThisCycle = null, dueThisCycleFormatted = null, rolledToNext = false,
                            pendingDueFormatted = null,
                            pendingDueMajorText = "", creditLimitMajorText = "",
                            newSpend = 0L, newSpendFormatted = null,
                            chargeCount = creditCardRepository.chargeCount(ab.account.id),
                        )
                    } else {
                        val cycle = billingCycle(detail.statementDay, detail.dueDay, today)
                        val newSpend = creditCardRepository.cycleSpend(ab.account.id, "${cycle.cycleStart}T00:00:00.000Z")
                        val dueOnDate = detail.dueOn?.take(10)?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: cycle.dueDate
                        val rolledToNext = detail.pendingDue != null && dueOnDate.isAfter(cycle.dueDate)
                        val dueThisCycle = if (detail.pendingDue == null) null else if (rolledToNext) 0L else detail.pendingDue
                        val availableCredit = detail.creditLimit?.let { maxOf(0L, it - owed) }

                        CreditCardUiModel(
                            accountId = ab.account.id, accountName = ab.account.name, accountColorHex = ab.account.color,
                            currency = currency, last4 = detail.cardLast4, owed = owed, owedFormatted = formatMoney(owed, currency),
                            creditLimit = detail.creditLimit, creditLimitFormatted = detail.creditLimit?.let { formatMoney(it, currency) },
                            availableCreditFormatted = availableCredit?.let { formatMoney(it, currency) },
                            hasCycle = true, statementDay = detail.statementDay, dueDay = detail.dueDay,
                            statementDateIso = cycle.statementDate.toString(), payByIso = dueOnDate.toString(),
                            dueThisCycle = dueThisCycle, dueThisCycleFormatted = dueThisCycle?.let { formatMoney(it, currency) },
                            rolledToNext = rolledToNext,
                            pendingDueFormatted = detail.pendingDue?.let { formatMoney(it, currency) },
                            // `formatMajorPlain`, not `formatMoney`: these two
                            // are typed back into number fields, so no symbol,
                            // no grouping and no privacy mask -- and the scale
                            // still comes from the currency, not from 100.
                            pendingDueMajorText = detail.pendingDue?.let { formatMajorPlain(it, currency) } ?: "",
                            creditLimitMajorText = detail.creditLimit?.let { formatMajorPlain(it, currency) } ?: "",
                            newSpend = newSpend, newSpendFormatted = if (newSpend > 0) formatMoney(newSpend, currency) else null,
                            chargeCount = creditCardRepository.chargeCount(ab.account.id),
                        )
                    }
                }
                _loaded.value = true
            }
        }
    }

    /**
     * Matches web's `saveCycle()`: statement/due day clamped 1-28, limit and
     * typed due-amount go through `upsertDetails`/`setCycleDetails` (the latter
     * recomputes `due_on` from the possibly-new cycle so "pay by" stays
     * correct).
     *
     * **Every nullable column this touches is a full overwrite, not a patch.**
     * `upsertDetails` writes `credit_limit` and `card_last4`; `setCycleDetails`
     * writes `pending_due` and `due_on`. So whatever the form holds IS the new
     * row, and the screen's contract is that the form was seeded from the
     * stored detail before the user ever saw it -- see the seeding
     * `LaunchedEffect` in CreditCardsScreen.kt. `due_on` is the one column that
     * can never go null: it is recomputed from the cycle on every save.
     *
     * A blank amount-due field therefore still means "unset this", which is
     * web's behaviour and the only way a user can clear a statement amount.
     * `existingCreditLimit` keeps web's asymmetry: the limit falls back rather
     * than clearing, because web's `saveCycle` does the same.
     */
    suspend fun saveCycle(
        accountId: String, currency: String, statementDayText: String, dueDayText: String,
        creditLimitMajorText: String, dueAmountMajorText: String, last4: String,
        existingCreditLimit: Long?,
    ): String? {
        val userId = authRepository.currentUserId.value ?: return "Couldn't determine the current user."
        val sDay = (statementDayText.toIntOrNull() ?: 1).coerceIn(1, 28)
        val dDay = (dueDayText.toIntOrNull() ?: 20).coerceIn(1, 28)
        val creditLimit = creditLimitMajorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount } ?: existingCreditLimit
        val pendingDue = dueAmountMajorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount }
        return try {
            creditCardRepository.upsertDetails(
                userId,
                CreditCardDetails(
                    accountId = accountId, statementDay = sDay, dueDay = dDay, creditLimit = creditLimit,
                    cardLast4 = last4.takeLast(4).ifBlank { null }, pendingDue = null, dueOn = null,
                ),
            )
            val cycle = billingCycle(sDay, dDay, LocalDate.now())
            creditCardRepository.setCycleDetails(accountId, pendingDue, cycle.dueDate.toString())
            null
        } catch (e: Exception) {
            "Couldn't save card details: ${e.message}"
        }
    }

    /** Settle the bill, then check whether the payment covers any EMIs
     * charged to this card -- if so, populate [coveredEmis] so the screen
     * can ask before marking anything (never auto-marks). */
    suspend fun settle(cardAccountId: String, currency: String, fromAccountId: String, amountMajorText: String): String? {
        val userId = authRepository.currentUserId.value ?: return "Couldn't determine the current user."
        val amountMajor = amountMajorText.toDoubleOrNull()
        if (amountMajor == null || amountMajor <= 0) return "Enter an amount."
        val amount = fromMajor(amountMajor, currency)
        val when_ = Instant.now().toString()
        return try {
            creditCardRepository.settle(userId, fromAccountId, cardAccountId, amount, occurredAt = when_)
            val covered = loansRepository.findCoveredEmis(cardAccountId, amount.amount)
            if (covered.isNotEmpty()) {
                settledAt = when_
                _coveredEmis.value = covered
            }
            null
        } catch (e: Exception) {
            "Couldn't settle: ${e.message}"
        }
    }

    /**
     * Load the charges behind [accountId]'s balance and open the list.
     *
     * The running total is the sum of the rows actually listed, exactly as
     * web's `chargesTotal` is -- both are capped at `CARD_CHARGES_LIMIT`, so a
     * card with more charges than that shows the same total on both clients.
     */
    fun openCharges(accountId: String, currency: String) {
        viewModelScope.launch {
            val rows = runCatching { creditCardRepository.charges(accountId) }.getOrDefault(emptyList())
            val total = rows.sumOf(CardCharge::amount)
            _charges.value = CardChargesUiModel(
                accountId = accountId,
                rows = rows.map {
                    CardChargeUiModel(
                        id = it.id,
                        description = it.description,
                        amountFormatted = formatMoney(it.amount, currency),
                        occurredAtIso = it.occurredAt,
                    )
                },
                totalFormatted = formatMoney(total, currency),
            )
        }
    }

    fun closeCharges() {
        _charges.value = null
    }

    fun confirmMarkEmisPaid() {
        val covered = _coveredEmis.value
        if (covered.isEmpty()) return
        viewModelScope.launch {
            loansRepository.markEmisPaid(covered, settledAt)
            _coveredEmis.value = emptyList()
        }
    }

    fun skipMarkEmisPaid() {
        _coveredEmis.value = emptyList()
    }
}
