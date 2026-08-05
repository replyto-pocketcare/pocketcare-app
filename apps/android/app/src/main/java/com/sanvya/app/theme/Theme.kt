package com.sanvya.app.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css :root / :root[data-theme="dark"]
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 * Semantic token holder — mirrors the CSS custom properties exactly (same
 * names, same values) so a screen reading `LocalSanvyaColors.current.accent`
 * is reading the same source-derived value web reads from `var(--accent)`.
 */
data class SanvyaColors(
    val bg: androidx.compose.ui.graphics.Color,
    val surface: androidx.compose.ui.graphics.Color,
    val surface2: androidx.compose.ui.graphics.Color,
    val border: androidx.compose.ui.graphics.Color,
    val borderStrong: androidx.compose.ui.graphics.Color,
    val sidebar: androidx.compose.ui.graphics.Color,
    val text: androidx.compose.ui.graphics.Color,
    val text2: androidx.compose.ui.graphics.Color,
    val text3: androidx.compose.ui.graphics.Color,
    val accent: androidx.compose.ui.graphics.Color,
    val accentHover: androidx.compose.ui.graphics.Color,
    val accentSoft: androidx.compose.ui.graphics.Color,
    val accentGhost: androidx.compose.ui.graphics.Color,
    val positive: androidx.compose.ui.graphics.Color,
    val negative: androidx.compose.ui.graphics.Color,
    val warning: androidx.compose.ui.graphics.Color,
    val teal: androidx.compose.ui.graphics.Color,
    val sage: androidx.compose.ui.graphics.Color,
    val forest: androidx.compose.ui.graphics.Color
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

val LocalSanvyaColors = staticCompositionLocalOf { lightTokens }

@Composable
fun SanvyaTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val tokens = if (darkTheme) darkTokens else lightTokens

    // MaterialTheme wiring so standard Material 3 components (ripples, default
    // surfaces) land close to the design system too — screens should still
    // prefer LocalSanvyaColors.current for anything that needs to match web
    // exactly (this is the same relationship web's globals.css vars have to
    // its .card/.btn/.chip classes vs raw browser defaults).
    val colorScheme = if (darkTheme) {
        darkColorScheme(
            background = tokens.bg,
            surface = tokens.surface,
            primary = tokens.accent,
            onBackground = tokens.text,
            onSurface = tokens.text,
            error = tokens.negative,
        )
    } else {
        lightColorScheme(
            background = tokens.bg,
            surface = tokens.surface,
            primary = tokens.accent,
            onBackground = tokens.text,
            onSurface = tokens.text,
            error = tokens.negative,
        )
    }

    CompositionLocalProvider(LocalSanvyaColors provides tokens) {
        MaterialTheme(colorScheme = colorScheme, content = content)
    }
}
