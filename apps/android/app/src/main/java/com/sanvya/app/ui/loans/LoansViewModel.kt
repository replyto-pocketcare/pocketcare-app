package com.sanvya.app.ui.loans

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.Loan
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.LoansRepository
import com.sanvya.app.data.repository.NewLoanInput
import com.sanvya.app.domain.finance.effectivePaidEmis
import com.sanvya.app.domain.money.convert
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.money.toMajor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.text.NumberFormat
import java.time.LocalDate
import java.util.Currency
import java.util.Locale

/** Base/display currency -- loans are always created in the base currency
 * (matches web: `AddLoan` inserts with `currency: base`, no per-loan
 * currency picker exists). Hardcoded "INR" matching Dashboard/
 * Investments' own established simplification. */
private const val BASE_CURRENCY = "INR"

private val NON_INVESTMENT_TYPES = setOf("stocks", "mutual_funds", "demat")

data class FundingAccountOption(val id: String, val name: String, val isCreditCard: Boolean)

data class LoanUiModel(
    val id: String,
    val lender: String,
    val active: Boolean,
    val rangeOrRate: String,
    val paidCountText: String,
    val progress: Double, // 0..1, or 0 if no tenure
    val hasTenure: Boolean,
    val principalFormatted: String,
    val emiFormatted: String,
)

/**
 * Ported from apps/web/app/loans/page.tsx per docs/mobile/screen-specs/
 * loans.md (task #27). Was read-only (watchLoans() only, constructor-
 * injected dead code, no consuming Screen, no nav route -- same
 * "reported DONE, actually never real" pattern as Budgets/Goals/
 * Investments' old ViewModels) before this pass (2026-08-06); replaced
 * with a real KoinComponent/by-inject() one, removed the now-superseded
 * LoanUiModel from ui/UiModels.kt.
 */
class LoansViewModel : ViewModel(), KoinComponent {
    private val loansRepository: LoansRepository by inject()
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _loans = MutableStateFlow<List<LoanUiModel>>(emptyList())
    val loans: StateFlow<List<LoanUiModel>> = _loans

    private val _totalEmiFormatted = MutableStateFlow(formatMoney(0L))
    val totalEmiFormatted: StateFlow<String> = _totalEmiFormatted

    private val _fundingAccounts = MutableStateFlow<List<FundingAccountOption>>(emptyList())
    val fundingAccounts: StateFlow<List<FundingAccountOption>> = _fundingAccounts

    init {
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value ?: return@launch
            combine(
                loansRepository.watchLoans(userId),
                ledgerRepository.watchAccounts(),
                ledgerRepository.watchRates(),
            ) { loans, accounts, rates -> Triple(loans, accounts, rates) }.collect { (loans, accounts, rates) ->
                _fundingAccounts.value = accounts
                    .filter { it.type !in NON_INVESTMENT_TYPES }
                    .sortedByDescending { it.type == "credit_card" }
                    .map { FundingAccountOption(it.id, it.name, it.type == "credit_card") }

                val today = LocalDate.now().toString()
                var totalEmiBase = 0L
                val uis = loans.map { l ->
                    val tenure = l.tenureMonths ?: 0
                    val paid = paidCount(l, today)
                    val remaining = if (tenure > 0) maxOf(0, tenure - paid) else null
                    val closed = tenure > 0 && remaining == 0
                    val range = loanRange(l.startDate, tenure)
                    val cur = l.currency.ifBlank { BASE_CURRENCY }
                    if (l.emiAmount != null) {
                        totalEmiBase += if (cur == BASE_CURRENCY) l.emiAmount else convert(money(l.emiAmount, cur), BASE_CURRENCY, rates(cur, BASE_CURRENCY)).amount
                    }
                    LoanUiModel(
                        id = l.id,
                        lender = l.lender?.takeIf { it.isNotBlank() } ?: "Loan",
                        active = !closed,
                        rangeOrRate = range ?: (l.interestRate?.let { "${it}% p.a." } ?: "—"),
                        paidCountText = if (tenure > 0) "$paid / $tenure paid" else "$paid paid",
                        progress = if (tenure > 0) (paid.toDouble() / tenure.toDouble()).coerceIn(0.0, 1.0) else 0.0,
                        hasTenure = tenure > 0,
                        principalFormatted = formatMoney(l.principal, cur),
                        emiFormatted = l.emiAmount?.let { formatMoney(it, cur) } ?: (if (l.rateType == "variable") "Varies" else "—"),
                    )
                }
                _loans.value = uis
                _totalEmiFormatted.value = formatMoney(totalEmiBase)
            }
        }
    }

    /** Matches web's `AddLoan.save()`: requires a lender name or a
     * principal; EMI is caller-supplied (auto-calculated by the screen
     * for fixed-rate loans via `emiFromPrincipal`, null for variable). */
    suspend fun create(
        lender: String, principalMajorText: String, emiMajorText: String?, interestRateText: String,
        tenureText: String, startDate: String?, dueDayText: String, autoMarkPaid: Boolean, rateType: String,
        fundingAccountId: String?, alertTimeUtc: String,
    ): String? {
        if (lender.trim().isEmpty() && principalMajorText.isBlank()) return "Enter a lender or a loan amount."
        val userId = authRepository.currentUserId.value ?: return "Couldn't determine the current user."
        return try {
            val principalMinor = fromMajor(principalMajorText.toDoubleOrNull() ?: 0.0, BASE_CURRENCY).amount
            val dueDay = dueDayText.toIntOrNull()?.coerceIn(1, 31)
            loansRepository.create(
                userId,
                NewLoanInput(
                    lender = lender.trim(), currency = BASE_CURRENCY, principal = principalMinor,
                    emiAmount = emiMajorText?.toDoubleOrNull()?.let { fromMajor(it, BASE_CURRENCY).amount },
                    interestRate = interestRateText.toDoubleOrNull() ?: 0.0,
                    tenureMonths = tenureText.toIntOrNull(), startDate = startDate, emiDueDay = dueDay,
                    autoMarkPaid = autoMarkPaid, rateType = rateType, fundingAccountId = fundingAccountId,
                    alertTimeUtc = alertTimeUtc,
                ),
            )
            null
        } catch (e: Exception) {
            "Couldn't add the loan: ${e.message}"
        }
    }
}

/** Effective paid-EMI count for a loan row (manual marks union auto-marked
 * past-due) -- matches web's page-local `paidCount()` exactly. */
internal fun paidCount(l: Loan, todayIso: String): Int {
    val tenure = l.tenureMonths ?: 0
    var manual = parseManualPaid(l.emiPayments)
    if (manual.isEmpty() && (l.emisPaid ?: 0) > 0) manual = (1..(l.emisPaid ?: 0)).toList()
    return effectivePaidEmis(manual, tenure, l.autoMarkPaid, l.startDate, l.emiDueDay, todayIso).size
}

/** Parses the `emi_payments` JSON map `{ "1": "2026-01-05", "2": "" }` into
 * the list of EMI numbers with a non-blank paid-on date. */
internal fun parseManualPaid(json: String?): List<Int> {
    if (json.isNullOrBlank()) return emptyList()
    return try {
        val obj = org.json.JSONObject(json)
        obj.keys().asSequence().filter { obj.optString(it).isNotBlank() }.mapNotNull { it.toIntOrNull() }.toList()
    } catch (e: Exception) {
        emptyList()
    }
}

/** "Mar '26 - Nov '26" from a start date + tenure in months -- matches
 * web's `loanRange()`. */
internal fun loanRange(startIso: String?, tenure: Int): String? {
    if (startIso.isNullOrBlank() || tenure <= 0) return null
    return try {
        val start = LocalDate.parse(startIso.take(10))
        val end = start.plusMonths(tenure.toLong())
        val fmt = java.time.format.DateTimeFormatter.ofPattern("MMM ''yy", Locale.ENGLISH)
        "${start.format(fmt)} – ${end.format(fmt)}"
    } catch (e: Exception) {
        null
    }
}

internal fun formatMoney(minor: Long, currency: String = "INR"): String = try {
    NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        this.currency = Currency.getInstance(currency)
        maximumFractionDigits = 0
    }.format(toMajor(money(minor, currency)))
} catch (e: Exception) {
    "$currency ${minor / 100.0}"
}
