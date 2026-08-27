package com.sanvya.app.ui.onboarding

// GENERATED FILE - do not hand-edit.
// Source: apps/web/app/onboarding/page.tsx (SLIDES)
// Regenerate with: node tools/parity/generate-onboarding-slides.mjs

import android.content.res.Resources
import androidx.compose.ui.graphics.Color
import com.sanvya.app.i18n.S
import com.sanvya.app.ui.parseHexColor

/**
 * The pre-auth onboarding deck's visual identity, exactly as web writes it.
 * 
 * Glyph and gradient only: each slide's title and body are i18n keys
 * (onboarding:slides.N.title / .body) and arrive through the generated
 * strings, so this file has no copy in it and needs no translation.
 * 
 * The gradient stops are stored as the #rrggbb strings web writes and
 * converted by the platform's own hex parser -- the one every account and
 * chart colour already goes through. A second colour constructor here would
 * be a second place for #RGB shorthand or a bad digit to behave differently.
 */
data class OnboardingSlide(
    val glyph: String,
    val gradientStartHex: String,
    val gradientEndHex: String,
) {
    val gradientStart: Color get() = parseHexColor(gradientStartHex)
    val gradientEnd: Color get() = parseHexColor(gradientEndHex)
}

object OnboardingSlides {
    /**
     * Every slide's title, in order, resolved through the generated strings.
     *
     * Emitted rather than hand-written because S.Onboarding's accessors are
     * flat (slides0Title, slides1Title, ...) with no way to index them: a
     * hand-written when-expression would be the one place an eighth slide gets
     * forgotten. The generator has already failed if a key is missing.
     */
    fun titles(res: Resources): List<String> = listOf(
        S.Onboarding.slides0Title(res),
        S.Onboarding.slides1Title(res),
        S.Onboarding.slides2Title(res),
        S.Onboarding.slides3Title(res),
        S.Onboarding.slides4Title(res),
        S.Onboarding.slides5Title(res),
        S.Onboarding.slides6Title(res),
    )

    fun bodies(res: Resources): List<String> = listOf(
        S.Onboarding.slides0Body(res),
        S.Onboarding.slides1Body(res),
        S.Onboarding.slides2Body(res),
        S.Onboarding.slides3Body(res),
        S.Onboarding.slides4Body(res),
        S.Onboarding.slides5Body(res),
        S.Onboarding.slides6Body(res),
    )

    val slides: List<OnboardingSlide> = listOf(
        OnboardingSlide("\u2764", "#b06a4f", "#8f533c"),
        OnboardingSlide("\u2302", "#3e4a38", "#2f6f6a"),
        OnboardingSlide("\u21C5", "#7a4a6b", "#4f3a54"),
        OnboardingSlide("\u25D4", "#c08a3e", "#a8503a"),
        OnboardingSlide("\u21CC", "#b06a4f", "#5f6647"),
        OnboardingSlide("\u25CE", "#2f6f6a", "#3e4a38"),
        OnboardingSlide("\u2726", "#7c4a3a", "#b06a4f"),
    )
}
