package com.sanvya.app.ui

import androidx.compose.ui.graphics.Color

/**
 * Per-account chip colours, derived from the generated palette.
 *
 * Deliberately distinct from the earthy design tokens in Theme.kt — this
 * includes jewel tones (indigo/violet/denim) and is used only for colouring one
 * account against another.
 *
 * The palette itself is NOT declared here. It lives once, in
 * `packages/core/catalog`, and reaches this module as `FormOptions.accountColors`
 * — hex strings, because hex is what gets written to `accounts.color` and all
 * three apps must agree on the string. This file only converts.
 *
 * It used to be declared twice in this module alone: an ARGB `Int` list here and
 * a `"#RRGGBB"` list in CreateAccountViewModel, which had to be kept
 * byte-identical by hand and were only ever checked by eye.
 */
private fun parseHex(hex: String): Color {
    val v = hex.removePrefix("#").toLong(16)
    return Color(v or 0xFF000000L)
}

val ACCOUNT_COLORS: List<Color> = FormOptions.accountColors.map(::parseHex)

/**
 * The two CHART palettes, which are neither the account palette nor each other.
 *
 * Web keeps them in two files -- `insights/types.ts` and `dashboard/tiles.tsx`
 * -- and they have drifted apart at the last two entries, despite the first
 * one's comment claiming they match. Both are generated into `FormOptions` now,
 * so the drift is at least honest and in one place. Insights' copy used to be a
 * `private val` inside InsightsScreen.kt, unreachable by anything else, which
 * is how the dashboard nearly acquired a fifth hand-typed copy.
 */
val CHART_COLORS: List<Color> = FormOptions.chartColors.map(::parseHex)
val DASHBOARD_CHART_COLORS: List<Color> = FormOptions.dashboardChartColors.map(::parseHex)

private val FALLBACK_COLOR = parseHex(FormOptions.FALLBACK_ACCOUNT_COLOR)

/**
 * A stable colour for an account with none set.
 *
 * Delegates to the generated `colorForId` rather than re-deriving the hash: this
 * has to agree with web and iOS about a colour the user has already seen.
 */
fun colorForId(id: String?): Color =
    if (id.isNullOrEmpty()) FALLBACK_COLOR else parseHex(FormOptions.colorForId(id))

/**
 * The account's own colour when it has one, else a stable derived one.
 *
 * A malformed stored value falls back rather than throwing — the column is
 * free-form text, and a crash on render would be a poor trade for a bad hex.
 */
fun accountColor(explicit: String?, id: String): Color {
    if (!explicit.isNullOrBlank()) {
        return try {
            parseHex(explicit)
        } catch (e: NumberFormatException) {
            colorForId(id)
        }
    }
    return colorForId(id)
}
