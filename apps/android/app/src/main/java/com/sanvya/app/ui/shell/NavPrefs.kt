package com.sanvya.app.ui.shell

import android.content.Context
import android.content.SharedPreferences
import com.sanvya.app.theme.SanvyaIcons
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * Which destinations sit in the bottom bar's four customizable slots.
 *
 * A faithful port of `apps/web/src/navPrefs.ts`, down to the storage key
 * (`pc_bottomNav`) and the JSON-array shape, so the two never disagree about
 * what a saved preference means.
 */
data class NavCatalogItem(
    val id: String,
    val route: String,
    /** i18n key, e.g. "nav.transactions" — the same one web passes to `t()`. */
    val tkey: String,
    /** English fallback, matching web's second argument to `t()`. */
    val label: String,
    val glyph: String,
)

object NavPrefs : KoinComponent {

    /**
     * The 14 destinations eligible for a slot. Home and More are fixed and are
     * deliberately NOT in here, exactly as on web.
     */
    val CATALOG: List<NavCatalogItem> = listOf(
        NavCatalogItem("transactions", "transactions", "nav.transactions", "Transactions", SanvyaIcons.swapHoriz),
        NavCatalogItem("friends", "splits", "nav.friends", "Shared", SanvyaIcons.groups),
        NavCatalogItem("insights", "insights", "nav.insights", "Insights", SanvyaIcons.insights),
        NavCatalogItem("accounts", "accounts", "nav.accounts", "Accounts", SanvyaIcons.accountBalance),
        NavCatalogItem("budgets", "budgets", "nav.budgets", "Budgets", SanvyaIcons.donutSmall),
        NavCatalogItem("goals", "goals", "nav.goals", "Goals", SanvyaIcons.flag),
        NavCatalogItem("recurring", "recurring", "nav.recurring", "Recurring", SanvyaIcons.autorenew),
        NavCatalogItem("loans", "loans", "nav.loans", "Loans", SanvyaIcons.requestQuote),
        NavCatalogItem("investments", "investments", "nav.investments", "Investments", SanvyaIcons.trendingUp),
        NavCatalogItem("cards", "cards", "nav.cards", "Cards", SanvyaIcons.creditCard),
        NavCatalogItem("statements", "statements", "nav.statements", "Statements", SanvyaIcons.description),
        NavCatalogItem("search", "search", "nav.search", "Search", SanvyaIcons.search),
        NavCatalogItem("assistant", "assistant", "nav.assistant", "Ask Sanvya", SanvyaIcons.autoAwesome),
        NavCatalogItem("settings", "settings", "nav.settings", "Settings", SanvyaIcons.settings),
    )

    val DEFAULT_IDS = listOf("transactions", "accounts", "friends", "insights")
    const val SLOTS = 4

    private const val PREFS_NAME = "sanvya_prefs"
    private const val KEY = "pc_bottomNav"

    private val context: Context by inject()
    private val sharedPrefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val _ids: MutableStateFlow<List<String>> by lazy { MutableStateFlow(read()) }
    val ids: StateFlow<List<String>> get() = _ids

    fun setIds(ids: List<String>) {
        val clean = sanitize(ids)
        sharedPrefs.edit().putString(KEY, JSONArray(clean).toString()).apply()
        _ids.value = clean
    }

    fun itemsFor(ids: List<String>): List<NavCatalogItem> =
        ids.mapNotNull { id -> CATALOG.firstOrNull { it.id == id } }

    private fun read(): List<String> {
        val raw = sharedPrefs.getString(KEY, null) ?: return DEFAULT_IDS
        return try {
            val array = JSONArray(raw)
            sanitize((0 until array.length()).mapNotNull { array.optString(it, null) })
        } catch (_: Exception) {
            DEFAULT_IDS
        }
    }

    /**
     * Port of web's `sanitize()` — drop unknown ids, dedupe, take the first four,
     * fall back to the defaults when nothing survives, and **top up from the
     * defaults when the list is short**.
     *
     * That last step is not defensive padding. A preference saved before the bar
     * grew to four slots holds three ids, and rendering it as-is leaves one side
     * of the bar short — the lopsided layout this design replaced. Keep it.
     */
    fun sanitize(ids: List<String>): List<String> {
        val valid = ids.filter { id -> CATALOG.any { it.id == id } }
        val deduped = valid.distinct().take(SLOTS).toMutableList()
        if (deduped.isEmpty()) return DEFAULT_IDS
        for (id in DEFAULT_IDS) {
            if (deduped.size >= SLOTS) break
            if (id !in deduped) deduped.add(id)
        }
        return deduped
    }
}
