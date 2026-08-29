package com.sanvya.app.ui.shell

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * Whether the one-time trial welcome dialog has been shown to this account.
 *
 * Keyed by email, exactly as web's `trialWelcomeSeenKey` is
 * (`sanvya:trial-welcome:<email>`, `"anon"` when there is none), so the two
 * clients mean the same thing by it. Signing in as somebody else is a different
 * key and therefore a different first run -- which is the point of keying it at
 * all.
 *
 * Same `sanvya_prefs` file and the same Koin-injected-SharedPreferences shape as
 * [NavPrefs] and `DashboardPrefs`. Device-local, never synced: it records that a
 * dialog was dismissed on this device, not anything about the account.
 */
object TrialPrefs : KoinComponent {

    private const val PREFS_NAME = "sanvya_prefs"

    private val context: Context by inject()
    private val sharedPrefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /** Web's `trialWelcomeSeenKey(email)`, character for character. */
    private fun key(email: String?): String = "sanvya:trial-welcome:${email ?: "anon"}"

    /**
     * Bumped on every write so a composable observing this object recomposes.
     *
     * The value itself is per-email and so cannot be a single StateFlow<Boolean>
     * without pinning it to one account; a revision counter is the smallest
     * thing that lets [seen] stay a plain lookup and still be reactive.
     */
    private val _revision = MutableStateFlow(0)
    val revision: StateFlow<Int> get() = _revision

    fun seen(email: String?): Boolean = sharedPrefs.getBoolean(key(email), false)

    fun markSeen(email: String?) {
        sharedPrefs.edit().putBoolean(key(email), true).apply()
        _revision.value = _revision.value + 1
    }
}
