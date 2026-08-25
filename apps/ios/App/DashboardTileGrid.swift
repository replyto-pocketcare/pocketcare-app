import SwiftUI
import Domain

/**
 The dashboard tile grid — web's `.dash-grid`.

 Rows come from `packRows` in `Domain`, which both platforms share and which is
 vector-tested; this file only draws what that function decides. Widths become
 proportional frames inside an `HStack`, so a two-of-four tile really is half
 the row rather than a hardcoded fraction that stops being true when the column
 count changes.

 **Not a `LazyVGrid`.** SwiftUI's grid has no per-item column span, which is the
 whole reason the packing lives in `Domain` — see `TileGrid.swift`.

 **Column count.** Web is one column below 860px and four above. The native
 window classes break at 600 and 840, and inventing a fourth breakpoint for one
 screen would be worse than the 20pt of daylight between 840 and 860. So: one
 column until `.expanded`, four from there. An iPhone and a portrait iPad both
 stack, which is what web does at those widths too.

 Mirrors `apps/android/.../ui/dashboard/DashboardTileGrid.kt`.
 */
struct DashboardTileGrid: View {
    let editing: Bool
    let isPaid: Bool
    let onOpen: (NavTab) -> Void

    @Environment(\.sanvyaWindowClass) private var windowClass
    @ObservedObject private var prefs = DashboardPrefs.shared

    /// Measured once per layout pass.
    ///
    /// SwiftUI has no `weight` modifier: `.frame(maxWidth: .infinity)` divides a
    /// row EQUALLY, and `layoutPriority` decides who shrinks last, not who gets
    /// how much. A tile that is four columns wide beside one that is one has to
    /// be given an explicit width, so the row's width has to be known. Read
    /// through a background GeometryReader rather than wrapping the grid in one,
    /// because a GeometryReader claims all the height it is offered and the
    /// grid's height must come from its tiles.
    @State private var rowWidth: CGFloat = 0

    private static let gap: CGFloat = 20

    private var columns: Int { windowClass == .expanded ? 4 : 1 }

    /// `isBuilt` as well as the premium gate. The storage key is web's own, so
    /// a saved dashboard can legitimately name a tile this platform has not
    /// built yet; rendering it would produce an empty card, which is the dead
    /// control the picker is already careful to avoid offering.
    ///
    /// Premium tiles disappear for an unentitled user rather than rendering
    /// locked, mirroring web's `enabled.filter(isPaid || !premium)`. The id
    /// stays in storage, so the tile returns the moment they upgrade.
    private var visible: [TileId] {
        prefs.ids.filter { $0.isBuilt && (isPaid || !$0.isPremium) }
    }

    private func span(_ id: TileId) -> Int {
        min(max(1, prefs.width(of: id).columns), columns)
    }

    var body: some View {
        Group {
            if visible.isEmpty {
                emptyState
            } else {
                VStack(spacing: Self.gap) {
                    ForEach(rows, id: \.self) { row in
                        rowView(row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { rowWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, new in rowWidth = new }
            }
        )
    }

    @ViewBuilder
    private func rowView(_ row: [String]) -> some View {
        let ids = row.compactMap { TileId(rawValue: $0) }
        let used = ids.reduce(0) { $0 + span($1) }
        // Every gap in the row, including the one before the trailing filler,
        // so the columns still line up with the row above.
        let gaps = Self.gap * CGFloat(max(0, (used < columns ? ids.count : ids.count - 1)))
        let unit = rowWidth > 0 ? max(0, (rowWidth - gaps) / CGFloat(columns)) : 0

        HStack(alignment: .top, spacing: Self.gap) {
            ForEach(ids) { id in
                slot(id)
                    .frame(width: unit > 0 ? unit * CGFloat(span(id)) : nil)
                    .frame(maxWidth: unit > 0 ? nil : .infinity)
            }
            // Load-bearing. A row that does not fill its columns -- the gap
            // packRows deliberately leaves, since this is not `dense` -- must
            // keep that gap, or the tiles either stretch or re-centre and the
            // layout stops matching the one that was computed.
            if used < columns {
                Color.clear.frame(width: unit > 0 ? unit * CGFloat(columns - used) : nil, height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: [[String]] {
        packRows(visible.map { GridItem(id: $0.rawValue, columns: span($0)) }, columns: columns)
    }

    /// Nothing enabled. Not an error — the user can remove every tile.
    private var emptyState: some View {
        SanvyaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(S.Dashboard.emptyTitle)
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(Color.text)
                Text(S.Dashboard.emptyBody)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One tile, plus the controls that only exist while editing.
    @ViewBuilder
    private func slot(_ id: TileId) -> some View {
        let index = visible.firstIndex(of: id) ?? 0
        VStack(alignment: .leading, spacing: 8) {
            TileView(id: id, editing: editing, onOpen: { onOpen(id.destination) })
            if editing {
                HStack(spacing: 8) {
                    // Width first: it is the only control that does nothing on
                    // an iPhone, and putting it where the eye lands first would
                    // make a dead button the most prominent thing in edit mode.
                    if windowClass == .expanded {
                        editChip(S.Dashboard.width) { prefs.setWidth(id, prefs.width(of: id).next) }
                    }
                    if index > 0 {
                        editChip(S.Dashboard.moveUp) { prefs.move(id, by: -1) }
                    }
                    if index < visible.count - 1 {
                        editChip(S.Dashboard.moveDown) { prefs.move(id, by: 1) }
                    }
                    Spacer(minLength: 0)
                    editChip(S.Translation.commonRemove, destructive: true) { prefs.setEnabled(id, false) }
                }
            }
        }
    }

    private func editChip(_ label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        SanvyaButton(ghost: true, action: action) {
            Text(label).foregroundStyle(destructive ? Color.negative : Color.text)
        }
    }
}
