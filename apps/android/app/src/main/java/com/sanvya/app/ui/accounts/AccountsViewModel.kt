package com.sanvya.app.ui.accounts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.AccountWithBalance
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.SettingsRepository
import com.sanvya.app.ui.components.initialSyncPending
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import com.sanvya.app.domain.money.convert
import com.sanvya.app.domain.money.money
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.formatMoneyAware
import kotlin.math.roundToInt

data class AccountUiModel(
    val id: String,
    val name: String,
    val type: String,
    val currency: String,
    val color: String?,
    val balance: String,
    val isArchived: Boolean = false,
    val allowNegative: Boolean = false,
    val includeInNetWorth: Boolean = true
)

/**
 * One currency's share of net worth -- a row of the "Across currencies" card.
 *
 * `native` is the total in the currency the accounts are actually held in;
 * `base` is that value converted to the user's base currency, which is the only
 * thing the shares can be computed against.
 */
data class CurrencySliceUiModel(
    val currency: String,
    val nativeFormatted: String,
    val baseFormatted: String,
    /** No "≈ base" line is drawn for the base currency itself -- it would
     * restate the amount already shown. Matches web. */
    val isBase: Boolean,
    /** Share of the total, already rounded for display (web's `toFixed(0)`). */
    val sharePct: Int,
    /** Share as a bar width. Clamped at zero because a net-negative currency
     * (a card-only currency, say) would otherwise ask the bar for a negative
     * width. Web clamps the same way, and only for the bar. */
    val barSharePct: Float,
)

/** "Across currencies" -- where the money is held, converted to base. Null for
 * the single-currency case, which web renders as nothing at all. */
data class CurrencyBreakdownUiModel(
    val base: String,
    val slices: List<CurrencySliceUiModel>,
    val totalFormatted: String,
)

data class AccountsUiState(
    val visible: List<AccountUiModel> = emptyList(),
    val archivedCount: Int = 0,
    val showArchived: Boolean = false,
    /** Null until there is more than one currency to compare. */
    val breakdown: CurrencyBreakdownUiModel? = null,
    /**
     * False on the seed value only. Web's `useAccountsLoading()` exists for the
     * same reason: a list of no accounts that has not been read yet is not a
     * list of no accounts.
     */
    val loaded: Boolean = false,
)

/** No-arg + KoinComponent, matches DashboardViewModel/SettingsViewModel's
 * established pattern (docs/mobile/screen-specs/dashboard.md's "no Koin
 * viewModel-DSL module needed" note). */
class AccountsViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val settingsRepository: SettingsRepository by inject()

    private val showArchived = MutableStateFlow(false)

    fun toggleShowArchived() {
        showArchived.value = !showArchived.value
    }

    val uiState: StateFlow<AccountsUiState> = combine(
        ledgerRepository.watchAccountBalances(includeArchived = true),
        showArchived,
        ledgerRepository.watchRates(),
    ) { balances, showArch, rates ->
        val all = balances.map { acctWithBal ->
            val acct = acctWithBal.account
            AccountUiModel(
                id = acct.id,
                name = acct.name,
                type = acct.type,
                currency = acct.currency,
                color = acct.color,
                balance = formatMoneyAware(acctWithBal.balance),
                isArchived = acct.isArchived,
                allowNegative = acct.allowNegative,
                includeInNetWorth = acct.includeInNetWorth,
            )
        }
        val archivedCount = all.count { it.isArchived }
        val visible = if (showArch) all else all.filterNot { it.isArchived }
        AccountsUiState(
            visible = visible,
            archivedCount = archivedCount,
            showArchived = showArch,
            breakdown = currencyBreakdown(balances, rates),
            loaded = true,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = AccountsUiState(),
    )

    /**
     * Show card skeletons rather than "no accounts yet".
     *
     * Web's guard is `balances.length === 0 && (accountsLoading || syncPending)`.
     * The half that matters is `syncPending`: on a returning user's first
     * launch the local database is empty because the accounts are still
     * downloading, and this screen told them they had none -- which for an
     * accounts list reads as "your money is gone", not as "still loading".
     */
    val showSkeleton: StateFlow<Boolean> = combine(
        uiState,
        initialSyncPending(settingsRepository),
    ) { state, syncPending ->
        !state.loaded || syncPending
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    /**
     * Net worth split by the currency each account is held in -- the port of
     * web's `useCurrencyBreakdown()` (apps/web/src/hooks.ts).
     *
     * Two filters, both copied from web rather than invented: archived accounts
     * are out because web builds this from `useAccountBalances()` with its
     * default (non-archived) argument, and accounts excluded from net worth are
     * out because the card is a breakdown OF net worth. This screen's own list
     * shows archived accounts on request; this card deliberately does not
     * follow it.
     *
     * Returns null below two currencies: a single-currency user has nothing to
     * compare, and web renders the section as nothing at all in that case.
     */
    private fun currencyBreakdown(
        balances: List<AccountWithBalance>,
        rates: (String, String) -> Double,
    ): CurrencyBreakdownUiModel? {
        val base = baseCurrencyNow()
        val byCurrency = LinkedHashMap<String, Long>()
        for (ab in balances) {
            if (ab.account.isArchived || !ab.account.includeInNetWorth) continue
            val currency = ab.balance.currency
            byCurrency[currency] = (byCurrency[currency] ?: 0L) + ab.balance.amount
        }
        if (byCurrency.size < 2) return null

        // `convert(money(...), base, rate)`, never a bare multiply: the two
        // currencies can have different minor-unit scales (JPY 0, KWD 3), and
        // the domain helper is what knows that.
        val converted = byCurrency.entries
            .map { (currency, native) ->
                // `runCatching`: `convert` rejects a non-positive rate, and a
                // zero in `exchange_rates` would otherwise take the whole
                // accounts list down. Falling back to par is what the rate
                // lookup itself does for an unknown pair.
                val inBase = if (currency == base) {
                    native
                } else {
                    runCatching { convert(money(native, currency), base, rates(currency, base)).amount }.getOrDefault(native)
                }
                Triple(currency, native, inBase)
            }
            .sortedByDescending { kotlin.math.abs(it.third) }
        val total = converted.sumOf { it.third }
        // The BAR divides by the sum of absolute values, not by the signed
        // total. Web divides by the signed one, and on a net-negative sheet --
        // or with one overdrawn currency against two positive ones -- that
        // yields negative shares and shares over 100%, which paint a segment
        // wider than the bar it sits in. Percentages of "how much of my money
        // is here" only mean anything against a magnitude.
        val magnitude = converted.sumOf { kotlin.math.abs(it.third) }

        return CurrencyBreakdownUiModel(
            base = base,
            totalFormatted = formatMoney(total, base),
            slices = converted.map { (currency, native, inBase) ->
                val share = if (magnitude != 0L) (kotlin.math.abs(inBase).toDouble() / magnitude.toDouble()) * 100.0 else 0.0
                CurrencySliceUiModel(
                    currency = currency,
                    nativeFormatted = formatMoney(native, currency),
                    baseFormatted = formatMoney(inBase, base),
                    isBase = currency == base,
                    sharePct = share.roundToInt(),
                    barSharePct = share.coerceIn(0.0, 100.0).toFloat(),
                )
            },
        )
    }

    /** Matches accounts/page.tsx's toggleNw() exactly (direct SQL update, no
     * confirmation). Boolean columns are stored as INTEGER 0/1 -- pass Long,
     * not a raw Kotlin Boolean, matching setAccountArchived()'s existing
     * convention in LedgerRepository.kt (accountMapper reads it back via
     * getBooleanOptional). */
    fun toggleIncludeInNetWorth(id: String, current: Boolean) {
        viewModelScope.launch {
            ledgerRepository.updateAccount(id, mapOf("include_in_net_worth" to if (!current) 1L else 0L))
        }
    }

    fun setArchived(id: String, archived: Boolean) {
        viewModelScope.launch {
            ledgerRepository.setAccountArchived(id, archived)
        }
    }
}
