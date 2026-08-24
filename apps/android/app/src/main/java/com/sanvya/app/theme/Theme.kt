package com.sanvya.app.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 * Semantic token holder — the same names and values as the CSS custom
 * properties, so `LocalSanvyaColors.current.accent` and web's `var(--accent)`
 * are the same number from the same source.
 */
data class SanvyaColors(
    val bg: Color,
    val surface: Color,
    val surface2: Color,
    val border: Color,
    val borderStrong: Color,
    val sidebar: Color,
    val text: Color,
    val text2: Color,
    val text3: Color,
    val accent: Color,
    val accentHover: Color,
    val accentSoft: Color,
    val accentGhost: Color,
    val positive: Color,
    val negative: Color,
    val warning: Color,
    val teal: Color,
    val sage: Color,
    val forest: Color
)

private val lightTokens = SanvyaColors(
    bg = SanvyaLightColors.bg,
    surface = SanvyaLightColors.surface,
    surface2 = SanvyaLightColors.surface2,
    border = SanvyaLightColors.border,
    borderStrong = SanvyaLightColors.borderStrong,
    sidebar = SanvyaLightColors.sidebar,
    text = SanvyaLightColors.text,
    text2 = SanvyaLightColors.text2,
    text3 = SanvyaLightColors.text3,
    accent = SanvyaLightColors.accent,
    accentHover = SanvyaLightColors.accentHover,
    accentSoft = SanvyaLightColors.accentSoft,
    accentGhost = SanvyaLightColors.accentGhost,
    positive = SanvyaLightColors.positive,
    negative = SanvyaLightColors.negative,
    warning = SanvyaLightColors.warning,
    teal = SanvyaLightColors.teal,
    sage = SanvyaLightColors.sage,
    forest = SanvyaLightColors.forest
)

private val darkTokens = SanvyaColors(
    bg = SanvyaDarkColors.bg,
    surface = SanvyaDarkColors.surface,
    surface2 = SanvyaDarkColors.surface2,
    border = SanvyaDarkColors.border,
    borderStrong = SanvyaDarkColors.borderStrong,
    sidebar = SanvyaDarkColors.sidebar,
    text = SanvyaDarkColors.text,
    text2 = SanvyaDarkColors.text2,
    text3 = SanvyaDarkColors.text3,
    accent = SanvyaDarkColors.accent,
    accentHover = SanvyaDarkColors.accentHover,
    accentSoft = SanvyaDarkColors.accentSoft,
    accentGhost = SanvyaDarkColors.accentGhost,
    positive = SanvyaDarkColors.positive,
    negative = SanvyaDarkColors.negative,
    warning = SanvyaDarkColors.warning,
    teal = SanvyaDarkColors.teal,
    sage = SanvyaDarkColors.sage,
    forest = SanvyaDarkColors.forest
)

data class SanvyaShadows(
    val shadow: SanvyaShadow,
    val shadowLg: SanvyaShadow,
    val shadowAccent: SanvyaShadow
)

private val lightShadows = SanvyaShadows(
    shadow = SanvyaLightShadows.shadow,
    shadowLg = SanvyaLightShadows.shadowLg,
    shadowAccent = SanvyaLightShadows.shadowAccent
)

private val darkShadows = SanvyaShadows(
    shadow = SanvyaDarkShadows.shadow,
    shadowLg = SanvyaDarkShadows.shadowLg,
    shadowAccent = SanvyaDarkShadows.shadowAccent
)

val LocalSanvyaColors = staticCompositionLocalOf { lightTokens }
val LocalSanvyaShadows = staticCompositionLocalOf { lightShadows }

@Composable
fun SanvyaTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val tokens = if (darkTheme) darkTokens else lightTokens
    val shadows = if (darkTheme) darkShadows else lightShadows

    // Material 3 wiring so stock components (ripples, dialogs, text fields the
    // app has not replaced yet) land close to the design system. Screens still
    // prefer LocalSanvyaColors.current for anything that must match web
    // exactly — the same relationship globals.css's vars have to .card/.btn.
    val colorScheme = if (darkTheme) {
        darkColorScheme(
            background = tokens.bg,
            surface = tokens.surface,
            surfaceVariant = tokens.surface2,
            primary = tokens.accent,
            onPrimary = Color.White,
            onBackground = tokens.text,
            onSurface = tokens.text,
            onSurfaceVariant = tokens.text2,
            outline = tokens.border,
            error = tokens.negative,
        )
    } else {
        lightColorScheme(
            background = tokens.bg,
            surface = tokens.surface,
            surfaceVariant = tokens.surface2,
            primary = tokens.accent,
            onPrimary = Color.White,
            onBackground = tokens.text,
            onSurface = tokens.text,
            onSurfaceVariant = tokens.text2,
            outline = tokens.border,
            error = tokens.negative,
        )
    }

    CompositionLocalProvider(
        LocalSanvyaColors provides tokens,
        LocalSanvyaShadows provides shadows,
    ) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = sanvyaMaterialTypography(),
            content = content,
        )
    }
}
