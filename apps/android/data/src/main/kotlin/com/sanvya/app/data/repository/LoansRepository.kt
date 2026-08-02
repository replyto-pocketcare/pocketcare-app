package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.powersync.db.SqlCursor
import com.powersync.db.getBooleanOptional
import com.powersync.db.getDouble
import com.powersync.db.getLong
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import kotlinx.coroutines.flow.Flow

data class Loan(
    val id: String,
    val userId: String,
    val lender: String,
    val principal: Long,
    val currency: String,
    val interestRate: Double,
    val tenureMonths: Long,
    val emiAmount: Long,
    val startDate: String,
    val emisPaid: Long,
    val emiDueDay: Long,
    val autoMarkPaid: Boolean,
    val rateType: String
)

class LoansRepository(private val db: PowerSyncDatabase) {

    private fun loanMapper(cursor: SqlCursor): Loan = Loan(
        id = cursor.getString("id"),
        userId = cursor.getString("user_id"),
        lender = cursor.getString("lender"),
        principal = cursor.getLong("principal"),
        currency = cursor.getString("currency"),
        interestRate = cursor.getDouble("interest_rate"),
        tenureMonths = cursor.getLong("tenure_months"),
        emiAmount = cursor.getLong("emi_amount"),
        startDate = cursor.getString("start_date"),
        emisPaid = cursor.getLong("emis_paid"),
        emiDueDay = cursor.getLong("emi_due_day"),
        autoMarkPaid = cursor.getBooleanOptional("auto_mark_paid") ?: false,
        rateType = cursor.getString("rate_type")
    )

    fun watchLoans(userId: String): Flow<List<Loan>> = db.watch(
        sql = "SELECT * FROM loans WHERE deleted_at IS NULL AND user_id = ? ORDER BY created_at DESC",
        parameters = listOf(userId),
        mapper = ::loanMapper
    )
}
