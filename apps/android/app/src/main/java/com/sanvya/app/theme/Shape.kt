package com.sanvya.app.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 * Corner radii. `pill` is CSS's 999px idiom — a capsule — and is expressed as
 * a 50% shape so it stays a capsule at any height, which a literal 999.dp
 * would not on a short element.
 */
object SanvyaRadius {
    val radius = 22.dp
    val radiusLg = 24.dp
    val radiusSm = 12.dp
    val row = 10.dp
    val popover = 18.dp
    val popoverItem = 12.dp
    val checkbox = 6.dp
}

object SanvyaShape {
    val radius = RoundedCornerShape(SanvyaRadius.radius)
    val radiusLg = RoundedCornerShape(SanvyaRadius.radiusLg)
    val radiusSm = RoundedCornerShape(SanvyaRadius.radiusSm)
    val row = RoundedCornerShape(SanvyaRadius.row)
    val popover = RoundedCornerShape(SanvyaRadius.popover)
    val popoverItem = RoundedCornerShape(SanvyaRadius.popoverItem)
    val checkbox = RoundedCornerShape(SanvyaRadius.checkbox)
    val pill = RoundedCornerShape(percent = 50)
}
