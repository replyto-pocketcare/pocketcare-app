package com.sanvya.app.ui

import com.sanvya.app.domain.money.Money
import com.sanvya.app.domain.money.format
import com.sanvya.app.domain.money.money

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
