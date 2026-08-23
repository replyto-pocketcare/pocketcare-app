package com.sanvya.app.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextGeometricTransform
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 * Type scale. Sizes are `sp` so system font scaling works (an accessibility
 * requirement web gets for free from browser zoom); tracking is expressed in
 * `em` exactly as CSS `letter-spacing` is, so it scales with the size.
 *
 * `SanvyaFont.family` is wired in Theme.kt — Inter, bundled in res/font.
 */
object SanvyaType {
    val h1 = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 26.sp,
        fontWeight = FontWeight(700),
        letterSpacing = -0.02.em,
    )

    val h1Compact = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 22.sp,
        fontWeight = FontWeight(700),
        letterSpacing = -0.02.em,
    )

    val h2 = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 18.sp,
        fontWeight = FontWeight(650),
        letterSpacing = -0.01.em,
    )

    val eyebrow = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 11.sp,
        fontWeight = FontWeight(600),
        letterSpacing = 0.09.em,
    )

    val sideNavItem = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 13.5.sp,
        fontWeight = FontWeight(500),
        letterSpacing = 0.em,
    )

    val sideNavItemActive = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 13.5.sp,
        fontWeight = FontWeight(650),
        letterSpacing = 0.em,
    )

    val sideNavTitle = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 10.5.sp,
        fontWeight = FontWeight(600),
        letterSpacing = 0.07.em,
    )

    val sideNavSearch = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 13.sp,
        fontWeight = FontWeight(400),
        letterSpacing = 0.em,
    )

    val sideNavBadge = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 10.5.sp,
        fontWeight = FontWeight(700),
        letterSpacing = 0.em,
    )

    val sideNavGuest = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 12.5.sp,
        fontWeight = FontWeight(400),
        letterSpacing = 0.em,
    )

    val sideNavVersion = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 11.sp,
        fontWeight = FontWeight(400),
        letterSpacing = 0.em,
    )

    val body = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 15.sp,
        fontWeight = FontWeight(400),
        letterSpacing = 0.em,
    )

    val chip = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 14.sp,
        fontWeight = FontWeight(400),
        letterSpacing = 0.em,
    )

    val button = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 15.sp,
        fontWeight = FontWeight(600),
        letterSpacing = 0.em,
    )

    val navLabel = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 10.sp,
        fontWeight = FontWeight(600),
        letterSpacing = 0.em,
    )

    val statValue = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 26.sp,
        fontWeight = FontWeight(700),
        letterSpacing = -0.02.em,
    )

    val statLabel = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 13.sp,
        fontWeight = FontWeight(600),
        letterSpacing = 0.em,
    )

    val sectionTitle = TextStyle(
        fontFamily = SanvyaFont.family,
        fontSize = 10.5.sp,
        fontWeight = FontWeight(600),
        letterSpacing = 0.07.em,
    )
}

/** Which styles render uppercase on web (`text-transform: uppercase`). */
object SanvyaTypeUppercase {
    const val h1 = false
    const val h1Compact = false
    const val h2 = false
    const val eyebrow = true
    const val sideNavItem = false
    const val sideNavItemActive = false
    const val sideNavTitle = true
    const val sideNavSearch = false
    const val sideNavBadge = false
    const val sideNavGuest = false
    const val sideNavVersion = false
    const val body = false
    const val chip = false
    const val button = false
    const val navLabel = false
    const val statValue = false
    const val statLabel = false
    const val sectionTitle = true
}
