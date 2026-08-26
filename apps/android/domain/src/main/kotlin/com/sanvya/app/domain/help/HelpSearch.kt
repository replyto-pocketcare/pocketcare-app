package com.sanvya.app.domain.help

/**
 * The Help page's search, ported from apps/web/app/help/page.tsx's `useMemo`.
 *
 * An item matches when the needle appears anywhere in its question OR its
 * answer -- web concatenates the two with a space before testing, so a needle
 * spanning the join ("Sanvya? An") matches there and matches here. Preserved
 * rather than corrected: it is invisible in practice and diverging over it
 * would be worse than the quirk.
 *
 * A section with no surviving items is dropped entirely; a blank query returns
 * everything untouched.
 *
 * Mirrors apps/ios/Domain/Sources/Domain/HelpSearch.swift.
 */
fun filterHelp(sections: List<HelpSection>, query: String): List<HelpSection> {
    // `trim()` here where the taxonomy screens deliberately do NOT: web trims
    // this one (`query.trim().toLowerCase()`) and does not trim those.
    val needle = query.trim().lowercase()
    if (needle.isEmpty()) return sections
    return sections.mapNotNull { section ->
        val items = section.items.filter {
            (it.question + " " + it.answer).lowercase().contains(needle)
        }
        if (items.isEmpty()) null else section.copy(items = items)
    }
}
