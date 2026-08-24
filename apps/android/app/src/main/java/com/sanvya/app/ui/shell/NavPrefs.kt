package com.sanvya.app.ui.shell

import android.content.Context
import android.content.SharedPreferences
import com.sanvya.app.theme.SanvyaIcons
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import android.content.res.Resources
import com.sanvya.app.i18n.S

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
    val glyph: String,
    /**
     * How this item names itself.
     *
     * A function, not a string and not a string key. It used to be both: a
     * `tkey` of `"nav.transactions"` that nothing ever resolved, sitting beside
     * an English `label` that got rendered directly — so the app shipped
     * English to hi and nl while carrying the key that would have fixed it.
     *
     * Holding the typed accessor instead means a renamed key fails to compile
     * rather than falling back to English at runtime, and there is no second
     * string to keep in sync with the first.
     */
    val label: (Resources) -> String,
)

object NavPrefs : KoinComponent {

    /**
     * The 14 destinations eligible for a slot. Home and More are fixed and are
     * deliberately NOT in here, exactly as on web.
     */
    val CATALOG: List<NavCatalogItem> = listOf(
        NavCatalogItem("transactions", "transactions", SanvyaIcons.swapHoriz, S.Translation::navTransactions),
        NavCatalogItem("friends", "splits", SanvyaIcons.groups, S.Translation::navFriends),
        NavCatalogItem("insights", "insights", SanvyaIcons.insights, S.Translation::navInsights),
        NavCatalogItem("accounts", "accounts", SanvyaIcons.accountBalance, S.Translation::navAccounts),
        NavCatalogItem("budgets", "budgets", SanvyaIcons.donutSmall, S.Translation::navBudgets),
        NavCatalogItem("goals", "goals", SanvyaIcons.flag, S.Translation::navGoals),
        NavCatalogItem("recurring", "recurring", SanvyaIcons.autorenew, S.Translation::navRecurring),
        NavCatalogItem("loans", "loans", SanvyaIcons.requestQuote, S.Translation::navLoans),
        NavCatalogItem("investments", "investments", SanvyaIcons.trendingUp, S.Translation::navInvestments),
        NavCatalogItem("cards", "cards", SanvyaIcons.creditCard, S.Translation::navCards),
        NavCatalogItem("statements", "statements", SanvyaIcons.description, S.Translation::navStatements),
        NavCatalogItem("search", "search", SanvyaIcons.search, S.Translation::navSearch),
        NavCatalogItem("assistant", "assistant", SanvyaIcons.autoAwesome, S.Translation::navAssistant),
        NavCatalogItem("settings", "settings", SanvyaIcons.settings, S.Translation::navSettings),
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
