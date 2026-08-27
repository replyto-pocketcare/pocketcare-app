package com.sanvya.app.ui.navigation

import android.net.Uri
import com.sanvya.app.domain.navigation.AppLink
import com.sanvya.app.domain.navigation.AppScreen
import com.sanvya.app.domain.navigation.parseAppLink

/**
 * The last step of the web-path translation: [AppLink] to a Compose route.
 *
 * Everything ABOVE this -- which path means which screen, what the query
 * decodes to, which paths are refused -- is Domain's and is shared with iOS.
 * What is here is only the part that genuinely cannot be shared: the route
 * strings this app's `NavHost` was built with.
 *
 * The table is exhaustive over [AppScreen] on purpose (no `else` branch), so
 * adding a destination to Domain fails the Android build until this app decides
 * where it goes, instead of silently returning null and producing a dead link.
 */

/** The search route's optional arguments, in the order the route declares them. */
internal val SEARCH_ARGS = listOf("q", "type", "account", "from", "to", "min", "max")

/** The `search` destination's route pattern, with every filter optional. */
internal val SEARCH_ROUTE: String =
    "search?" + SEARCH_ARGS.joinToString("&") { "$it={$it}" }

/**
 * A route string for [link], or null when this app has no destination for it.
 *
 * Null is currently unreachable -- every [AppScreen] maps -- and is kept as the
 * return type anyway so that the day one does not (a screen that exists on web
 * and iOS but not yet here), the call sites already handle it.
 */
fun routeFor(link: AppLink): String? {
    val id = link.id?.let { Uri.encode(it) }
    return when (link.screen) {
        AppScreen.DASHBOARD -> "dashboard"
        AppScreen.ACCOUNTS -> "accounts"
        AppScreen.ACCOUNT_NEW -> "accounts/new"
        AppScreen.ACCOUNT_EDIT -> id?.let { "accounts/$it/edit" }
        AppScreen.TRANSACTIONS -> "transactions"
        AppScreen.TRANSACTION_NEW -> "transactions/new"
        AppScreen.TRANSACTION_EDIT -> id?.let { "transactions/$it/edit" }
        AppScreen.BUDGETS -> "budgets"
        AppScreen.GOALS -> "goals"
        AppScreen.RECURRING -> "recurring"
        AppScreen.RECURRING_DIRECTION -> id?.let { "recurring/$it" }
        AppScreen.LOANS -> "loans"
        AppScreen.LOAN_DETAIL -> id?.let { "loans/$it" }
        AppScreen.INVESTMENTS -> "investments"
        AppScreen.CARDS -> "cards"
        // Web's Splits screen is `/friends`; this app's route is `splits`.
        AppScreen.SPLITS -> "splits"
        AppScreen.GROUP_DETAIL -> id?.let { "splits/$it" }
        AppScreen.INSIGHTS -> "insights"
        AppScreen.REFLECT -> "reflect"
        AppScreen.STATEMENTS -> "statements"
        AppScreen.STATEMENTS_ANALYZE -> "statements/analyze"
        AppScreen.RECEIPT_NEW -> "receipts/new"
        AppScreen.SEARCH -> searchRoute(link.query)
        AppScreen.NOTIFICATIONS -> "notifications"
        AppScreen.ASSISTANT -> "assistant"
        AppScreen.HELP -> "help"
        AppScreen.SETTINGS -> "settings"
        AppScreen.SETTINGS_DATA -> "settings/data"
        AppScreen.SETTINGS_CATEGORIES -> "settings/categories"
        AppScreen.SETTINGS_LABELS -> "settings/labels"
        AppScreen.LOGIN -> "login"
    }
}

/** Convenience for the two callers that hold a raw web path. */
fun routeForHref(href: String): String? = parseAppLink(href)?.let(::routeFor)

/**
 * `search?q=Swiggy&type=expense`.
 *
 * Only the parameters the Search screen reads are carried; anything else the
 * link happened to hold is dropped here rather than in Domain, because it is
 * this app's route that cannot express it. Values are re-encoded: they arrive
 * already decoded, and a raw `&` or `#` in a search term would otherwise split
 * the route.
 */
private fun searchRoute(query: Map<String, String>): String {
    val parts = SEARCH_ARGS.mapNotNull { key ->
        val value = query[key]
        if (value.isNullOrEmpty()) null else "$key=${Uri.encode(value)}"
    }
    return if (parts.isEmpty()) "search" else "search?" + parts.joinToString("&")
}
