package com.sanvya.app.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 * One layer of a CSS box-shadow. Compose has no spread parameter, so
 * `spread` is carried through for the component layer to compensate with
 * (web's shadows use large negative spreads to keep a wide blur tight) rather
 * than being silently dropped here.
 */
data class SanvyaShadowLayer(
    val x: Dp,
    val y: Dp,
    val blur: Dp,
    val spread: Dp,
    val color: Color,
)

data class SanvyaShadow(val layers: List<SanvyaShadowLayer>)

object SanvyaLightShadows {
    val shadow = SanvyaShadow(listOf(
        SanvyaShadowLayer(x = 0.dp, y = 1.dp, blur = 2.dp, spread = 0.dp, color = Color(red = 0.1686f, green = 0.1529f, blue = 0.1373f, alpha = 0.0400f)),
        SanvyaShadowLayer(x = 0.dp, y = 12.dp, blur = 30.dp, spread = -20.dp, color = Color(red = 0.1686f, green = 0.1529f, blue = 0.1373f, alpha = 0.1600f)),
    ))
    val shadowLg = SanvyaShadow(listOf(
        SanvyaShadowLayer(x = 0.dp, y = 22.dp, blur = 48.dp, spread = -22.dp, color = Color(red = 0.1686f, green = 0.1529f, blue = 0.1373f, alpha = 0.3200f)),
    ))
    val shadowAccent = SanvyaShadow(listOf(
        SanvyaShadowLayer(x = 0.dp, y = 10.dp, blur = 24.dp, spread = -12.dp, color = Color(red = 0.6902f, green = 0.4157f, blue = 0.3098f, alpha = 0.9000f)),
    ))
}

object SanvyaDarkShadows {
    val shadow = SanvyaShadow(listOf(
        SanvyaShadowLayer(x = 0.dp, y = 1.dp, blur = 2.dp, spread = 0.dp, color = Color(red = 0.0000f, green = 0.0000f, blue = 0.0000f, alpha = 0.3000f)),
        SanvyaShadowLayer(x = 0.dp, y = 8.dp, blur = 24.dp, spread = -12.dp, color = Color(red = 0.0000f, green = 0.0000f, blue = 0.0000f, alpha = 0.5000f)),
    ))
    val shadowLg = SanvyaShadow(listOf(
        SanvyaShadowLayer(x = 0.dp, y = 24.dp, blur = 60.dp, spread = -20.dp, color = Color(red = 0.0000f, green = 0.0000f, blue = 0.0000f, alpha = 0.6000f)),
    ))
    val shadowAccent = SanvyaShadow(listOf(
        SanvyaShadowLayer(x = 0.dp, y = 10.dp, blur = 24.dp, spread = -12.dp, color = Color(red = 0.6902f, green = 0.4157f, blue = 0.3098f, alpha = 0.9000f)),
    ))
}
