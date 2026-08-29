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
import com.powersync.db.getLong
import com.powersync.db.getLongOptional
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import kotlinx.coroutines.flow.Flow

/** One `market_dividends` row (global, read-only market-sync table). */
data class DividendRow(val symbol: String, val exchange: String?, val exDate: String, val payDate: String?, val amount: Long, val currency: String)

/** One `market_quotes` row (global, read-only). */
data class QuoteRow(val symbol: String, val exchange: String?, val price: Long, val currency: String)

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
    /** Amount-based SIP fields (migration 0061). `plannedId` alone is not
     * enough to tell a live SIP from a stopped one -- it can still point at a
     * recurring row that was already cancelled -- so web gates the SIP UI on
     * `planned_id && sip_amount > 0` and so does mobile. */
    val sipAmount: Long?,
    val sipDay: Long?,
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

/**
 * A SIP the user is setting up alongside the holding -- web's
 * `AddHoldingInput.sip`.
 *
 * [firstDue] is the date the recurring engine posts the first instalment and
 * [startDate] is when the plan began; web sends the same value for both from
 * one date field, and they are kept separate here because the COLUMNS are
 * separate (`recurring_items.next_due` moves every time the engine posts,
 * `holdings.sip_start_date` never does).
 *
 * [day] is the day-of-month, already clamped to 1-28 by
 * `domain.investments.clampSipDay` -- the repository does not re-clamp, so
 * there is exactly one place the rule lives.
 */
data class SipSetup(
    val amount: Long,
    val frequency: String,
    val firstDue: String,
    val sourceAccountId: String,
    val startDate: String,
    val day: Int,
)

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
    /** Present only when the user is starting a SIP. See [SipSetup]. */
    val sip: SipSetup? = null,
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
        sipAmount = cursor.getLongOptional("sip_amount"),
        sipDay = cursor.getLongOptional("sip_day"),
    )

    fun watchHoldings(userId: String): Flow<List<Holding>> = db.watch(
        sql = "SELECT * FROM holdings WHERE deleted_at IS NULL AND user_id = ? ORDER BY created_at DESC",
        parameters = listOf(userId),
        mapper = ::holdingMapper,
    )

    /** Global, read-only market-sync tables -- no user_id/deleted_at filter,
     * matches web's own unscoped queries exactly. Added 2026-08-06 for
     * Insights' dividend_income/portfolio_projection cards (task #28), the
     * first mobile reader of either table. */
    fun watchDividends(): Flow<List<DividendRow>> = db.watch(
        sql = "SELECT symbol, exchange, ex_date, pay_date, amount, currency FROM market_dividends",
        mapper = { cursor ->
            DividendRow(
                symbol = cursor.getString("symbol"), exchange = cursor.getStringOptional("exchange"),
                exDate = cursor.getString("ex_date"), payDate = cursor.getStringOptional("pay_date"),
                amount = cursor.getLong("amount"), currency = cursor.getString("currency"),
            )
        },
    )

    fun watchQuotes(): Flow<List<QuoteRow>> = db.watch(
        sql = "SELECT symbol, exchange, price, currency FROM market_quotes",
        mapper = { cursor ->
            QuoteRow(
                symbol = cursor.getString("symbol"), exchange = cursor.getStringOptional("exchange"),
                price = cursor.getLong("price"), currency = cursor.getString("currency"),
            )
        },
    )

    /**
     * Adds a holding -- matches write.ts's addHolding() exactly: funds the
     * invested pool first (transfer from a source account, or an adjustment
     * on the investment account itself for an already-owned holding), creates
     * the SIP's recurring transfer if there is one, then inserts the
     * `holdings` row.
     *
     * The SIP half was missing until now, and its absence was not cosmetic:
     * `planned_id` was hardcoded null and `sip_amount`/`sip_day` were never
     * written, so a SIP could not be created on a phone AT ALL and the Stop
     * SIP control could only ever appear for a holding created on web
     * (PARITY_AUDIT 2026-08-28, item 9).
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

        // The SIP is a recurring `saving` transfer: source account -> this
        // investment account, auto-posting on its own schedule.
        //
        // This is the ONLY place a recurring saving item is created on either
        // platform, exactly as on web. Recurring savings are not browsable
        // under Recurring, so a SIP belongs to the holding that funds it and
        // is created and stopped there (see stopSipForHolding). It still posts
        // through the shared engine and still shows in the "Due now" strip.
        //
        // One row, not a template + rule pair: `recurring_items` carries both
        // the schedule and the transaction detail (migration 0064).
        val plannedId: String? = inp.sip?.takeIf { it.amount > 0 && it.sourceAccountId.isNotBlank() }?.let { sip ->
            insertRow(
                db, "recurring_items", userId,
                mapOf(
                    "direction" to "saving",
                    "name" to inp.name.ifBlank { inp.symbol.ifBlank { "SIP" } },
                    "amount" to sip.amount,
                    "currency" to inp.currency,
                    "frequency" to sip.frequency,
                    // Web hardcodes 1 here too -- every interval the UI offers
                    // is "every 1 <frequency>".
                    "interval_count" to 1L,
                    "next_due" to sip.firstDue,
                    "account_id" to sip.sourceAccountId,
                    "to_account_id" to inp.investmentAccountId,
                    "category_id" to null,
                    "auto_post" to 1L,
                    "active" to 1L,
                    "alert_time_utc" to null,
                    "description" to "SIP",
                    "note" to null,
                    "payment_method" to null,
                    "labels" to null,
                    "split_group_id" to null,
                    "split_mode" to null,
                    "last_generated" to null,
                    "source_table" to null,
                    "source_id" to null,
                ),
            )
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
                // A SIP's money movement IS the recurring transfer, so its
                // source account is the debit account, not a one-off funding
                // account -- web resolves it in the same order.
                "source_account_id" to when {
                    inp.sip != null -> inp.sip.sourceAccountId
                    inp.funding is HoldingFunding.New -> inp.funding.sourceAccountId
                    else -> null
                },
                "planned_id" to plannedId,
                "off_list" to if (inp.offList) 1L else 0L,
                "auto_fetch" to if (inp.autoFetch) 1L else 0L,
                // Amount-based SIP fields (migration 0061). Written together
                // with `planned_id`: the UI reads a live SIP as
                // `planned_id != null && sip_amount > 0`, and half of that
                // pair is what made every mobile-created holding look
                // SIP-less.
                "sip_amount" to plannedId?.let { inp.sip?.amount },
                "sip_start_date" to plannedId?.let { inp.sip?.startDate },
                "sip_day" to plannedId?.let { inp.sip?.day?.toLong() },
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

    /**
     * Stop the SIP attached to a holding -- web's `stopSipForHolding()`.
     *
     * The recurring transfer is a standing debit on a real account, and
     * recurring savings are not browsable under Recurring, so if this is
     * skipped there is nowhere left for the user to go and cancel it: the
     * money keeps leaving every month for an investment that no longer
     * exists. No-op when the holding never had one.
     */
    suspend fun stopSipForHolding(plannedId: String?) {
        if (plannedId != null) softDelete(db, "recurring_items", plannedId)
    }

    /** Clears the holding's own SIP fields, so `sip_amount > 0` stops
     * reporting a live SIP once the recurring row is gone. Matches web's
     * `updateRow("holdings", id, { sip_amount: null, sip_day: null })`. */
    suspend fun clearSipFields(id: String) {
        updateRow(db, "holdings", id, mapOf<String, Any?>("sip_amount" to null, "sip_day" to null))
    }

    /**
     * Matches web's remove(): soft-delete the holding row, and kill its SIP
     * first -- the funding transaction is deliberately NOT reversed (same
     * accepted asymmetry as Goals' allocation-delete-doesn't-cascade,
     * documented in docs/mobile/screen-specs/goals.md), but a live standing
     * debit is not an asymmetry, it is money still moving.
     */
    suspend fun deleteHolding(id: String, plannedId: String?) {
        stopSipForHolding(plannedId)
        softDelete(db, "holdings", id)
    }
}
