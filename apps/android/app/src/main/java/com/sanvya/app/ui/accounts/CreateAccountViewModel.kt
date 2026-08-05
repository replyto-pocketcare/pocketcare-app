package com.sanvya.app.ui.accounts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.domain.money.fromMajor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.Instant

/** The 7 apps/web AccountType values (packages/types/src/index.ts), regular-
 * account path only per docs/mobile/screen-specs/accounts.md scope (credit
 * card / demat specifics deferred to those screens). */
val ACCOUNT_TYPES = listOf("savings", "current", "credit_card", "cash", "mutual_funds", "stocks", "demat")
val ACCOUNT_CURRENCIES = listOf("INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED")

data class CreateAccountUiState(
    val name: String = "",
    val type: String = "savings",
    val currency: String = "INR",
    val color: String = ACCOUNT_COLOR_HEX.first(),
    val includeInNetWorth: Boolean = true,
    /** null = "follow type default" (matches web's `allowNeg: Boolean | null`
     * exactly -- accounts/new/page.tsx's `allowNegEffective = allowNeg ?? isCard`).
     * Not modeled as a plain Boolean: that would lose the "user hasn't
     * touched this yet" state and make the toggle silently stop following
     * the type when the user picks a different account type. */
    val allowNegativeOverride: Boolean? = null,
    val openingBalance: String = "",
    val saving: Boolean = false,
    val savedAccountId: String? = null,
) {
    val allowNegativeEffective: Boolean get() = allowNegativeOverride ?: (type == "credit_card")
}

/** ACCOUNT_COLORS as hex strings for the color-swatch picker (the Compose
 * Color palette in ui/AccountColors.kt is ARGB Int, this screen needs to
 * persist a "#RRGGBB" string to account.color, matching what
 * apps/web/src/colors.ts's ACCOUNT_COLORS actually stores). */
val ACCOUNT_COLOR_HEX = listOf(
    "#3E4A38", "#5F6647", "#6B7A4F", "#9CAE8E", "#B06A4F", "#C98A72",
    "#A8503A", "#7C4A3A", "#5F4636", "#C9B79C", "#C08A3E", "#4F46E5",
    "#6D5ACF", "#3F5A8A", "#2F6F6A", "#7A4A6B", "#4B5563", "#2B2723",
)

class CreateAccountViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _uiState = MutableStateFlow(CreateAccountUiState())
    val uiState: StateFlow<CreateAccountUiState> = _uiState.asStateFlow()

    fun setName(v: String) = update { it.copy(name = v) }
    fun setType(v: String) = update { it.copy(type = v) }
    fun setCurrency(v: String) = update { it.copy(currency = v) }
    fun setColor(v: String) = update { it.copy(color = v) }
    fun setIncludeInNetWorth(v: Boolean) = update { it.copy(includeInNetWorth = v) }
    fun setAllowNegative(v: Boolean) = update { it.copy(allowNegativeOverride = v) }
    fun setOpeningBalance(v: String) = update { it.copy(openingBalance = v) }

    private fun update(f: (CreateAccountUiState) -> CreateAccountUiState) {
        _uiState.value = f(_uiState.value)
    }

    /** Matches accounts/new/page.tsx's save() for the regular-account path:
     * create, then setOpeningBalance if non-zero. Card/demat branches
     * deferred (see spec). */
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
                val opening = s.openingBalance.toDoubleOrNull()
                if (opening != null && opening != 0.0) {
                    ledgerRepository.setOpeningBalance(
                        userId = userId,
                        accountId = accountId,
                        balance = fromMajor(opening, s.currency),
                        occurredAt = Instant.now().toString(),
                    )
                }
                update { it.copy(saving = false, savedAccountId = accountId) }
            } catch (e: Exception) {
                e.printStackTrace()
                update { it.copy(saving = false) }
            }
        }
    }
}
