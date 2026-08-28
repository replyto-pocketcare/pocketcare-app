package com.sanvya.app.ui.accounts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.CreditCardDetails
import com.sanvya.app.data.repository.CreditCardRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.domain.cards.CardDue
import com.sanvya.app.domain.cards.cardDueDate
import com.sanvya.app.domain.cards.clampCardDay
import com.sanvya.app.domain.js.jsParseFloat
import com.sanvya.app.domain.money.fromMajor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.Instant
import java.time.LocalDate
import com.sanvya.app.ui.FormOptions

/** The 7 apps/web AccountType values (packages/types/src/index.ts). The
 * credit-card branch was added 2026-08-28; demat differs only in its copy. */
val ACCOUNT_TYPES = FormOptions.accountTypes
val ACCOUNT_CURRENCIES = FormOptions.currencies

/** Hex, because hex is what `accounts.color` stores. */
val ACCOUNT_COLOR_HEX = FormOptions.accountColors

data class CreateAccountUiState(
    val name: String = "",
    val type: String = "savings",
    val currency: String = FormOptions.DEFAULT_CURRENCY,
    val color: String = ACCOUNT_COLOR_HEX.first(),
    val includeInNetWorth: Boolean = true,
    /** null = "follow type default" (matches web's `allowNeg: Boolean | null`
     * exactly -- accounts/new/page.tsx's `allowNegEffective = allowNeg ?? isCard`).
     * Not modeled as a plain Boolean: that would lose the "user hasn't
     * touched this yet" state and make the toggle silently stop following
     * the type when the user picks a different account type. */
    val allowNegativeOverride: Boolean? = null,
    val openingBalance: String = "",
    // ---- credit card ----
    /** The card's limit, as typed. Optional: web stores 0 when it is blank. */
    val creditLimit: String = "",
    /** What is owed on the current statement, as typed. */
    val dueAmount: String = "",
    /** Web's defaults, as STRINGS, because the field is a string and "" has to
     * survive as "" until save clamps it. */
    val statementDay: String = "1",
    val dueDay: String = "20",
    val saving: Boolean = false,
    val savedAccountId: String? = null,
    /** The saved account's type, so the caller can route where web routes:
     * cards for a card, investments for a demat, accounts otherwise. */
    val savedType: String? = null,
) {
    val allowNegativeEffective: Boolean get() = allowNegativeOverride ?: (type == "credit_card")

    val isCard: Boolean get() = type == "credit_card"
    val isDemat: Boolean get() = type == "demat"

    /**
     * Live preview of the cycle, so the user understands the roll-forward rule
     * before saving rather than after. Null when there is nothing to preview --
     * web gates it on `isCard && dueAmount`, and an empty box has no date.
     */
    val cardPreview: CardDue?
        get() = if (!isCard || dueAmount.isBlank()) {
            null
        } else {
            cardDueDate(
                createdIso = LocalDate.now().toString(),
                statementDay = clampCardDay(statementDay, 1),
                dueDay = clampCardDay(dueDay, 20),
            )
        }
}

class CreateAccountViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()
    private val creditCardRepository: CreditCardRepository by inject()

    private val _uiState = MutableStateFlow(CreateAccountUiState())
    val uiState: StateFlow<CreateAccountUiState> = _uiState.asStateFlow()

    fun setName(v: String) = update { it.copy(name = v) }
    fun setType(v: String) = update { it.copy(type = v) }
    fun setCurrency(v: String) = update { it.copy(currency = v) }
    fun setColor(v: String) = update { it.copy(color = v) }
    fun setIncludeInNetWorth(v: Boolean) = update { it.copy(includeInNetWorth = v) }
    fun setAllowNegative(v: Boolean) = update { it.copy(allowNegativeOverride = v) }
    fun setOpeningBalance(v: String) = update { it.copy(openingBalance = v) }
    fun setCreditLimit(v: String) = update { it.copy(creditLimit = v) }
    fun setDueAmount(v: String) = update { it.copy(dueAmount = v) }

    /** Web strips non-digits and caps the field at two characters. */
    fun setStatementDay(v: String) = update { it.copy(statementDay = v.filter(Char::isDigit).take(2)) }
    fun setDueDay(v: String) = update { it.copy(dueDay = v.filter(Char::isDigit).take(2)) }

    private fun update(f: (CreateAccountUiState) -> CreateAccountUiState) {
        _uiState.value = f(_uiState.value)
    }

    /** Matches accounts/new/page.tsx's save(): create the account, clear the
     * net-worth flag if the box was cleared, then take the card branch or the
     * ordinary opening-balance branch. */
    fun save() {
        val s = _uiState.value
        val userId = authRepository.currentUserId.value ?: return
        if (s.name.isBlank() || s.saving) return
        update { it.copy(saving = true) }
        viewModelScope.launch {
            try {
                val accountId = ledgerRepository.createAccount(
                    userId = userId,
                    name = s.name.trim(),
                    type = s.type,
                    currency = s.currency,
                    color = s.color,
                    allowNegative = s.allowNegativeEffective,
                )
                // Web creates the row, then UPDATEs the flag off if the box was
                // cleared (`accounts/new/page.tsx`) -- the INSERT deliberately
                // omits the column so it keeps its read-side default. The
                // checkbox was drawn and its value never read: an account
                // excluded from net worth at creation was included anyway.
                if (!s.includeInNetWorth) {
                    ledgerRepository.updateAccount(accountId, mapOf("include_in_net_worth" to 0L))
                }
                if (s.isCard) {
                    saveCard(userId, accountId, s)
                } else {
                    val opening = jsParseFloat(s.openingBalance)
                    if (opening != null && opening != 0.0) {
                        ledgerRepository.setOpeningBalance(
                            userId = userId,
                            accountId = accountId,
                            balance = fromMajor(opening, s.currency),
                            occurredAt = Instant.now().toString(),
                        )
                    }
                }
                update { it.copy(saving = false, savedAccountId = accountId, savedType = s.type) }
            } catch (e: Exception) {
                e.printStackTrace()
                update { it.copy(saving = false) }
            }
        }
    }

    /**
     * The credit-card branch of web's save().
     *
     * Three writes, in web's order and for web's reasons:
     *
     * 1. **The balance is stored NEGATIVE.** A card's "balance" is what you
     *    owe, and the ledger stores what the account holds -- so an owed amount
     *    is a negative opening balance. Getting this sign wrong would make a
     *    debt read as savings in net worth.
     * 2. **The details row**, with both days clamped to 1..28 so the due date
     *    is a date that exists in February.
     * 3. **The cycle**, only when something is owed. `pending_due` is stored
     *    whatever the cycle says; the roll-forward is expressed by the DATE,
     *    not by a zero -- which is why `thisCycle` drives only the preview
     *    sentence and never the amount.
     */
    private suspend fun saveCard(userId: String, accountId: String, s: CreateAccountUiState) {
        val statementDay = clampCardDay(s.statementDay, 1)
        val dueDay = clampCardDay(s.dueDay, 20)
        val owed = jsParseFloat(s.dueAmount) ?: 0.0
        if (owed != 0.0) {
            ledgerRepository.setOpeningBalance(
                userId = userId,
                accountId = accountId,
                balance = fromMajor(-owed, s.currency),
                occurredAt = Instant.now().toString(),
            )
        }
        val limit = jsParseFloat(s.creditLimit) ?: 0.0
        creditCardRepository.upsertDetails(
            userId = userId,
            details = CreditCardDetails(
                accountId = accountId,
                statementDay = statementDay,
                dueDay = dueDay,
                // Web writes 0 rather than null for a blank limit, and the
                // Cards screen reads 0 as "no limit set" -- keep both halves.
                creditLimit = if (limit != 0.0) fromMajor(limit, s.currency).amount else 0L,
                cardLast4 = null,
                pendingDue = null,
                dueOn = null,
            ),
        )
        if (owed != 0.0) {
            val due = cardDueDate(LocalDate.now().toString(), statementDay, dueDay)
            creditCardRepository.setCycleDetails(
                accountId = accountId,
                pendingDue = fromMajor(owed, s.currency).amount,
                dueOnIso = due.dueOn,
            )
        }
    }
}
