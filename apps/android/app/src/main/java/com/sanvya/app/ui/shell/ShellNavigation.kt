package com.sanvya.app.ui.shell

import androidx.compose.runtime.staticCompositionLocalOf
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Navigate to an app route from inside a screen the nav graph never handed a
 * callback for.
 *
 * Set by [AppShell], which already owns `onNavigate`, and read by screens that
 * need a destination their own composable signature does not carry — the
 * dashboard's notification bell and Settings' "Create account to keep my data"
 * are both links on web (`<Link href=…>`), not props a parent passes down, so
 * making each one travel as a new parameter through the graph would put web's
 * ambient `next/link` behind three hand-wired callbacks.
 *
 * Same shape and the same reason as [LocalAddActionSetter] directly above it in
 * this package: the shell publishes, the page consumes.
 */
val LocalShellNavigate = staticCompositionLocalOf<(String) -> Unit> { {} }

/** The sections of the Settings page that something else can link INTO. */
object SettingsSection {
    /** Web's `/settings#problems` — the dead-letter queue panel. */
    const val PROBLEMS = "problems"
}

/**
 * The `#fragment` half of a deep link into Settings.
 *
 * Web's sync-problems banner pushes `/settings#problems` and the browser scrolls
 * the panel into view; there is no fragment on a native route, so the intent has
 * to travel beside the navigation. It is held here rather than passed as a route
 * argument because the Settings destination takes none, and adding one would
 * change the route string every other caller navigates to.
 *
 * One-shot on purpose: [consume] clears it the moment the scroll has happened,
 * so returning to Settings later does not silently jump the page again.
 */
object SettingsSectionRequest {
    private val _pending = MutableStateFlow<String?>(null)
    val pending: StateFlow<String?> = _pending.asStateFlow()

    fun request(section: String) { _pending.value = section }

    fun consume() { _pending.value = null }
}
