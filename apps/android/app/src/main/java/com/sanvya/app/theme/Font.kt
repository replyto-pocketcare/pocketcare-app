package com.sanvya.app.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import com.sanvya.app.R

/**
 * The app's typefaces. Hand-written (not generated) because it wires resource
 * ids, which only exist on this platform.
 *
 * **Inter is bundled as a VARIABLE font, deliberately.** `globals.css` uses
 * font-weight 550 (`.trx-title`, `.pc-seg-btn`) and 650 (`h2`,
 * `.side-nav-item.active`). Static weight files only exist in 100-point steps,
 * so those two would round to 500 and 600 and every affected heading would sit
 * fractionally wrong next to the web app. Declaring the same variable file at
 * each weight with an explicit `wght` variation setting resolves them exactly.
 * Variable-font axes need API 26, which is this app's `minSdk`.
 *
 * The icon face is the same Material Symbols Rounded subset web serves — see
 * `SanvyaIcons` and `tools/parity/build-fonts.sh`.
 */
object SanvyaFont {

    // FontVariation is still @ExperimentalTextApi. Opting in knowingly: it is
    // the only way to reach the wght axis, and the alternative (static weight
    // files) cannot express the design's 550/650 at all.
    @OptIn(ExperimentalTextApi::class)
    private fun inter(weight: Int) = Font(
        resId = R.font.inter_variable,
        weight = FontWeight(weight),
        variationSettings = FontVariation.Settings(FontVariation.weight(weight)),
    )

    /**
     * Only the weights the design system actually uses. Compose resolves a
     * requested weight to the nearest declared one, so listing 550 and 650
     * here is what makes them reachable at all.
     */
    val family = FontFamily(
        inter(400),
        inter(500),
        inter(550),
        inter(600),
        inter(650),
        inter(700),
        inter(800),
    )

    /** Icons render as text by codepoint — see `SanvyaIcons` for why. */
    val icons = FontFamily(Font(R.font.sanvya_icons))
}

/**
 * Material 3's own type slots, filled from the generated scale.
 *
 * Screens should use `SanvyaType.*` directly — it is the source-derived scale.
 * This exists so stock Material components the app has not replaced yet
 * (dialogs, menus, snackbars) inherit Inter and sensible sizes instead of
 * Roboto, rather than as a second scale to design against.
 */
fun sanvyaMaterialTypography(): Typography {
    val base = Typography()
    fun slot(style: TextStyle, from: TextStyle) = style.merge(
        TextStyle(
            fontFamily = SanvyaFont.family,
            fontSize = from.fontSize,
            fontWeight = from.fontWeight,
            letterSpacing = from.letterSpacing,
        ),
    )
    return base.copy(
        displayLarge = slot(base.displayLarge, SanvyaType.h1),
        displayMedium = slot(base.displayMedium, SanvyaType.h1),
        displaySmall = slot(base.displaySmall, SanvyaType.h1Compact),
        headlineLarge = slot(base.headlineLarge, SanvyaType.h1),
        headlineMedium = slot(base.headlineMedium, SanvyaType.h1Compact),
        headlineSmall = slot(base.headlineSmall, SanvyaType.h2),
        titleLarge = slot(base.titleLarge, SanvyaType.h2),
        titleMedium = slot(base.titleMedium, SanvyaType.h2),
        titleSmall = slot(base.titleSmall, SanvyaType.statLabel),
        bodyLarge = slot(base.bodyLarge, SanvyaType.body),
        bodyMedium = slot(base.bodyMedium, SanvyaType.body),
        bodySmall = slot(base.bodySmall, SanvyaType.statLabel),
        labelLarge = slot(base.labelLarge, SanvyaType.button),
        labelMedium = slot(base.labelMedium, SanvyaType.statLabel),
        labelSmall = slot(base.labelSmall, SanvyaType.navLabel),
    )
}
