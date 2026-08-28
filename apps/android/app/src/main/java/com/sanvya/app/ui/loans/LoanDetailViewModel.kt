package com.sanvya.app.ui.loans

import com.sanvya.app.domain.finance.emiDescription
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.EditLoanInput
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.Loan
import com.sanvya.app.data.repository.LoansRepository
import com.sanvya.app.domain.finance.amortizationSchedule
import com.sanvya.app.domain.finance.effectivePaidEmis
import com.sanvya.app.domain.finance.emiDueDate
import com.sanvya.app.domain.finance.emiFromPrincipal
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.money.money
import com.sanvya.app.ui.budgets.utcToLocalTime
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import com.sanvya.app.ui.formatMoney
import com.sanvya.app.ui.baseCurrencyNow

enum class EmiRowState { PAID, AUTO_MARKED, DUE }

data class EmiRowUiModel(
    val month: Int,
    val amountFormatted: String,
    val hasAmount: Boolean,
    /** Minor-unit EMI amount for this row (0 for an unset variable month) --
     * used to post the mark-paid expense transaction. */
    val emiMinor: Long,
    val state: EmiRowState,
    val dueFormatted: String,
    val paidOnOrDueFormatted: String,
    // fixed-rate only:
    val principalFormatted: String? = null,
    val interestFormatted: String? = null,
    val balanceFormatted: String? = null,
    val hasInterest: Boolean = false,
    // variable-rate only:
    val rawAmountMajor: String = "",
)

data class MarkPaidAccountOption(val id: String, val name: String, val balanceFormatted: String, val isCreditCard: Boolean)

data class LoanDetailUiModel(
    val id: String,
    val lender: String,
    val principalFormatted: String,
    val emiFormatted: String,
    val interestRateText: String,
    val emisPaidText: String,
    val nextEmiDueFormatted: String,
    val remainingText: String,
    val isVariable: Boolean,
    val hasInterest: Boolean,
    val totalInterestFormatted: String?,
    val variablePaidFormatted: String?,
    val progress: Double,
    val hasTenure: Boolean,
    val autoMarkPaid: Boolean,
    val autoMarkDueDayText: String,
    val rows: List<EmiRowUiModel>,
    val emptyScheduleHint: Boolean,
    // raw fields for edit prefill
    val rawLender: String,
    val rawPrincipalMajor: String,
    val rawEmiMajor: String,
    val rawInterestRate: String,
    val rawTenure: String,
    val rawStartDate: String,
    val rawDueDay: String,
    val rawRateType: String,
    val rawAlertTimeLocal: String,
    val currency: String,
)

/**
 * Loan detail (EMI schedule, mark-paid, auto-mark, edit/delete). Ported
 * from apps/web/app/loans/[id]/page.tsx per docs/mobile/screen-specs/
 * loans.md (task #27). New file -- Android had no per-loan detail screen
 * at all before this pass.
 */
class LoanDetailViewModel : ViewModel(), KoinComponent {
    private val loansRepository: LoansRepository by inject()
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _uiModel = MutableStateFlow<LoanDetailUiModel?>(null)
    val uiModel: StateFlow<LoanDetailUiModel?> = _uiModel

    private val _markPaidAccounts = MutableStateFlow<List<MarkPaidAccountOption>>(emptyList())
    val markPaidAccounts: StateFlow<List<MarkPaidAccountOption>> = _markPaidAccounts

    private val _defaultFundingAccountId = MutableStateFlow<String?>(null)
    val defaultFundingAccountId: StateFlow<String?> = _defaultFundingAccountId

    private var latestLoan: Loan? = null
    private val _selectedId = MutableStateFlow<String?>(null)
    private var observing = false

    /** Compose's default `viewModel()` factory takes no constructor args,
     * so (matching this codebase's established Budgets/Goals convention
     * of resolving an edit target by id rather than a custom
     * `ViewModelProvider.Factory`) this is a plain parameterless
     * `KoinComponent` ViewModel that (re)subscribes to whichever loan id
     * the screen selects, via `flatMapLatest` on `_selectedId`. */
    fun select(id: String) {
        _selectedId.value = id
        if (observing) return
        observing = true
        viewModelScope.launch {
            combine(
                _selectedId.flatMapLatest { sid -> if (sid == null) flowOf<Loan?>(null) else loansRepository.watchLoan(sid) },
                ledgerRepository.watchAccountBalances(),
            ) { loan, balances ->
                latestLoan = loan
                _defaultFundingAccountId.value = loan?.fundingAccountId
                _markPaidAccounts.value = balances.map {
                    MarkPaidAccountOption(it.account.id, it.account.name, formatMoney(it.balance.amount, it.account.currency), it.account.type == "credit_card")
                }
                _uiModel.value = loan?.let { buildUiModel(it) }
            }.collect {}
        }
    }

    private fun buildUiModel(l: Loan): LoanDetailUiModel {
        val cur = l.currency.ifBlank { baseCurrencyNow() }
        val tenure = l.tenureMonths ?: 0
        val emi = l.emiAmount ?: 0L
        val dueDay = l.emiDueDay
        val autoMark = l.autoMarkPaid
        val isVariable = l.rateType == "variable"
        val schedule = if (!isVariable && emi > 0) amortizationSchedule(l.principal, l.interestRate ?: 0.0, emi, if (tenure > 0) tenure else 600) else emptyList()
        val totalInterest = schedule.sumOf { it.interest }
        val hasInterest = (l.interestRate ?: 0.0) > 0

        var manual = parseManualPaid(l.emiPayments)
        if (manual.isEmpty() && (l.emisPaid ?: 0) > 0) manual = (1..(l.emisPaid ?: 0)).toList()
        val amounts = parseAmounts(l.emiAmounts)

        val knownMax = maxOf(0, (amounts.keys + manual).maxOrNull() ?: 0)
        val totalEmis = if (tenure > 0) tenure else if (isVariable) knownMax else schedule.size
        val variableMonths = if (isVariable) (1..maxOf(totalEmis, knownMax, 1)).toList() else emptyList()

        val today = LocalDate.now().toString()
        val effective = effectivePaidEmis(manual, totalEmis, autoMark, l.startDate, dueDay, today)
        val manualSet = manual.toSet()
        val monthsList = if (isVariable) variableMonths else schedule.map { it.month }
        val nextUnpaid = monthsList.firstOrNull { it !in effective }
        val nextEmiDue = nextUnpaid?.let { emiDueDate(l.startDate, dueDay, it) }
        val remaining = if (totalEmis > 0) maxOf(0, totalEmis - effective.size) else null
        val paidOnMap = parsePaidOnMap(l.emiPayments)
        val variablePaidTotal = variableMonths.filter { it in effective }.sumOf { amounts[it] ?: 0L }

        val rows = if (isVariable) {
            variableMonths.map { m ->
                val paid = m in effective
                val due = emiDueDate(l.startDate, dueDay, m)
                EmiRowUiModel(
                    month = m, amountFormatted = amounts[m]?.let { formatMoney(it, cur) } ?: "—", hasAmount = amounts[m] != null,
                    emiMinor = amounts[m] ?: 0L,
                    state = if (paid && m !in manualSet) EmiRowState.AUTO_MARKED else if (paid) EmiRowState.PAID else EmiRowState.DUE,
                    dueFormatted = fmtDateShort(due),
                    paidOnOrDueFormatted = if (paid) fmtDateShort(paidOnMap[m] ?: due) else fmtDateShort(due),
                    rawAmountMajor = amounts[m]?.let { formatMajorPlain(it, cur) } ?: "",
                )
            }
        } else {
            schedule.map { r ->
                val paid = r.month in effective
                val due = emiDueDate(l.startDate, dueDay, r.month)
                EmiRowUiModel(
                    month = r.month, amountFormatted = formatMoney(r.emi, cur), hasAmount = true,
                    emiMinor = r.emi,
                    state = if (paid && r.month !in manualSet) EmiRowState.AUTO_MARKED else if (paid) EmiRowState.PAID else EmiRowState.DUE,
                    dueFormatted = fmtDateShort(due),
                    paidOnOrDueFormatted = if (paid) fmtDateShort(paidOnMap[r.month] ?: due) else fmtDateShort(due),
                    principalFormatted = formatMoney(r.principal, cur),
                    interestFormatted = if (hasInterest) formatMoney(r.interest, cur) else null,
                    balanceFormatted = if (!hasInterest) formatMoney(r.balance, cur) else null,
                    hasInterest = hasInterest,
                )
            }
        }

        return LoanDetailUiModel(
            id = l.id,
            lender = l.lender?.takeIf { it.isNotBlank() } ?: "Loan",
            principalFormatted = formatMoney(l.principal, cur),
            emiFormatted = if (isVariable) "Varies" else if (emi > 0) formatMoney(emi, cur) else "—",
            interestRateText = if (hasInterest) "${l.interestRate}% p.a.${if (isVariable) " (variable)" else ""}" else if (isVariable) "Variable" else "—",
            emisPaidText = if (tenure > 0) "${effective.size} / $tenure" else "${effective.size}",
            nextEmiDueFormatted = if (nextEmiDue != null && remaining != 0) fmtDateLong(nextEmiDue) else "—",
            remainingText = remaining?.let { "$it EMI${if (it == 1) "" else "s"} left" } ?: "—",
            isVariable = isVariable,
            hasInterest = hasInterest,
            totalInterestFormatted = if (!isVariable && hasInterest) formatMoney(totalInterest, cur) else null,
            variablePaidFormatted = if (isVariable) formatMoney(variablePaidTotal, cur) else null,
            progress = if (tenure > 0) (effective.size.toDouble() / tenure.toDouble()).coerceIn(0.0, 1.0) else 0.0,
            hasTenure = tenure > 0,
            autoMarkPaid = autoMark,
            autoMarkDueDayText = (dueDay ?: l.startDate?.let { runCatching { LocalDate.parse(it.take(10)).dayOfMonth }.getOrNull() })?.let { "Due on the ${ordinal(it)} each month" } ?: "",
            rows = rows,
            emptyScheduleHint = !isVariable && schedule.isEmpty(),
            rawLender = l.lender ?: "",
            rawPrincipalMajor = formatMajorPlain(l.principal, l.currency),
            rawEmiMajor = l.emiAmount?.let { formatMajorPlain(it, l.currency) } ?: "",
            rawInterestRate = l.interestRate?.let { if (it == Math.floor(it)) it.toLong().toString() else it.toString() } ?: "",
            rawTenure = l.tenureMonths?.toString() ?: "",
            rawStartDate = l.startDate ?: "",
            rawDueDay = l.emiDueDay?.toString() ?: "",
            rawRateType = l.rateType ?: "fixed",
            rawAlertTimeLocal = utcToLocalTime(l.alertTimeUtc),
            currency = cur,
        )
    }

    /** Matches web's `setManualPaid(month, paidOn)`. */
    fun markPaid(month: Int, paidOn: String, accountId: String?, emiAmountMinor: Long, currency: String) {
        viewModelScope.launch {
            val l = latestLoan ?: return@launch
            val manual = parsePaidOnMap(l.emiPayments).toMutableMap()
            manual[month] = paidOn
            val json = JSONObject().apply { manual.forEach { (k, v) -> put(k.toString(), v) } }.toString()
            loansRepository.setManualPaid(l.id, json, manual.size)
            if (accountId != null && emiAmountMinor > 0) {
                val userId = authRepository.currentUserId.value
                if (userId != null) {
                    val occurredAt = "${paidOn}T12:00:00.000Z"
                    ledgerRepository.createTransaction(
                        userId = userId, accountId = accountId, type = "expense",
                        amount = money(emiAmountMinor, currency), occurredAt = occurredAt,
                        // emiDescription(), not a literal: this string is the
                        // cross-device dedupe key loan auto-post matches on.
                        description = emiDescription(month, l.lender),
                    )
                }
                loansRepository.setFundingAccountId(l.id, accountId)
            }
        }
    }

    /** Matches web's `setManualPaid(month, null)` (undo). */
    fun unmarkPaid(month: Int) {
        viewModelScope.launch {
            val l = latestLoan ?: return@launch
            val manual = parsePaidOnMap(l.emiPayments).toMutableMap()
            manual.remove(month)
            val json = JSONObject().apply { manual.forEach { (k, v) -> put(k.toString(), v) } }.toString()
            loansRepository.setManualPaid(l.id, json, manual.size)
        }
    }

    /** Matches web's `setAmount(month, minor)` (variable-rate EMI entry). */
    fun setVariableAmount(month: Int, majorText: String, currency: String) {
        viewModelScope.launch {
            val l = latestLoan ?: return@launch
            val amounts = parseAmounts(l.emiAmounts).toMutableMap()
            val minor = majorText.toDoubleOrNull()?.let { fromMajor(it, currency).amount }
            if (minor == null || minor <= 0) amounts.remove(month) else amounts[month] = minor
            val json = JSONObject().apply { amounts.forEach { (k, v) -> put(k.toString(), v) } }.toString()
            loansRepository.setEmiAmounts(l.id, json)
        }
    }

    fun toggleAutoMark() {
        viewModelScope.launch {
            val l = latestLoan ?: return@launch
            loansRepository.setAutoMarkPaid(l.id, !l.autoMarkPaid)
        }
    }

    /** Matches web's `EditLoan.save()`. */
    suspend fun update(
        lender: String, principalMajorText: String, emiMajorText: String, interestRateText: String,
        tenureText: String, startDate: String, dueDayText: String, rateType: String, alertTimeUtc: String,
    ): String? {
        val l = latestLoan ?: return "Loan not found."
        val cur = l.currency.ifBlank { baseCurrencyNow() }
        return try {
            val principalMinor = fromMajor(principalMajorText.toDoubleOrNull() ?: 0.0, cur).amount
            val isVariable = rateType == "variable"
            val rate = interestRateText.toDoubleOrNull() ?: 0.0
            val tenure = tenureText.toIntOrNull()
            val computedEmi = if (!isVariable) emiFromPrincipal(principalMinor, rate, tenure ?: 0) else 0L
            val emiToUse = if (isVariable) null else (emiMajorText.toDoubleOrNull()?.let { fromMajor(it, cur).amount } ?: computedEmi.takeIf { it > 0 })
            val dueDay = dueDayText.toIntOrNull()?.coerceIn(1, 31)
            loansRepository.update(
                l.id,
                EditLoanInput(
                    lender = lender.trim().ifBlank { null }, principal = principalMinor, emiAmount = emiToUse,
                    interestRate = rate, tenureMonths = tenure, startDate = startDate.ifBlank { null },
                    emiDueDay = dueDay, rateType = rateType, alertTimeUtc = alertTimeUtc,
                ),
            )
            null
        } catch (e: Exception) {
            "Couldn't save changes: ${e.message}"
        }
    }

    fun delete(onDone: () -> Unit) {
        viewModelScope.launch {
            val id = latestLoan?.id ?: return@launch
            try {
                loansRepository.delete(id)
                onDone()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}

private fun parsePaidOnMap(json: String?): Map<Int, String> {
    if (json.isNullOrBlank()) return emptyMap()
    return try {
        val obj = JSONObject(json)
        val out = mutableMapOf<Int, String>()
        obj.keys().forEach { k ->
            val v = obj.optString(k)
            val n = k.toIntOrNull()
            if (n != null && v.isNotBlank()) out[n] = v
        }
        out
    } catch (e: Exception) {
        emptyMap()
    }
}

private fun parseAmounts(json: String?): Map<Int, Long> {
    if (json.isNullOrBlank()) return emptyMap()
    return try {
        val obj = JSONObject(json)
        val out = mutableMapOf<Int, Long>()
        obj.keys().forEach { k ->
            val v = obj.optLong(k, -1)
            val n = k.toIntOrNull()
            if (n != null && v > 0) out[n] = v
        }
        out
    } catch (e: Exception) {
        emptyMap()
    }
}

private fun fmtDateShort(iso: String?): String = try {
    if (iso == null) "—" else LocalDate.parse(iso.take(10)).format(DateTimeFormatter.ofPattern("d MMM", Locale.ENGLISH))
} catch (e: Exception) {
    "—"
}

private fun fmtDateLong(iso: String?): String = try {
    if (iso == null) "—" else LocalDate.parse(iso.take(10)).format(DateTimeFormatter.ofPattern("d MMM yyyy", Locale.ENGLISH))
} catch (e: Exception) {
    "—"
}

/** 1 -> "1st", 2 -> "2nd", ... day-of-month ordinal -- matches web's ordinal(). */
private fun ordinal(n: Int): String {
    val v = n % 100
    val suffix = when {
        v in 11..13 -> "th"
        v % 10 == 1 -> "st"
        v % 10 == 2 -> "nd"
        v % 10 == 3 -> "rd"
        else -> "th"
    }
    return "$n$suffix"
}
