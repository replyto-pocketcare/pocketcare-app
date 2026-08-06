package com.sanvya.app.data.repository

/**
 * Investments (holdings) repository -- P3.20 (task #26), read/write.
 * Mirrors apps/web/src/investments/write.ts's addHolding() and page.tsx's
 * EditHolding.save()/remove() exactly. See docs/mobile/screen-specs/
 * investments.md for the full source-verification notes.
 *
 * Fixed this pass (2026-08-06): `exchange`/`instrument_type`/`avg_cost` were
 * previously mapped as non-nullable via non-optional cursor getters despite
 * web's HoldingRow treating all three as nullable (`exchange: string | null`,
 * `instrument_type: string | null`, `avg_cost: number | null`) -- a real
 * runtime-crash risk for any holding where those columns are actually null
 * (e.g. a freshly-added FD/crypto/other-scheme holding has no exchange).
 * `current_value` was already correctly typed `Long?` in Kotlin but was
 * still read via non-optional `getLong`, which would crash the exact same
 * way. Also added the three columns the schema already had
 * (PocketCareSchema.kt's `holdings` TableDef) but this repository's
 * `Holding` data class was missing entirely: `off_list` (functionally
 * significant -- gates live pricing/"untracked" display, see
 * domain/investments/InvestmentsModel.kt's `holdingLabel`/`valuation`),
 * `source_account_id`, `planned_id`.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.SqlCursor
import com.powersync.db.getBooleanOptional
import com.powersync.db.getDouble
import com.powersync.db.getDoubleOptional
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import kotlinx.coroutines.flow.Flow

data class Holding(
    val id: String,
    val userId: String,
    val accountId: String,
    val symbol: String,
    val exchange: String?,
    val quantity: Double,
    val avgCost: Long?,
    val currency: String,
    val autoFetch: Boolean,
    val instrumentType: String?,
    val offList: Boolean,
    val name: String?,
    val assetClass: String?,
    val currentValue: Long?,
    val annualRate: Double?,
    val maturityDate: String?,
    val sourceAccountId: String?,
    val plannedId: String?,
)

/** Funding mode for a new holding -- matches web's AddHoldingInput.funding
 * union: an EXISTING holding raises the investment account's invested pool
 * via an `adjustment` entry (money was already in the market); a NEW
 * investment `transfer`s the cost from a chosen savings/other account into
 * the investment account (money moves, net worth preserved). */
sealed class HoldingFunding {
    object Existing : HoldingFunding()
    data class New(val sourceAccountId: String) : HoldingFunding()
}

data class AddHoldingInput(
    val investmentAccountId: String,
    val assetClass: String,
    val symbol: String,
    val exchange: String?,
    val name: String,
    val quantity: Double,
    val avgCost: Long?,
    val currency: String,
    val currentValue: Long?,
    val annualRate: Double?,
    val maturityDate: String?,
    val offList: Boolean,
    val autoFetch: Boolean,
    val funding: HoldingFunding,
)

class InvestmentsRepository(private val db: PowerSyncDatabase) {

    private fun holdingMapper(cursor: SqlCursor): Holding = Holding(
        id = cursor.getString("id"),
        userId = cursor.getString("user_id"),
        accountId = cursor.getString("account_id"),
        symbol = cursor.getString("symbol"),
        exchange = cursor.getStringOptional("exchange"),
        quantity = cursor.getDouble("quantity"),
        avgCost = cursor.getLongOptional("avg_cost"),
        currency = cursor.getString("currency"),
        autoFetch = cursor.getBooleanOptional("auto_fetch") ?: false,
        instrumentType = cursor.getStringOptional("instrument_type"),
        offList = cursor.getBooleanOptional("off_list") ?: false,
        name = cursor.getStringOptional("name"),
        assetClass = cursor.getStringOptional("asset_class"),
        currentValue = cursor.getLongOptional("current_value"),
        annualRate = cursor.getDoubleOptional("annual_rate"),
        maturityDate = cursor.getStringOptional("maturity_date"),
        sourceAccountId = cursor.getStringOptional("source_account_id"),
        plannedId = cursor.getStringOptional("planned_id"),
    )

    fun watchHoldings(userId: String): Flow<List<Holding>> = db.watch(
        sql = "SELECT * FROM holdings WHERE deleted_at IS NULL AND user_id = ? ORDER BY created_at DESC",
        parameters = listOf(userId),
        mapper = ::holdingMapper,
    )

    /**
     * Adds a holding -- matches write.ts's addHolding() exactly: funds the
     * invested pool first (transfer from a source account, or an adjustment
     * on the investment account itself for an already-owned holding), then
     * inserts the `holdings` row. SIP recurring-transfer setup and the
     * live-catalog instrument picker are deferred (see screen spec) so
     * there is no `sip` parameter here, unlike web's.
     */
    suspend fun addHolding(userId: String, inp: AddHoldingInput): String {
        val costTotal = Math.round((inp.avgCost ?: 0L) * inp.quantity)

        if (costTotal > 0) {
            when (inp.funding) {
                is HoldingFunding.New -> insertRow(
                    db, "transactions", userId,
                    mapOf(
                        "account_id" to inp.funding.sourceAccountId,
                        "type" to "transfer",
                        "amount" to costTotal,
                        "currency" to inp.currency,
                        "to_account_id" to inp.investmentAccountId,
                        "to_amount" to costTotal,
                        "description" to "Invested in ${inp.name.ifBlank { inp.symbol.ifBlank { "investment" } }}",
                        "occurred_at" to nowIso(),
                    ),
                )
                HoldingFunding.Existing -> insertRow(
                    db, "transactions", userId,
                    mapOf(
                        "account_id" to inp.investmentAccountId,
                        "type" to "adjustment",
                        "amount" to costTotal,
                        "currency" to inp.currency,
                        "description" to "Existing investment: ${inp.name.ifBlank { inp.symbol.ifBlank { "holding" } }}",
                        "occurred_at" to nowIso(),
                    ),
                )
            }
        }

        return insertRow(
            db, "holdings", userId,
            mapOf(
                "account_id" to inp.investmentAccountId,
                "symbol" to inp.symbol,
                "exchange" to inp.exchange,
                "name" to inp.name.ifBlank { null },
                "quantity" to inp.quantity,
                "avg_cost" to inp.avgCost,
                "currency" to inp.currency,
                "asset_class" to inp.assetClass,
                "instrument_type" to when (inp.assetClass) { "mf" -> "mf"; "stock" -> "stock"; else -> null },
                "current_value" to inp.currentValue,
                "annual_rate" to inp.annualRate,
                "maturity_date" to inp.maturityDate,
                "source_account_id" to if (inp.funding is HoldingFunding.New) inp.funding.sourceAccountId else null,
                "planned_id" to null,
                "off_list" to if (inp.offList) 1L else 0L,
                "auto_fetch" to if (inp.autoFetch) 1L else 0L,
            ),
        )
    }

    /** Matches web's EditHolding.save(): quantity/avg_cost always editable;
     * current_value/annual_rate only meaningful for unpriced holdings but
     * harmless to write through for priced ones (web does the same --
     * updateRow always sends all four). */
    suspend fun updateHolding(id: String, quantity: Double, avgCost: Long?, currentValue: Long?, annualRate: Double?) {
        updateRow(
            db, "holdings", id,
            mapOf("quantity" to quantity, "avg_cost" to avgCost, "current_value" to currentValue, "annual_rate" to annualRate),
        )
    }

    /** Matches web's remove(): soft-delete the holding row only -- no
     * reversal of the funding transaction (same accepted asymmetry as
     * Goals' allocation-delete-doesn't-cascade, already documented in
     * docs/mobile/screen-specs/goals.md). */
    suspend fun deleteHolding(id: String) = softDelete(db, "holdings", id)
}
