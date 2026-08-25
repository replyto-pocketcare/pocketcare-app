import SwiftUI
import Domain

/**
 Which tiles actually render something.

 The `switch` has **no `default` branch**, and that is the guard: `TileId` is
 generated from web's catalog, so the day a fifteenth tile appears there this
 file stops compiling until somebody decides whether it is built. The
 Add-a-widget picker reads this same property, so it is structurally impossible
 for the picker to offer a tile that renders an empty card — the dead control
 this audit keeps finding.

 Mirrors `apps/android/.../ui/dashboard/TileViews.kt`.
 */
extension TileId {
    var isBuilt: Bool {
        switch self {
        case .recent, .spending, .upcoming: return true
        case .trends, .splits, .budgets, .goals, .subscriptions, .cashflow,
             .netTrend, .byCategory, .byLabel, .monthCompare, .currencies: return false
        }
    }
}

/// One tile's content.
///
/// Each tile owns its own data, exactly as web does — every tile in `tiles.tsx`
/// runs its own `useQuery`. A tile the user has not enabled is never built, so
/// its query never runs, which is what lets the catalog hold fourteen.
struct TileView: View {
    let id: TileId
    let editing: Bool
    let onOpen: () -> Void

    var body: some View {
        // While editing, the tile is drawn but not tappable, mirroring web's
        // `pointer-events: none` on the tile body. A tap during edit belongs to
        // the move/remove controls, never to whatever is underneath them.
        let open: (() -> Void)? = editing ? nil : onOpen
        switch id {
        case .recent: RecentTile(onOpen: open)
        case .spending: SpendingTile(onOpen: open)
        case .upcoming: UpcomingTile(onOpen: open)
        default: EmptyView()
        }
    }
}

private struct TileShell<Trailing: View, Content: View>: View {
    let title: String
    let onOpen: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        SanvyaCard(padding: 20, action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    SanvyaEyebrow(title)
                    Spacer(minLength: 0)
                    trailing()
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension TileShell where Trailing == EmptyView {
    init(title: String, onOpen: (() -> Void)?, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, onOpen: onOpen, trailing: { EmptyView() }, content: content)
    }
}

private struct TileEmpty: View {
    let text: String
    var body: some View {
        Text(text)
            .sanvyaStyle(SanvyaType.statLabel)
            .foregroundStyle(Color.text2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/* ------------------------------ Recent ------------------------------ */

private struct RecentTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = RecentTileViewModel()

    var body: some View {
        TileShell(title: S.Dashboard.tileRecent, onOpen: onOpen, content: {
            if viewModel.rows.isEmpty {
                TileEmpty(text: S.Dashboard.emptyRecent)
            } else {
                VStack(spacing: 6) {
                    // The SAME row web renders on Transactions, Search and
                    // Statements. It was private inside TransactionsView until
                    // this tile needed it; a second copy here is the
                    // re-inlining the component inventory exists to prevent.
                    ForEach(viewModel.rows) { item in
                        TransactionRowView(item: item)
                    }
                }
            }
        })
        .onAppear { viewModel.start() }
    }
}

/* ----------------------------- Spending ----------------------------- */

private struct SpendingTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = SpendingTileViewModel()

    var body: some View {
        TileShell(
            title: S.Dashboard.tileSpending,
            onOpen: onOpen,
            trailing: {
                if !viewModel.slices.isEmpty {
                    Text(formatMoney(viewModel.totalMinor, baseCurrencyNow()))
                        .sanvyaStyle(SanvyaType.body)
                        .foregroundStyle(Color.text)
                }
            },
            content: {
                if viewModel.slices.isEmpty {
                    TileEmpty(text: S.Dashboard.emptySpending)
                } else {
                    // Ranked horizontal bars, not a donut. Web's own comment:
                    // "a calmer, more legible read than a donut", and bars are
                    // sized against the LARGEST category so the leader always
                    // fills its track.
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(viewModel.slices.enumerated()), id: \.element.id) { index, slice in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Text(slice.name)
                                        .sanvyaStyle(SanvyaType.statLabel)
                                        .foregroundStyle(Color.text)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text("\(formatMoney(slice.totalMinor, baseCurrencyNow())) · \(slice.sharePct)%")
                                        .sanvyaStyle(SanvyaType.statLabel)
                                        .foregroundStyle(Color.text2)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.surface2)
                                        Capsule()
                                            .fill(dashboardChartColors[index % dashboardChartColors.count])
                                            .frame(width: geo.size.width * CGFloat(slice.fillPct) / 100)
                                    }
                                }
                                .frame(height: 7)
                            }
                        }
                        if viewModel.hiddenCount > 0 {
                            Text(S.Dashboard.moreCategories(count: viewModel.hiddenCount))
                                .sanvyaStyle(SanvyaType.statLabel)
                                .foregroundStyle(Color.text2)
                        }
                    }
                }
            }
        )
        .onAppear { viewModel.start() }
    }
}

/* ----------------------------- Upcoming ----------------------------- */

private struct UpcomingTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = UpcomingTileViewModel()

    var body: some View {
        TileShell(title: S.Dashboard.tileUpcoming, onOpen: onOpen, content: {
            if viewModel.rows.isEmpty {
                TileEmpty(text: S.Dashboard.emptyUpcoming)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.rows) { row in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .sanvyaStyle(SanvyaType.body)
                                    .foregroundStyle(Color.text)
                                    .lineLimit(1)
                                Text(S.Cashflow.next(date: row.dueIso))
                                    .sanvyaStyle(SanvyaType.statLabel)
                                    .foregroundStyle(Color.text2)
                            }
                            Spacer(minLength: 0)
                            if let amount = row.amountMinor {
                                Text(formatMoney(amount, row.currency ?? baseCurrencyNow()))
                                    .sanvyaStyle(SanvyaType.body)
                                    .foregroundStyle(Color.text)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        })
        .onAppear { viewModel.start() }
    }
}
