package com.sanvya.app.domain.navigation

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Wires parseAppLink into FunctionRegistry.
//
// These vectors are a SPEC, not a capture. There is no web function to run:
// on web the router IS the path, so the "expected" behaviour lives in the
// `app/` directory's shape, in two redirect files, and in the search page's
// prefill effect. Each vector was written against that source -- the static
// table is `find apps/web/app -name page.tsx`, the two redirects are
// `/subscriptions` and `/groups`, and the query rules are URLSearchParams' --
// so a passing run proves Android and iOS agree with each other and with what
// was read off web, not that a browser was observed doing it.
//
// The refusals matter as much as the resolutions. `/cashflow` and `/templates`
// are advertised in the assistant persona and do not exist on web; they are
// pinned as null here so that a later "fix" that invents a native destination
// for them fails loudly instead of quietly sending users somewhere web never
// would.

private const val DOMAIN = "applink"

fun registerAppLinkVectors() {
    FunctionRegistry.register(DOMAIN, "parseAppLink") { input ->
        val href = input.jsonObject.getValue("href").jsonPrimitive.content
        when (val link = parseAppLink(href)) {
            null -> JsonNull
            else -> JsonObject(
                buildMap {
                    put("screen", JsonPrimitive(link.screen.name))
                    // Absent, not null, when the route has no dynamic segment --
                    // the fixture is written the way JSON.stringify would emit it.
                    link.id?.let { put("id", JsonPrimitive(it)) }
                    put("query", JsonObject(link.query.mapValues { (_, v) -> JsonPrimitive(v) }))
                },
            )
        }
    }
}
