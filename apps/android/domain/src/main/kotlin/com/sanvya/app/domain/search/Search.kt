package com.sanvya.app.domain.search

import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.money.minorUnits
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.money.toMajor
import kotlin.math.abs

/**
 * The Search screen's filter, ported from apps/web/app/search/page.tsx.
 *
 * Web computes this inside a `useMemo` in the page component. It is pure
 * function of (rows, criteria) with no React in it, so it lives here and is
 * vector-tested; the screen keeps only the criteria and the rendering.
 * Mirrors apps/ios/Domain/Sources/Domain/Search.swift.
 */

/** Type filter chips, in web's order. */
val SEARCH_TYPES = listOf("all", "income", "expense", "transfer")

/** Web slices the filtered list to 300 before rendering. */
const val SEARCH_RESULT_LIMIT = 300

/**
 * A transaction with its display names already resolved.
 *
 * Web resolves them in the component (`catName`, `acct`, and the `method_label`
 * correlated subquery); doing it in the caller keeps this function pure and
 * keeps the joins in `:data` where the other queries live.
 */
data class SearchRow(
    val id: String,
    val type: String,
    val accountId: String,
    val toAccountId: String?,
    val occurredAt: String,
    val amountMinor: Long,
    val currency: String,
    val labels: String?,
    val note: String?,
    val description: String?,
    val methodLabel: String?,
    val categoryName: String?,
    val accountName: String?,
    val accountType: String?,
)

data class SearchCriteria(
    val query: String = "",
    val type: String = "all",
    val accountId: String = "",
    /** `YYYY-MM-DD`, inclusive. */
    val from: String = "",
    /** `YYYY-MM-DD`, inclusive. */
    val to: String = "",
    /** Major units, as typed. Blank or unparseable means "no bound". */
    val min: String = "",
    /** Major units, as typed. Blank or unparseable means "no bound". */
    val max: String = "",
)

/** How many filters are set -- web shows this as "Filters · N". */
fun activeFilterCount(c: SearchCriteria): Int = listOf(
    c.type != "all",
    c.accountId.isNotEmpty(),
    c.from.isNotEmpty(),
    c.to.isNotEmpty(),
    c.min.isNotEmpty(),
    c.max.isNotEmpty(),
).count { it }

/**
 * Everything web's `hay` concatenates, lowercased, in web's order.
 *
 * The amount is included so "499" finds a ₹499 charge. Web renders it as
 * `toMajor(money(...)).toFixed(2)` -- a hardcoded two decimals, which is wrong
 * for JPY and KWD; this uses the currency's own minor-unit count. INR, USD and
 * EUR are unaffected, which is why web's version has survived.
 */
private fun haystack(r: SearchRow): String {
    val decimals = minorUnits(r.currency)
    val major = toMajor(money(r.amountMinor, r.currency))
    val amountText = String.format(java.util.Locale.ROOT, "%.${decimals}f", major)
    return listOf(
        r.labels, r.note, r.description, r.type, r.methodLabel,
        r.categoryName, r.accountName, r.accountType, amountText,
    ).filter { !it.isNullOrEmpty() }.joinToString(" ").lowercase()
}

/**
 * The amount bound in the ROW's own currency.
 *
 * Web writes `Math.round(Number(min) * 100)` -- the same hardcoded x100 the
 * de-hardcoding programme is removing everywhere else, and it compares that
 * against `Math.abs(t.amount)`, which is in the row's own minor units. So on
 * web a "500" bound means ¥50000 against a yen row. Converting per row with
 * `fromMajor` is what the comparison web is *trying* to make actually needs.
 *
 * An unparseable bound returns null and therefore filters nothing, matching
 * web: `Number("abc")` is NaN and every NaN comparison is false.
 */
private fun bound(text: String, currency: String): Long? {
    if (text.isEmpty()) return null
    val value = text.toDoubleOrNull() ?: return null
    if (value.isNaN() || value.isInfinite()) return null
    return fromMajor(value, currency).amount
}

/**
 * Filters `rows` -- which the caller supplies newest-first -- and caps the
 * result at [SEARCH_RESULT_LIMIT], exactly as web's `useMemo` does.
 */
fun searchTransactions(rows: List<SearchRow>, c: SearchCriteria): List<SearchRow> {
    val term = c.query.trim().lowercase()
    return rows.filter { r ->
        when {
            c.type != "all" && r.type != c.type -> false
            c.accountId.isNotEmpty() && r.accountId != c.accountId && r.toAccountId != c.accountId -> false
            else -> {
                val day = r.occurredAt.take(10)
                val minA = bound(c.min, r.currency)
                val maxA = bound(c.max, r.currency)
                when {
                    c.from.isNotEmpty() && day < c.from -> false
                    c.to.isNotEmpty() && day > c.to -> false
                    minA != null && abs(r.amountMinor) < minA -> false
                    maxA != null && abs(r.amountMinor) > maxA -> false
                    term.isNotEmpty() && !haystack(r).contains(term) -> false
                    else -> true
                }
            }
        }
    }.take(SEARCH_RESULT_LIMIT)
}
