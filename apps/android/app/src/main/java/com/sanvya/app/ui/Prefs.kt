package com.sanvya.app.ui

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * Local-only device prefs — mirrors apps/web/src/prefs.ts's localStorage-backed
 * `useAmountsHidden`/`setAmountsHidden` (a plain boolean flag, default false,
 * same key name so the semantics match exactly; the storage mechanism differs
 * by platform, the persisted default doesn't). NOT synced (matches web: this
 * is a device preference, not ledger data).
 *
 * `SettingsScreen.kt` already referenced this object unqualified
 * (`Prefs.amountsHidden` / `Prefs.setAmountsHidden`) before this file existed
 * — verified 2026-08-05, another dangling reference alongside SanvyaTheme/
 * SanvyaNavHost/the missing Application class. This creates it for real.
 */
object Prefs : KoinComponent {
    private const val PREFS_NAME = "sanvya_prefs"
    private const val HIDE_KEY = "amountsHidden"

    private val context: Context by inject()

    private val sharedPrefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    // Backed by `by lazy` (not a top-level initializer) because Koin/Context
    // isn't available until the app has actually started.
    private val _amountsHidden: MutableStateFlow<Boolean> by lazy {
        MutableStateFlow(sharedPrefs.getBoolean(HIDE_KEY, false))
    }
    val amountsHidden: StateFlow<Boolean> get() = _amountsHidden

    fun setAmountsHidden(hidden: Boolean) {
        sharedPrefs.edit().putBoolean(HIDE_KEY, hidden).apply()
        _amountsHidden.value = hidden
    }
}
