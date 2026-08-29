package com.sanvya.app.i18n

import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.content.res.Resources
import androidx.compose.runtime.compositionLocalOf
import java.util.Locale

/**
 * The app's chosen language.
 *
 * ## Why this is nine lines and not a dependency
 *
 * The platform answer is `AppCompatDelegate.setApplicationLocales`, which needs
 * `androidx.appcompat` — a dependency this app does not have and does not
 * otherwise want, since every screen is Compose. The framework's own
 * `LocaleManager` is API 33+, and `minSdk` here is 26, so on most devices in
 * this app's market it would be a setting that silently does nothing.
 *
 * Neither is necessary, because of a decision made much earlier: **`S.kt`
 * accessors take a `Resources` explicitly.** Every translated string in the app
 * arrives through `sRes()`. Overriding what that one function returns overrides
 * the entire catalogue, with no dependency, no manifest entry, and no API-level
 * floor.
 *
 * That is the same shape as the iOS fix — there the seam is the `bundle:`
 * argument the generator now emits, here it is the `Resources` argument it
 * already emitted. Neither platform needed a screen to know anything.
 *
 * ## Null means the system
 *
 * The default, and the only state a fresh install is in. A user who has never
 * touched this follows the phone, which is what they expect and what every
 * other app does.
 */
val LocalAppLocale = compositionLocalOf<String?> { null }

/**
 * How a screen changes the language.
 *
 * A setter rather than a `MutableState`, so the state itself stays owned by the
 * one place that can hold it across the whole tree. Settings calls this; nothing
 * else should need to.
 */
val LocalLanguageSetter = compositionLocalOf<(String?) -> Unit> { {} }

/**
 * `Resources` bound to [code], or the caller's own when [code] is null.
 *
 * `createConfigurationContext` rather than the deprecated
 * `Resources.updateConfiguration`: the latter mutates the shared, process-wide
 * `Resources` object, so it would change the language of every other
 * `Resources` handle in the app as a side effect — including ones held by
 * view models that were handed theirs earlier.
 */
fun localizedResources(context: Context, code: String?): Resources {
    if (code.isNullOrBlank()) return context.resources
    val base = context.resources.configuration
    val key = CacheKey(code, base)
    cache[key]?.let { return it }
    val config = Configuration(base)
    config.setLocale(Locale.forLanguageTag(code))
    val resources = context.createConfigurationContext(config).resources
    cache[key] = resources
    return resources
}

/**
 * Memoised, because `sRes()` is `@ReadOnlyComposable` and therefore cannot
 * `remember`.
 *
 * Without this, every string read with an override active allocates a
 * `Configuration` and a whole `ContextImpl`. `TileViews.kt` calls `sRes()`
 * fifty-two times and `CreditCardsScreen.kt` thirty-eight, so that is dozens of
 * context allocations per recomposition, on the scroll path. Correct either
 * way; jank one way.
 *
 * Keyed on the base configuration as well as the code, so a rotation, a theme
 * change or a font-scale change produces a fresh `Resources` rather than one
 * carrying the old configuration. `Configuration` has value equality, which is
 * what makes that cheap.
 */
private data class CacheKey(val code: String, val base: Configuration)

private val cache = mutableMapOf<CacheKey, Resources>()

/**
 * The stored choice. `null` = follow the system.
 *
 * Web stores the same thing under `i18nextLng`; this is deliberately NOT that
 * name, because the two clients do not share storage and a matching name would
 * invite someone to assume they do.
 */
object LanguagePrefs {
    private const val PREFS = "sanvya_prefs"
    private const val KEY = "pc_language"

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun read(context: Context): String? = prefs(context).getString(KEY, null)

    fun write(context: Context, code: String?) {
        prefs(context).edit().apply {
            if (code == null) remove(KEY) else putString(KEY, code)
        }.apply()
    }

}
