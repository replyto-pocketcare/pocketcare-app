package com.sanvya.app.domain.taxonomy

/**
 * The Manage-categories tree, ported from apps/web/app/settings/categories/page.tsx.
 *
 * Web computes this inline in its render. It is branchy enough that two
 * platforms would drift on it -- three of the four branches only appear while
 * something is typed in the search box -- so it lives here with vectors.
 * Mirrors apps/ios/Domain/Sources/Domain/CategoryTree.swift.
 */

/** One `categories` row, as the taxonomy screen reads it. */
data class TaxonomyCategory(
    val id: String,
    val name: String,
    val kind: String,
    val parentId: String?,
)

/** One top-level row plus the children that should be drawn under it. */
data class CategoryTreeNode(
    val category: TaxonomyCategory,
    /** ALL children, for the "· N" badge -- not just the visible ones. */
    val childCount: Int,
    val isOpen: Boolean,
    val children: List<TaxonomyCategory>,
)

/**
 * Web's four rules, in web's order:
 *
 * 1. A parent is hidden entirely when a search matches neither it nor any of
 *    its children.
 * 2. While searching, every surviving parent is FORCED open -- otherwise a
 *    match inside a collapsed parent would be invisible and the search would
 *    look broken.
 * 3. A parent that matches the search itself shows all its children, not just
 *    the matching ones: you searched for the group, so you get the group.
 * 4. A parent that does NOT match but has matching children shows only those.
 *
 * `search` is compared case-insensitively, as a substring, and an all-whitespace
 * search is a real search -- web tests `!search`, so only the empty string
 * turns filtering off. Copied deliberately; trimming here would make the two
 * platforms disagree with the browser about a space.
 */
fun categoryTree(
    categories: List<TaxonomyCategory>,
    search: String,
    expanded: Set<String>,
): List<CategoryTreeNode> {
    val needle = search.lowercase()
    val searching = search.isNotEmpty()
    fun matches(name: String) = !searching || name.lowercase().contains(needle)

    val childrenByParent = categories.filter { it.parentId != null }.groupBy { it.parentId!! }

    return categories.filter { it.parentId == null }.mapNotNull { parent ->
        val kids = childrenByParent[parent.id].orEmpty()
        val parentMatch = matches(parent.name)
        val matchingKids = kids.filter { matches(it.name) }
        if (searching && !parentMatch && matchingKids.isEmpty()) return@mapNotNull null
        CategoryTreeNode(
            category = parent,
            childCount = kids.size,
            isOpen = if (searching) true else expanded.contains(parent.id),
            children = if (searching && !parentMatch) matchingKids else kids,
        )
    }
}
