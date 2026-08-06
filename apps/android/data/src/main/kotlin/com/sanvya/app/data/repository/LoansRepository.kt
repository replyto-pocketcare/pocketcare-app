package com.sanvya.app.data.repository

/**
 * Loans (EMI) repository -- P3.11/P3.16 (task #27), read/write. Mirrors
 * apps/web/app/loans/page.tsx's `AddLoan.save()` and [id]/page.tsx's
 * `setManualPaid`/`setAmount`/`toggleAutoMark`/`EditLoan.save()` exactly.
 * See docs/mobile/screen-specs/loans.md for the full source-verification
 * notes.
 *
 * Fixed this pass (2026-08-06): `tenure_months`/`emi_amount`/`start_date`/
 * `emis_paid`/`emi_due_day`/`rate_type` were all mapped as non-nullable
 * via non-optional cursor getters despite web's own `Loan` interface
 * treating every one of them as nullable (`tenure_months: number | null`,
 * etc.) -- a real crash risk, same bug class already found and fixed in
 * Budgets/Investments this engagement. Also added `emi_payments`/
 * `emi_amounts`/`funding_account_id`/`alert_time_utc`, which the schema
 * already had (PocketCareSchema.kt's `loans` TableDef, and
 * `alert_time_utc` specifically was added to this exact table in the
 * 2026-08-06 Budgets pass) but this repository's `Loan` data class was
 * missing entirely.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.SqlCursor
import com.powersync.db.getBooleanOptional
import com.powersync.db.getDoubleOptional
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

data class Loan(
    val id: String,
    val userId: String,
    val lender: String?,
    val principal: Long,
    val currency: String,
    val interestRate: Double?,
    val tenureMonths: Int?,
    val emiAmount: Long?,
    val startDate: String?,
    val emisPaid: Int?,
    val emiPayments: String?,
    val emiDueDay: Int?,
    val autoMarkPaid: Boolean,
    val rateType: String?,
    val emiAmounts: String?,
    val fundingAccountId: String?,
    val alertTimeUtc: String?,
)

data class NewLoanInput(
    val lender: String,
    val currency: String,
    val principal: Long,
    val emiAmount: Long?,
    val interestRate: Double,
    val tenureMonths: Int?,
    val startDate: String?,
    val emiDueDay: Int?,
    val autoMarkPaid: Boolean,
    val rateType: String,
    val fundingAccountId: String?,
    val alertTimeUtc: String,
)

data class EditLoanInput(
    val lender: String?,
    val principal: Long,
    val emiAmount: Long?,
    val interestRate: Double,
    val tenureMonths: Int?,
    val startDate: String?,
    val emiDueDay: Int?,
    val rateType: String,
    val alertTimeUtc: String,
)

class LoansRepository(private val db: PowerSyncDatabase) {

    private fun loanMapper(cursor: SqlCursor): Loan = Loan(
        id = cursor.getString("id"),
        userId = cursor.getString("user_id"),
        lender = cursor.getStringOptional("lender"),
        principal = cursor.getLongOptional("principal") ?: 0L,
        currency = cursor.getString("currency"),
        interestRate = cursor.getDoubleOptional("interest_rate"),
        tenureMonths = cursor.getLongOptional("tenure_months")?.toInt(),
        emiAmount = cursor.getLongOptional("emi_amount"),
        startDate = cursor.getStringOptional("start_date"),
        emisPaid = cursor.getLongOptional("emis_paid")?.toInt(),
        emiPayments = cursor.getStringOptional("emi_payments"),
        emiDueDay = cursor.getLongOptional("emi_due_day")?.toInt(),
        autoMarkPaid = cursor.getBooleanOptional("auto_mark_paid") ?: false,
        rateType = cursor.getStringOptional("rate_type"),
        emiAmounts = cursor.getStringOptional("emi_amounts"),
        fundingAccountId = cursor.getStringOptional("funding_account_id"),
        alertTimeUtc = cursor.getStringOptional("alert_time_utc"),
    )

    fun watchLoans(userId: String): Flow<List<Loan>> = db.watch(
        sql = "SELECT * FROM loans WHERE deleted_at IS NULL AND user_id = ? ORDER BY created_at",
        parameters = listOf(userId),
        mapper = ::loanMapper,
    )

    fun watchLoan(id: String): Flow<Loan?> = db.watch(
        sql = "SELECT * FROM loans WHERE id = ? AND deleted_at IS NULL",
        parameters = listOf(id),
        mapper = ::loanMapper,
    ).map { it.firstOrNull() }

    /** Matches web's `AddLoan.save()`: `emis_paid` starts at 0. */
    suspend fun create(userId: String, input: NewLoanInput): String = insertRow(
        db, "loans", userId,
        mapOf(
            "lender" to input.lender, "currency" to input.currency, "principal" to input.principal,
            "emi_amount" to input.emiAmount, "interest_rate" to input.interestRate,
            "tenure_months" to input.tenureMonths, "start_date" to input.startDate,
            "emi_due_day" to input.emiDueDay, "auto_mark_paid" to if (input.autoMarkPaid) 1L else 0L,
            "rate_type" to input.rateType, "funding_account_id" to input.fundingAccountId,
            "emis_paid" to 0L, "alert_time_utc" to input.alertTimeUtc,
        ),
    )

    /** Matches web's `EditLoan.save()`: currency/funding-account/auto-mark
     * are not editable here (funding account is only set via a mark-paid
     * confirm, matching web's own `setLoanFundingAccount` call site). */
    suspend fun update(id: String, input: EditLoanInput) = updateRow(
        db, "loans", id,
        mapOf(
            "lender" to input.lender, "principal" to input.principal, "emi_amount" to input.emiAmount,
            "interest_rate" to input.interestRate, "tenure_months" to input.tenureMonths,
            "start_date" to input.startDate, "emi_due_day" to input.emiDueDay,
            "rate_type" to input.rateType, "alert_time_utc" to input.alertTimeUtc,
        ),
    )

    suspend fun delete(id: String) = softDelete(db, "loans", id)

    /** Matches web's `setManualPaid()`: rewrites the whole `emi_payments`
     * JSON map and the legacy `emis_paid` count together. */
    suspend fun setManualPaid(id: String, emiPaymentsJson: String, emisPaidCount: Int) = updateRow(
        db, "loans", id,
        mapOf("emi_payments" to emiPaymentsJson, "emis_paid" to emisPaidCount.toLong()),
    )

    /** Matches web's `setAmount()` (variable-rate month EMI). */
    suspend fun setEmiAmounts(id: String, emiAmountsJson: String) = updateRow(db, "loans", id, mapOf("emi_amounts" to emiAmountsJson))

    /** Matches web's `toggleAutoMark()`. */
    suspend fun setAutoMarkPaid(id: String, enabled: Boolean) = updateRow(db, "loans", id, mapOf("auto_mark_paid" to if (enabled) 1L else 0L))

    /** Matches web's `setLoanFundingAccount()` -- remembered so the next
     * EMI mark-paid defaults to the same account. Unlike web (which falls
     * back to localStorage for pre-migration rows), this always writes
     * the real `funding_account_id` column, which is present on both
     * native schemas from day one. */
    suspend fun setFundingAccountId(id: String, accountId: String?) = updateRow(db, "loans", id, mapOf("funding_account_id" to accountId))
}
