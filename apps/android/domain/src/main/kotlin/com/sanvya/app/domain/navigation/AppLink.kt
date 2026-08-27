package com.sanvya.app.domain.navigation

/**
 * A web path, resolved to a destination both native apps can navigate to.
 *
 * Web hands links around as URLs -- `/budgets`, `/groups/<id>`,
 * `/search?q=Swiggy&type=expense` -- because on web the router IS the path.
 * Native has no such thing: Compose Navigation and SwiftUI each carry their own
 * route vocabulary, and neither is web's. Every place that receives a web path
 * therefore needs the same translation, and until now no such translation
 * existed, so both places that receive one -- the notification inbox and the
 * assistant's `<ui>` actions -- simply did nothing on tap.
 *
 * This is the translation, and it is deliberately in Domain rather than in
 * either app: the paths are web's, the set is closed, and a difference between
 * the two platforms in where `/friends` lands is a bug that no compiler would
 * catch. What stays per-platform is the LAST step -- [AppScreen] to a Compose
 * route string or a SwiftUI destination -- which is the only genuinely
 * per-platform part.
 *
 * Mirrors iOS's AppLink.swift; pinned by `applink.json`.
 */

/**
 * Every destination a web path can name.
 *
 * The names are web's routes, not Android's or iOS's, because the input is a
 * web path. Two of web's routes are redirects and are folded in here rather
 * than carried: `/subscriptions` redirects to `/recurring` and `/groups` to
 * `/friends`, and reproducing a redirect as a redirect on native would mean a
 * visible double-navigation for no reason.
 */
enum class AppScreen {
    DASHBOARD,
    ACCOUNTS,
    ACCOUNT_NEW,
    ACCOUNT_EDIT,
    TRANSACTIONS,
    TRANSACTION_NEW,
    TRANSACTION_EDIT,
    BUDGETS,
    GOALS,
    RECURRING,
    RECURRING_DIRECTION,
    LOANS,
    LOAN_DETAIL,
    INVESTMENTS,
    CARDS,
    SPLITS,
    GROUP_DETAIL,
    INSIGHTS,
    REFLECT,
    STATEMENTS,
    STATEMENTS_ANALYZE,
    RECEIPT_NEW,
    SEARCH,
    NOTIFICATIONS,
    ASSISTANT,
    HELP,
    SETTINGS,
    SETTINGS_DATA,
    SETTINGS_CATEGORIES,
    SETTINGS_LABELS,
    LOGIN,
}

/**
 * A resolved link.
 *
 * [id] is the record a detail route names (`/loans/<id>` -> the loan) or, for
 * [AppScreen.RECURRING_DIRECTION], the direction slug -- it is whatever the one
 * dynamic path segment held, unescaped.
 *
 * [query] is the decoded query string, kept as strings because that is what the
 * receiving screen's filter state is made of. Only [AppScreen.SEARCH] currently
 * reads it; it is carried for every screen because dropping it silently would
 * be worse than carrying something unused.
 */
data class AppLink(
    val screen: AppScreen,
    val id: String? = null,
    val query: Map<String, String> = emptyMap(),
)

/** The static paths, exactly as web's `app/` directory defines them. */
private val STATIC_PATHS: Map<String, AppScreen> = mapOf(
    "" to AppScreen.DASHBOARD,
    "accounts" to AppScreen.ACCOUNTS,
    "accounts/new" to AppScreen.ACCOUNT_NEW,
    "transactions" to AppScreen.TRANSACTIONS,
    "transactions/new" to AppScreen.TRANSACTION_NEW,
    "budgets" to AppScreen.BUDGETS,
    "goals" to AppScreen.GOALS,
    "recurring" to AppScreen.RECURRING,
    // `/subscriptions` is a server redirect to `/recurring` (web's own comment:
    // "kept so old links -- dashboard tiles, insights CTAs, bookmarks -- still
    // land"). The persona still advertises it, so it must resolve.
    "subscriptions" to AppScreen.RECURRING,
    "loans" to AppScreen.LOANS,
    "investments" to AppScreen.INVESTMENTS,
    "cards" to AppScreen.CARDS,
    "friends" to AppScreen.SPLITS,
    // `/groups` redirects to `/friends` -- "Groups and Splits were one screen's
    // worth of information split across two". `/groups/<id>` is NOT a redirect
    // and is handled below.
    "groups" to AppScreen.SPLITS,
    "insights" to AppScreen.INSIGHTS,
    "reflect" to AppScreen.REFLECT,
    "statements" to AppScreen.STATEMENTS,
    "statements/analyze" to AppScreen.STATEMENTS_ANALYZE,
    "receipts/new" to AppScreen.RECEIPT_NEW,
    "search" to AppScreen.SEARCH,
    "notifications" to AppScreen.NOTIFICATIONS,
    "assistant" to AppScreen.ASSISTANT,
    "help" to AppScreen.HELP,
    "settings" to AppScreen.SETTINGS,
    "settings/categories" to AppScreen.SETTINGS_CATEGORIES,
    "settings/labels" to AppScreen.SETTINGS_LABELS,
    "data" to AppScreen.SETTINGS_DATA,
    "login" to AppScreen.LOGIN,
)

/**
 * Resolve a web path.
 *
 * Returns null for anything that is not an in-app destination:
 *
 *  * an absolute URL (`https://...`) or a protocol-relative one (`//...`) --
 *    the persona says "never an external URL", and honouring one would take the
 *    user out of the app;
 *  * a path with no leading `/`, which on web would resolve relative to
 *    whatever page happened to be open and has no native meaning at all;
 *  * `/admin/*`, `/auth/*`, `/onboarding`, `/join/*` -- real web routes with no
 *    native destination, deliberately not guessed at;
 *  * anything else unrecognised, including `/cashflow` and `/templates`, which
 *    the assistant persona advertises and web does not implement (recorded as a
 *    web defect in PARITY_AUDIT; NOT fixed here, because the persona is
 *    generated from web's own text).
 *
 * A null result is a link that must not be offered, not one to render dead.
 */
fun parseAppLink(href: String): AppLink? {
    val raw = href.trim()
    if (!raw.startsWith("/") || raw.startsWith("//")) return null

    val noHash = raw.substringBefore('#')
    val pathPart = noHash.substringBefore('?')
    val queryPart = noHash.substringAfter('?', "")

    // Trailing and doubled slashes are the same page on web; a segment list
    // that drops empties says exactly that without a normalisation pass.
    val segments = pathPart.split('/').filter { it.isNotEmpty() }.map { decodeUriComponent(it) }
    val query = parseQuery(queryPart)
    val key = segments.joinToString("/")

    STATIC_PATHS[key]?.let { return AppLink(it, null, query) }

    return when {
        segments.size == 3 && segments[0] == "accounts" && segments[2] == "edit" ->
            AppLink(AppScreen.ACCOUNT_EDIT, segments[1], query)
        segments.size == 3 && segments[0] == "transactions" && segments[2] == "edit" ->
            AppLink(AppScreen.TRANSACTION_EDIT, segments[1], query)
        segments.size == 2 && segments[0] == "loans" ->
            AppLink(AppScreen.LOAN_DETAIL, segments[1], query)
        segments.size == 2 && segments[0] == "groups" ->
            AppLink(AppScreen.GROUP_DETAIL, segments[1], query)
        // `/recurring/<direction>` takes a SLUG, not an id, and web 404s on an
        // unknown one. Only the two slugs that exist resolve; anything else is
        // not a destination.
        segments.size == 2 && segments[0] == "recurring" && (segments[1] == "income" || segments[1] == "expense") ->
            AppLink(AppScreen.RECURRING_DIRECTION, segments[1], query)
        else -> null
    }
}

/**
 * `?a=1&b=hello%20world` -> `{a: "1", b: "hello world"}`.
 *
 * Deliberately `URLSearchParams`' rules and not a generic percent-decode: `+`
 * means a space in a query string (and only there), a key with no `=` maps to
 * the empty string, and a repeated key keeps the FIRST value because that is
 * what `params.get(k)` returns.
 */
private fun parseQuery(query: String): Map<String, String> {
    if (query.isEmpty()) return emptyMap()
    val out = LinkedHashMap<String, String>()
    for (pair in query.split('&')) {
        if (pair.isEmpty()) continue
        val name = decodeUriComponent(pair.substringBefore('=').replace('+', ' '))
        if (name.isEmpty()) continue
        val value = decodeUriComponent(pair.substringAfter('=', "").replace('+', ' '))
        if (!out.containsKey(name)) out[name] = value
    }
    return out
}

/**
 * Percent-decoding, by hand.
 *
 * `java.net.URLDecoder` is not available in the shared Domain sources, and its
 * behaviour differs anyway: it decodes `+` as a space unconditionally, which is
 * wrong in a PATH segment. A malformed escape is left literal rather than
 * throwing, matching `decodeURIComponent`'s failure being a caller problem
 * rather than a user-visible crash on a link the model wrote.
 */
private fun isHexDigit(c: Char): Boolean =
    c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F'

private fun decodeUriComponent(value: String): String {
    if (!value.contains('%')) return value
    val bytes = ArrayList<Byte>(value.length)
    var i = 0
    while (i < value.length) {
        val c = value[i]
        if (c == '%' && i + 2 < value.length && isHexDigit(value[i + 1]) && isHexDigit(value[i + 2])) {
            // Both digits checked explicitly: `toIntOrNull(16)` accepts a
            // leading sign, so "%-1" would decode to 0xFF here and to nothing
            // at all in Swift's UInt8 initialiser. Two ports, one behaviour.
            bytes.add(value.substring(i + 1, i + 3).toInt(16).toByte())
            i += 3
            continue
        }
        for (byte in c.toString().toByteArray(Charsets.UTF_8)) bytes.add(byte)
        i++
    }
    return String(bytes.toByteArray(), Charsets.UTF_8)
}
