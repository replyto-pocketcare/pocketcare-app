package com.sanvya.app.i18n

// GENERATED FILE — do not hand-edit.
// Source: packages/core/i18n/src/index.ts (SUPPORTED_LANGUAGES)
// Regenerate with: node tools/parity/generate-i18n.mjs

/**
 * One language the app ships strings for.
 *
 * [label] is the ENDONYM and is deliberately not translated: a picker that
 * names languages in the language you are trying to leave is a picker you
 * cannot use.
 */
data class SupportedLanguage(val code: String, val label: String, val rtl: Boolean)

/** Every language this build carries, source locale first. */
val SUPPORTED_LANGUAGES: List<SupportedLanguage> = listOf(
    SupportedLanguage("en", "English", rtl = false),
    SupportedLanguage("hi", "हिन्दी", rtl = false),
    SupportedLanguage("nl", "Nederlands", rtl = false),
)
