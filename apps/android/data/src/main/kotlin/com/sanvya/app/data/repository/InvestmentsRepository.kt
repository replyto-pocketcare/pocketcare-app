package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.powersync.db.SqlCursor
import com.powersync.db.getBooleanOptional
import com.powersync.db.getDouble
import com.powersync.db.getDoubleOptional
import com.powersync.db.getLong
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import kotlinx.coroutines.flow.Flow

data class Holding(
    val id: String,
    val userId: String,
    val accountId: String,
    val symbol: String,
    val exchange: String,
    val quantity: Double,
    val avgCost: Long,
    val currency: String,
    val autoFetch: Boolean,
    val instrumentType: String,
    val name: String?,
    val assetClass: String?,
    val currentValue: Long?,
    val annualRate: Double?,
    val maturityDate: String?
)

class InvestmentsRepository(private val db: PowerSyncDatabase) {

    private fun holdingMapper(cursor: SqlCursor): Holding = Holding(
        id = cursor.getString("id"),
        userId = cursor.getString("user_id"),
        accountId = cursor.getString("account_id"),
        symbol = cursor.getString("symbol"),
        exchange = cursor.getString("exchange"),
        quantity = cursor.getDouble("quantity"),
        avgCost = cursor.getLong("avg_cost"),
        currency = cursor.getString("currency"),
        autoFetch = cursor.getBooleanOptional("auto_fetch") ?: false,
        instrumentType = cursor.getString("instrument_type"),
        name = cursor.getStringOptional("name"),
        assetClass = cursor.getStringOptional("asset_class"),
        currentValue = cursor.getLong("current_value"),
        annualRate = cursor.getDoubleOptional("annual_rate"),
        maturityDate = cursor.getStringOptional("maturity_date")
    )

    fun watchHoldings(userId: String): Flow<List<Holding>> = db.watch(
        sql = "SELECT * FROM holdings WHERE deleted_at IS NULL AND user_id = ? ORDER BY created_at DESC",
        parameters = listOf(userId),
        mapper = ::holdingMapper
    )
}
