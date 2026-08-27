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
    private const val WALKTHROUGH_DONE_KEY = "sanvya:walkthroughDone"
    private const val HIDE_KEY = "amountsHidden"
    private const val THEME_KEY = "theme"
    private const val CURRENCY_KEY = "baseCurrency"
    private const val DEFAULT_THEME = "light"
    private const val DEFAULT_CURRENCY = FormOptions.DEFAULT_CURRENCY

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

    /**
     * "light" | "dark" -- mirrors apps/web/src/theme.ts's localStorage-backed
     * useTheme/setTheme (same key name, same default). Settings-screen only
     * for now: nothing else in the app reads this yet to switch
     * MaterialTheme's color scheme -- that propagation is a follow-up (see
     * AUDIT_HISTORY.md, Settings entry).
     */
    private val _theme: MutableStateFlow<String> by lazy {
        MutableStateFlow(sharedPrefs.getString(THEME_KEY, DEFAULT_THEME) ?: DEFAULT_THEME)
    }
    val theme: StateFlow<String> get() = _theme

    fun setTheme(value: String) {
        sharedPrefs.edit().putString(THEME_KEY, value).apply()
        _theme.value = value
    }

    /**
     * Mirrors apps/web/src/prefs.ts's useBaseCurrency/setBaseCurrency (same
     * key, same default). Read through `baseCurrencyNow()` in MoneyFormat.kt by
     * everything that rolls up across accounts — net worth, portfolio
     * subtotals, insights, a cross-group split position. It was write-only
     * until 2026-08-23: eleven screens hardcoded INR, so choosing USD in
     * Settings changed nothing anywhere.
     */
    private val _baseCurrency: MutableStateFlow<String> by lazy {
        MutableStateFlow(sharedPrefs.getString(CURRENCY_KEY, DEFAULT_CURRENCY) ?: DEFAULT_CURRENCY)
    }
    val baseCurrency: StateFlow<String> get() = _baseCurrency

    fun setBaseCurrency(value: String) {
        sharedPrefs.edit().putString(CURRENCY_KEY, value).apply()
        _baseCurrency.value = value
    }

    /**
     * First-run walkthrough, closed for good.
     *
     * Same key string as web's localStorage entry (`sanvya:walkthroughDone`) so
     * the two clients mean the same thing by it, even though the stores differ.
     * Its sibling — "skipped" — is deliberately NOT here: web keeps that one in
     * `sessionStorage`, because skipping is "not now", and someone who taps it
     * while still having no account should meet the walkthrough again next
     * launch. That flag lives in the gate's own memory instead, which is the
     * same lifetime.
     */
    private val _walkthroughDone: MutableStateFlow<Boolean> by lazy {
        MutableStateFlow(sharedPrefs.getBoolean(WALKTHROUGH_DONE_KEY, false))
    }
    val walkthroughDone: StateFlow<Boolean> get() = _walkthroughDone

    fun setWalkthroughDone() {
        sharedPrefs.edit().putBoolean(WALKTHROUGH_DONE_KEY, true).apply()
        _walkthroughDone.value = true
    }
}
