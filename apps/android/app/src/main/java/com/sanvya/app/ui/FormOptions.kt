package com.sanvya.app.ui

// GENERATED FILE — do not hand-edit.
// Source: packages/core/catalog/src/index.ts
// Regenerate with: node tools/parity/generate-options.mjs

/**
 * The option lists every form offers.
 *
 * These are *offered* options, not the currencies the app can handle: the
 * money layer knows the minor units of every ISO 4217 code, and an account
 * synced in a currency absent from this list still formats correctly. This is
 * only what a picker shows.
 */
object FormOptions {
    val currencies = listOf("INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED")

    /**
     * The fallback when nothing else is known — a fresh install, or a row whose
     * currency column is null. The ONLY place a currency literal belongs;
     * everywhere else reads the user's base-currency setting.
     */
    const val DEFAULT_CURRENCY = "INR"

    val periods = listOf("daily", "weekly", "monthly", "yearly")

    val accountTypes = listOf("savings", "current", "credit_card", "cash", "mutual_funds", "stocks", "demat")

    /**
     * Accounts that only RECORD investments — they hold holdings, not spendable
     * money. Every picker that moves real money filters these out.
     */
    val investmentAccountTypes = listOf("demat", "stocks", "mutual_funds")

    /** True when the type is an investment account. Mirrors web isInvestmentAccount. */
    fun isInvestmentAccount(type: String?): Boolean = !type.isNullOrEmpty() && type in investmentAccountTypes

    /**
     * Hex, not `Color`: this is what gets written to `accounts.color`, so all
     * three apps must agree on the string. Converted at the point of use.
     */
    val accountColors = listOf("#3e4a38", "#5f6647", "#6b7a4f", "#9cae8e", "#b06a4f", "#c98a72", "#a8503a", "#7c4a3a", "#5f4636", "#c9b79c", "#c08a3e", "#4f46e5", "#6d5acf", "#3f5a8a", "#2f6f6a", "#7a4a6b", "#4b5563", "#2b2723")

    val defaultAccountColor = accountColors.first()

    /** Insights' multi-series palette -- web's INSIGHT_PALETTE. */
    val chartColors = listOf("#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#7c7264", "#5f6647")

    /** The dashboard tiles' palette -- web's PIE. NOT the same list. */
    val dashboardChartColors = listOf("#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#4f46e5", "#7c7264")

    const val FALLBACK_ACCOUNT_COLOR = "#7c7264"

    /**
     * `value` is what is stored. `label` is English and NOT yet translated —
     * there are no `gender.*` keys in the i18n on any platform. See the note
     * in packages/core/catalog.
     */
    data class Option(val value: String, val label: String)

    val genders = listOf(
        Option("", "Not specified"),
        Option("female", "Female"),
        Option("male", "Male"),
        Option("non-binary", "Non-binary"),
        Option("prefer not to say", "Prefer not to say"),
    )

    val countries = listOf("", "IN", "US", "GB", "CA", "AU", "SG", "AE", "DE", "FR", "NL", "JP", "BR", "ZA", "NG", "KE", "Other")

    /** A paid plan, straight from web's billing catalogue. Prices are RUPEES. */
    data class Plan(
        val id: String,
        val label: String,
        val monthly: Int,
        val yearly: Int,
        val quota: Int,
    )

    val plans = listOf(
        Plan("lite", "Lite", 49, 499, 50),
        Plan("pro", "Pro", 99, 999, 200),
    )

    /**
     * A stable colour for an id, when none was chosen.
     *
     * Deterministic so the same account is the same colour on every device and
     * in every session. Ported with the palette rather than re-implemented,
     * because a platform that re-derived the hash would disagree with web about
     * a colour the user has already seen.
     */
    fun colorForId(id: String?, fallback: String = FALLBACK_ACCOUNT_COLOR): String {
        if (id.isNullOrEmpty()) return fallback
        var h = 0u
        for (c in id) h = (h * 31u + c.code.toUInt())
        return accountColors[(h % accountColors.size.toUInt()).toInt()]
    }
}
