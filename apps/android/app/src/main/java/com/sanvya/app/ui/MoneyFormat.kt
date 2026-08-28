package com.sanvya.app.ui

import com.sanvya.app.domain.money.Money
import com.sanvya.app.domain.money.format
import com.sanvya.app.domain.money.minorUnits
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.money.toMajor

/**
 * The one money formatter.
 *
 * Before this file, eleven screens each built their own:
 *
 * ```
 * NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
 *     currency = Currency.getInstance("INR")
 * }
 * ```
 *
 * Every one of them was wrong the same three ways. The currency was pinned to
 * INR, so a USD account rendered with a rupee sign. The locale was pinned to
 * `en_IN`, so **every** currency got lakh/crore grouping — $1,25,000. And none
 * of them consulted the hide-amounts setting, which is the privacy-leak class
 * that has already shipped on web three times (PARITY_AUDIT trap 7).
 *
 * Two of the eleven were also called `formatMoney`, declared `internal` in
 * different files with *different* `maximumFractionDigits` — 0 in Loans, 2 in
 * Splits — so the same amount rendered differently on two screens.
 *
 * Everything now goes through the generated `domain.money.format`, which takes
 * its fraction digits from `minorUnits(currency)` and its grouping from the
 * currency's own locale. This mirrors iOS's `App/Components/MoneyFormat.swift`
 * exactly, so the two platforms cannot drift.
 */

/** Shown in place of an amount when hide-amounts is on. Matches web's `useMoneyFmt`. */
const val MONEY_MASK = "••••"

/**
 * Format a [Money], respecting the hide-amounts privacy setting.
 *
 * This is the native `useMoneyFmt()`. Use it for **every** amount that reaches
 * the screen — including inside charts, which is where web's leaks happened.
 */
/**
 * The divisor that turns minor units into major ones for a currency.
 *
 * For a CHART, where the value is already a Double (an average, a running
 * total) and wrapping it back into a `Money` would round it. Everywhere an
 * exact integer amount is in hand, `toMajor` is the right call instead.
 *
 * It exists so chart code stops writing `/ 100.0`, which is correct for the
 * rupee, the dollar and the euro and wrong for the yen -- a JPY chart drawn
 * that way plots every point at a hundredth of its real height, silently.
 */
fun majorScale(currency: String): Double = Math.pow(10.0, minorUnits(currency).toDouble())

/**
 * The unformatted major-unit value, for a field the user is about to edit.
 *
 * Deliberately NOT `formatMoney`: an input field must contain something the
 * user can type back, so no symbol, no grouping and no mask. It is still
 * currency-aware.
 *
 * **There were four copies of this, and three of them divided by 100.** The one
 * correct copy lived in InvestmentsViewModel with a comment explaining exactly
 * why; the other three put two extra decimal places into a JPY field and
 * dropped one from a KWD field. A helper duplicated per screen is a helper that
 * gets fixed on one screen.
 */
fun formatMajorPlain(minor: Long, currency: String): String {
    val major = toMajor(money(minor, currency))
    return if (major == Math.floor(major)) major.toLong().toString() else major.toString()
}

fun formatMoneyAware(m: Money, mask: String = MONEY_MASK): String =
    if (Prefs.amountsHidden.value) mask else format(m)

/** Convenience for the common `(minorUnits, currencyCode)` call shape. */
fun formatMoney(minor: Long, currency: String, mask: String = MONEY_MASK): String =
    formatMoneyAware(money(minor, currency), mask)

/**
 * Format without masking.
 *
 * For the rare place an amount must always be visible — an input field the user
 * is actively editing, where masking would make the field unusable rather than
 * private. **Not** for display.
 */
fun formatMoneyUnmasked(m: Money): String = format(m)

/**
 * The user's base currency, for amounts that roll up across accounts.
 *
 * Net worth, a cross-group split position, a multi-currency total: none of these
 * is *in* any one account's currency, so they report in the currency the user
 * chose. Reading it here rather than at eleven call sites is what makes the
 * setting mean something — it was write-only until now.
 */
fun baseCurrencyNow(): String = Prefs.baseCurrency.value
