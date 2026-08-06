package com.sanvya.app.domain.investments

/**
 * Investments domain model (pure, UI-agnostic) -- Kotlin port of
 * apps/web/src/investments/model.ts, read in full 2026-08-06 for task #26.
 * A "holding" is any tracked investment: a listed stock/MF, or a crypto
 * coin, fixed deposit, SIP, or other scheme. Holdings are grouped for
 * display by **exchange** (for listed stocks) and by **asset class**
 * (everything else), each group carrying invested/current/gain subtotals.
 *
 * Live market quotes are NOT ported (see docs/mobile/screen-specs/
 * investments.md's Deferred section) -- [valuation] is always called with
 * `quote = null` on both native platforms, so listed holdings value at
 * `current_value ?? cost` exactly like an off-list holding would on web.
 * This is a real, documented simplification, not a bug.
 */

enum class AssetClass(val key: String, val label: String, val icon: String, val unitWord: String, val listed: Boolean) {
    STOCK("stock", "Stock", "▤", "shares", true),
    MF("mf", "Mutual fund", "◈", "units", true),
    SIP("sip", "SIP", "↻", "units", false),
    CRYPTO("crypto", "Crypto", "◇", "coins", false),
    FD("fd", "Fixed deposit", "▦", "", false),
    OTHER("other", "Other scheme", "✦", "", false),
    ;

    companion object {
        fun fromKey(key: String?): AssetClass = values().find { it.key == key } ?: OTHER
    }
}

fun isListed(c: AssetClass): Boolean = c == AssetClass.STOCK || c == AssetClass.MF

/** [c]'s own icon/label/unitWord fields ARE the "class meta" -- unlike
 * web's separate ASSET_CLASSES lookup table, Kotlin's enum already carries
 * them, so callers just use the enum instance directly (`cls.icon`,
 * `cls.label`, `cls.unitWord`) rather than a redundant lookup function. */

/** Minimal holding shape the pure functions below operate on -- mirrors
 * web's HoldingRow. Callers (repositories) map their own data class into
 * this one rather than this model depending on any data-layer type. */
data class HoldingRow(
    val id: String,
    val accountId: String,
    val symbol: String,
    val exchange: String?,
    val quantity: Double,
    val avgCost: Long?,
    val currency: String,
    val offList: Boolean,
    val name: String?,
    val assetClass: String?,
    val currentValue: Long?,
)

fun assetClassOf(h: HoldingRow): AssetClass = AssetClass.fromKey(h.assetClass)

/** Display label for a holding -- matches web's holdingLabel() exactly. */
fun holdingLabel(h: HoldingRow): String {
    if (h.offList || !isListed(assetClassOf(h))) return h.name?.takeIf { it.isNotBlank() } ?: h.symbol.takeIf { it.isNotBlank() } ?: "Investment"
    return h.symbol.takeIf { it.isNotBlank() } ?: h.name?.takeIf { it.isNotBlank() } ?: "Holding"
}

/** Stable grouping key: listed stocks by exchange, everything else by class. */
fun groupKeyOf(h: HoldingRow): String {
    val c = assetClassOf(h)
    return if (c == AssetClass.STOCK) "ex:${(h.exchange?.takeIf { it.isNotBlank() } ?: "OTHER").uppercase()}" else "cls:${c.key}"
}

private val CLASS_LABEL = mapOf(
    AssetClass.STOCK to "Stocks", AssetClass.MF to "Mutual Funds", AssetClass.CRYPTO to "Crypto",
    AssetClass.FD to "Fixed Deposits", AssetClass.SIP to "SIPs", AssetClass.OTHER to "Other Schemes",
)

/** Human label for a group key. */
fun groupLabel(key: String): String {
    if (key.startsWith("ex:")) {
        val ex = key.substring(3)
        return if (ex == "OTHER") "Stocks (other)" else ex
    }
    val c = AssetClass.fromKey(key.substring(4))
    return CLASS_LABEL[c] ?: "Investments"
}

/** Sort order for group tiles: exchanges first, then MF, SIP, crypto, FD, other. */
fun groupSort(key: String): Int {
    if (key.startsWith("ex:")) return 0
    val order = mapOf("mf" to 10, "sip" to 11, "crypto" to 12, "fd" to 13, "other" to 14)
    return order[key.substring(4)] ?: 20
}

data class Valuation(val cost: Long, val value: Long, val gain: Long, val gainPct: Double)

/**
 * Value a holding in its own currency (minor units). Listed & priced would
 * use a live quote x quantity, but this port has no live-quote source
 * (deferred) so [quotePrice] is always null in practice -- falls back to
 * the user-supplied current_value, else cost, matching web's own fallback
 * for off-list holdings.
 */
fun valuation(h: HoldingRow, quotePrice: Double? = null): Valuation {
    val cost = Math.round((h.avgCost ?: 0L) * h.quantity)
    val priced = !h.offList && isListed(assetClassOf(h)) && quotePrice != null
    val value = if (priced) Math.round(quotePrice!! * h.quantity) else (h.currentValue ?: cost)
    val gain = value - cost
    val gainPct = if (cost > 0) (gain.toDouble() / cost.toDouble()) * 100 else 0.0
    return Valuation(cost, value, gain, gainPct)
}

data class Group(
    val key: String,
    val label: String,
    val holdings: List<HoldingRow>,
    val cost: Long,
    val value: Long,
    val gain: Long,
    val gainPct: Double,
)

/**
 * Bucket holdings into display groups with base-currency subtotals.
 * [convert] converts a holding-currency minor amount to base currency.
 */
fun buildGroups(holdings: List<HoldingRow>, convert: (Long, String) -> Long): List<Group> {
    data class Acc(val key: String, val label: String, val holdings: MutableList<HoldingRow>, var cost: Long, var value: Long)
    val map = LinkedHashMap<String, Acc>()
    for (h in holdings) {
        val key = groupKeyOf(h)
        val acc = map.getOrPut(key) { Acc(key, groupLabel(key), mutableListOf(), 0L, 0L) }
        val v = valuation(h)
        acc.holdings.add(h)
        acc.cost += convert(v.cost, h.currency)
        acc.value += convert(v.value, h.currency)
    }
    return map.values.map { acc ->
        val gain = acc.value - acc.cost
        val gainPct = if (acc.cost > 0) (gain.toDouble() / acc.cost.toDouble()) * 100 else 0.0
        Group(acc.key, acc.label, acc.holdings, acc.cost, acc.value, gain, gainPct)
    }.sortedWith(compareBy({ groupSort(it.key) }, { it.label }))
}

data class PortfolioTotals(val cost: Long, val value: Long, val gain: Long, val gainPct: Double)

fun portfolioTotals(groups: List<Group>): PortfolioTotals {
    val cost = groups.sumOf { it.cost }
    val value = groups.sumOf { it.value }
    val gain = value - cost
    val gainPct = if (cost > 0) (gain.toDouble() / cost.toDouble()) * 100 else 0.0
    return PortfolioTotals(cost, value, gain, gainPct)
}
