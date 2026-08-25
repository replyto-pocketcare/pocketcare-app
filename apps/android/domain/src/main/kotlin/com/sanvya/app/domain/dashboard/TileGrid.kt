package com.sanvya.app.domain.dashboard

/**
 * One tile's claim on a row: which tile, and how many columns it wants.
 */
data class GridItem(val id: String, val columns: Int)

/**
 * Packs dashboard tiles into rows.
 *
 * Web lays the dashboard out with CSS grid and lets the browser do this. There
 * is no equivalent to lean on natively — `LazyVerticalGrid` takes per-item
 * spans but the SwiftUI counterpart does not, so a shared, vector-tested
 * function is the only way the two platforms can be made to agree. It lives in
 * `domain` for that reason: it is arithmetic, not layout.
 *
 * **This is `grid-auto-flow: row`, NOT `row dense`, and web sets `dense`.**
 * That is a deliberate, recorded divergence. Dense back-fills a gap with a
 * later, smaller tile — so on a wide screen a tile the user dragged to the
 * bottom can jump to the top of the page because something above it happened
 * to be four columns wide. On a screen whose entire point is that the user
 * chooses the order, silently reordering it is the wrong behaviour, and
 * reproducing it would also make the drag-to-reorder preview lie about where a
 * tile will land. Both platforms keep the user's order and leave the gap.
 *
 * Also absent, and not by choice: web gives each tile a **measured** row span
 * (`grid-auto-rows: 8px` plus a `ResizeObserver` on every tile body). That
 * depends on measuring rendered CSS pixels, which neither Compose nor SwiftUI
 * can do before layout. Native rows size to their tallest tile instead — which
 * is why native tiles do not need web's `useFitRows()` clipping.
 */
fun packRows(items: List<GridItem>, columns: Int): List<List<String>> {
    // A caller that asks for zero columns has a bug, but a dashboard that
    // renders nothing is a worse answer than one narrow column.
    val width = if (columns < 1) 1 else columns
    val rows = mutableListOf<List<String>>()
    var current = mutableListOf<String>()
    var used = 0

    for (item in items) {
        // A tile wider than the grid is clamped, never dropped and never
        // allowed to overflow: at one column every tile claims the whole row.
        // A width of zero would pack forever, so it counts as one.
        val span = item.columns.coerceIn(1, width)
        if (used + span > width && current.isNotEmpty()) {
            rows.add(current)
            current = mutableListOf()
            used = 0
        }
        current.add(item.id)
        used += span
        if (used >= width) {
            rows.add(current)
            current = mutableListOf()
            used = 0
        }
    }
    if (current.isNotEmpty()) rows.add(current)
    return rows
}
