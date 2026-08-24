package com.sanvya.app.theme

import androidx.compose.animation.core.CubicBezierEasing

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 * Motion. Web uses `cubic-bezier(0.2, 0, 0, 1)` for essentially every
 * meaningful transition; that curve is `standard` here.
 */
object SanvyaMotion {
    val standard = CubicBezierEasing(0.2f, 0f, 0f, 1f)

    const val pressScale = 0.97f
    const val pressDurationMs = 120

    const val liftPressScale = 0.985f
    const val liftPressDurationMs = 80

    const val pageInDurationMs = 340
    const val pageInTranslateY = 10

    const val fadeUpDurationMs = 400
    const val fadeUpTranslateY = 8

    const val shimmerDurationMs = 1400
    const val colorFadeDurationMs = 150
}
