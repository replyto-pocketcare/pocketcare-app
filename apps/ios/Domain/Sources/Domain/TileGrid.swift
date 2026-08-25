import Foundation

/// One tile's claim on a row: which tile, and how many columns it wants.
public struct GridItem: Sendable, Equatable {
    public let id: String
    public let columns: Int

    public init(id: String, columns: Int) {
        self.id = id
        self.columns = columns
    }
}

/**
 Packs dashboard tiles into rows.

 Web lays the dashboard out with CSS grid and lets the browser do this. There is
 no equivalent to lean on natively — `LazyVerticalGrid` takes per-item spans but
 `LazyVGrid` does not, so a shared, vector-tested function is the only way the
 two platforms can be made to agree. It lives in `Domain` for that reason: it is
 arithmetic, not layout.

 **This is `grid-auto-flow: row`, NOT `row dense`, and web sets `dense`.** That
 is a deliberate, recorded divergence. Dense back-fills a gap with a later,
 smaller tile — so on a wide screen a tile the user dragged to the bottom can
 jump to the top of the page because something above it happened to be four
 columns wide. On a screen whose entire point is that the user chooses the
 order, silently reordering it is the wrong behaviour, and reproducing it would
 also make the drag-to-reorder preview lie about where a tile will land. Both
 platforms keep the user's order and leave the gap.

 Also absent, and not by choice: web gives each tile a **measured** row span
 (`grid-auto-rows: 8px` plus a `ResizeObserver` on every tile body). That
 depends on measuring rendered CSS pixels, which neither SwiftUI nor Compose can
 do before layout. Native rows size to their tallest tile instead — which is why
 native tiles do not need web's `useFitRows()` clipping.
 */
public func packRows(_ items: [GridItem], columns: Int) -> [[String]] {
    // A caller that asks for zero columns has a bug, but a dashboard that
    // renders nothing is a worse answer than one narrow column.
    let width = max(1, columns)
    var rows: [[String]] = []
    var current: [String] = []
    var used = 0

    for item in items {
        // A tile wider than the grid is clamped, never dropped and never
        // allowed to overflow: at one column every tile claims the whole row.
        // A width of zero would pack forever, so it counts as one.
        let span = min(max(1, item.columns), width)
        if used + span > width, !current.isEmpty {
            rows.append(current)
            current = []
            used = 0
        }
        current.append(item.id)
        used += span
        if used >= width {
            rows.append(current)
            current = []
            used = 0
        }
    }
    if !current.isEmpty { rows.append(current) }
    return rows
}
