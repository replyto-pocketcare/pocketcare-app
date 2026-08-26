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
        // All fourteen. The `switch` keeps its no-`default` shape: a fifteenth
        // tile in web's catalog must still fail the build until somebody
        // decides.
        case .recent, .spending, .upcoming, .budgets, .goals, .splits,
             .byCategory, .byLabel, .monthCompare,
             .trends, .subscriptions, .cashflow, .netTrend, .currencies: return true
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
        case .budgets: BudgetsTile(onOpen: open)
        case .goals: GoalsTile(onOpen: open)
        case .splits: SplitsTile(onOpen: open)
        case .byCategory: ByCategoryTile(onOpen: open)
        case .byLabel: ByLabelTile(onOpen: open)
        case .monthCompare: MonthCompareTile(onOpen: open)
        case .trends: TrendsTile(onOpen: open)
        case .cashflow: CashflowTile(onOpen: open)
        case .netTrend: NetTrendTile(onOpen: open)
        case .subscriptions: SubscriptionsTile(onOpen: open)
        case .currencies: CurrenciesTile(onOpen: open)
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

/* ------------------------------ Budgets ----------------------------- */

private struct BudgetsTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = BudgetsTileViewModel()

    var body: some View {
        HeroTile(title: S.Dashboard.tileBudgets, tint: .budgets, onOpen: onOpen) {
            if viewModel.rows.isEmpty {
                Text(S.Dashboard.emptyBudgets)
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(heroInkMuted)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.rows) { budget in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(budget.label)
                                    .sanvyaStyle(SanvyaType.statLabel)
                                    .foregroundStyle(heroInk)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(formatMoney(budget.spentMinor, budget.currency)) / \(formatMoney(budget.limitMinor, budget.currency))")
                                    .sanvyaStyle(SanvyaType.statLabel)
                                    .foregroundStyle(heroInkMuted)
                                    .lineLimit(1)
                            }
                            // Three fills, not one: over-limit, at-threshold,
                            // and fine. Web's own colours — pale on purpose,
                            // because the track sits on a gradient and a
                            // saturated bar would fight it.
                            LightBar(
                                pct: budget.pct,
                                color: budget.overLimit
                                    ? Color(hex: "#f0d8c9")!
                                    : (budget.atOrOverThreshold ? Color(hex: "#f3e4c6")! : Color(hex: "#dde7c9")!)
                            )
                        }
                    }
                }
            }
        }
        .onAppear { viewModel.start() }
    }
}

/* ------------------------------- Goals ------------------------------ */

private struct GoalsTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = GoalsTileViewModel()

    var body: some View {
        HeroTile(title: S.Dashboard.tileGoals, tint: .goals, onOpen: onOpen) {
            if viewModel.rows.isEmpty {
                Text(S.Dashboard.emptyGoals)
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(heroInkMuted)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.rows) { goal in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(goal.isEmergencyFund ? "\(goal.name) · \(S.Dashboard.efShort)" : goal.name)
                                    .sanvyaStyle(SanvyaType.statLabel)
                                    .foregroundStyle(heroInk)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(formatMoney(goal.savedMinor, goal.currency)) / \(formatMoney(goal.targetMinor, goal.currency))")
                                    .sanvyaStyle(SanvyaType.statLabel)
                                    .foregroundStyle(heroInkMuted)
                                    .lineLimit(1)
                            }
                            LightBar(
                                pct: goal.pct,
                                color: goal.isEmergencyFund ? Color(hex: "#c6cdb3")! : Color(hex: "#f3e4c6")!
                            )
                        }
                    }
                }
            }
        }
        .onAppear { viewModel.start() }
    }
}

/* ------------------------------ Splits ------------------------------ */

private struct SplitsTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = SplitsTileViewModel()

    var body: some View {
        TileShell(title: S.Dashboard.tileSplits, onOpen: onOpen, content: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(S.Dashboard.youAreOwed)
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(Color.text2)
                        Text(formatMoney(viewModel.owedMinor, baseCurrencyNow()))
                            .sanvyaStyle(SanvyaType.statValue)
                            .foregroundStyle(Color.positive)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(S.Dashboard.youOwe)
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(Color.text2)
                        Text(formatMoney(viewModel.oweMinor, baseCurrencyNow()))
                            .sanvyaStyle(SanvyaType.statValue)
                            .foregroundStyle(Color.negative)
                    }
                    Spacer(minLength: 0)
                }

                if viewModel.rows.isEmpty {
                    Text(S.Dashboard.emptySplits)
                        .sanvyaStyle(SanvyaType.statLabel)
                        .foregroundStyle(Color.text2)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.rows) { row in
                            HStack(spacing: 8) {
                                Text(row.name)
                                    .sanvyaStyle(SanvyaType.statLabel)
                                    .foregroundStyle(Color.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                // Web builds this from the same two inline
                                // fragments; they exist as keys because Splits
                                // already renders them.
                                Text(row.netMinor > 0
                                     ? "\(S.Splits.owesYouInline) \(formatMoney(row.netMinor, baseCurrencyNow()))"
                                     : "\(S.Splits.youOweInline) \(formatMoney(-row.netMinor, baseCurrencyNow()))")
                                    .sanvyaStyle(SanvyaType.statLabel)
                                    .foregroundStyle(row.netMinor > 0 ? Color.positive : Color.negative)
                                    .lineLimit(1)
                            }
                        }
                        if viewModel.hiddenCount > 0 {
                            Text(S.Dashboard.moreItems(count: viewModel.hiddenCount))
                                .sanvyaStyle(SanvyaType.statLabel)
                                .foregroundStyle(Color.text2)
                        }
                    }
                }
            }
        })
        .onAppear { viewModel.start() }
    }
}

/* -------------------- By category / by label ------------------- */

/// Web's `HBarTile` — a ranked horizontal bar per row.
///
/// The bars are the shared `SanvyaBarsChart`, which was `private` inside the
/// Insights screen until 2026-08-26. Two tiles differing only in what they group
/// by is exactly the case for one shell, which is what web does too.
private struct HBarTile: View {
    let title: String
    let rows: [NamedTotalRow]
    let emptyText: String
    let onOpen: (() -> Void)?

    var body: some View {
        TileShell(title: title, onOpen: onOpen, content: {
            if rows.isEmpty {
                TileEmpty(text: emptyText)
            } else {
                SanvyaBarsChart(
                    series: rows.map { row in
                        SeriesPoint(
                            (row.name?.isEmpty == false ? row.name! : S.Transactions.uncategorised),
                            // MAJOR units: the chart labels its own values, and
                            // a bar labelled in minor units would read as 100x
                            // the money.
                            toMajor(Money(amount: row.totalMinor, currency: baseCurrencyNow()))
                        )
                    },
                    unit: nil,
                    horizontal: true,
                    accent: Color.accent
                )
            }
        })
    }
}

private struct ByCategoryTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = ByCategoryTileViewModel()

    var body: some View {
        HBarTile(
            title: S.Dashboard.tileByCategory,
            rows: viewModel.rows,
            emptyText: S.Dashboard.emptySpending,
            onOpen: onOpen
        )
        .onAppear { viewModel.start() }
    }
}

private struct ByLabelTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = ByLabelTileViewModel()

    var body: some View {
        HBarTile(
            title: S.Dashboard.tileByLabel,
            rows: viewModel.rows,
            emptyText: S.Dashboard.emptyLabels,
            onOpen: onOpen
        )
        .onAppear { viewModel.start() }
    }
}

/* ---------------------- This month vs last --------------------- */

private struct MonthCompareTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = MonthCompareTileViewModel()

    var body: some View {
        TileShell(title: S.Dashboard.tileMonthCompare, onOpen: onOpen, content: {
            if viewModel.isEmpty {
                TileEmpty(text: S.Dashboard.emptySpending)
            } else {
                // Four bars, not a grouped pair per month: the shared bars chart
                // draws one series, and web's grouping is a recharts affordance
                // rather than information. The colour carries income-vs-expense.
                SanvyaBarsChart(
                    series: [
                        SeriesPoint("\(S.Dashboard.lastMonth) · \(S.Cashflow.dirLabelIncome)", major(viewModel.lastIncomeMinor), "positive"),
                        SeriesPoint("\(S.Dashboard.lastMonth) · \(S.Cashflow.dirLabelPayment)", major(viewModel.lastExpenseMinor), "accent"),
                        SeriesPoint("\(S.Dashboard.thisMonth) · \(S.Cashflow.dirLabelIncome)", major(viewModel.thisIncomeMinor), "positive"),
                        SeriesPoint("\(S.Dashboard.thisMonth) · \(S.Cashflow.dirLabelPayment)", major(viewModel.thisExpenseMinor), "accent"),
                    ],
                    unit: nil,
                    horizontal: true,
                    accent: Color.accent
                )
            }
        })
    }

    private func major(_ minor: Int64) -> Double {
        toMajor(Money(amount: minor, currency: baseCurrencyNow()))
    }
}

/* ---------------------------- Trends --------------------------- */

/// Formats a bucket's start date for the axis. The DATE is what Domain returns;
/// the label is built here, with the device's locale, because web's version
/// hardcodes English month names.
private func bucketLabel(_ startIso: String, _ period: TrendPeriod) -> String {
    let parts = startIso.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return startIso }
    var components = DateComponents()
    components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let date = calendar.date(from: components) else { return startIso }
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate(period == .oneYear ? "MMM" : "d MMM")
    return formatter.string(from: date)
}

private func trendPeriodLabel(_ period: TrendPeriod) -> String {
    switch period {
    case .threeDays: return S.Dashboard.trendLast3d
    case .oneWeek: return S.Dashboard.trendLast1w
    case .oneYear: return S.Dashboard.trendLast1y
    case .oneMonth: return S.Dashboard.trendLast1m
    }
}

private struct TrendsTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = TrendsTileViewModel()

    var body: some View {
        TileShell(title: S.Dashboard.tileTrends, onOpen: onOpen, content: {
            VStack(alignment: .leading, spacing: 8) {
                // Chips, not web's <select>: this codebase has no select
                // component, and four options is what a chip row is for.
                FlowLayout(spacing: 8) {
                    ForEach(TrendPeriod.allCases, id: \.self) { option in
                        SanvyaChip(trendPeriodLabel(option), isActive: option == viewModel.period) {
                            viewModel.setPeriod(option)
                        }
                    }
                }
                Text("\(S.Dashboard.spent(amount: formatMoney(viewModel.totalMinor, baseCurrencyNow()))) · \(trendPeriodLabel(viewModel.period))")
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
                SanvyaAreaChart(
                    series: viewModel.buckets.map {
                        SeriesPoint(bucketLabel($0.startIso, viewModel.period), toMajor(Money(amount: $0.totalMinor, currency: baseCurrencyNow())))
                    },
                    accent: Color.accent
                )
                .frame(height: 140)
            }
        })
        .onAppear { viewModel.start() }
    }
}

/* ------------------- Cashflow / net trend ---------------------- */

private struct CashflowTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = CashflowTileViewModel()

    var body: some View {
        HeroTile(title: S.Dashboard.tileCashflow, tint: .cashflow, onOpen: onOpen) {
            if viewModel.months.isEmpty {
                Text(S.Dashboard.emptyCashflow)
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(heroInkMuted)
            } else {
                let totalIn = viewModel.months.reduce(Int64(0)) { $0 + $1.incomeMinor }
                let totalOut = viewModel.months.reduce(Int64(0)) { $0 + $1.expenseMinor }
                let net = totalIn - totalOut
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .bottom, spacing: 4) {
                        Text((net >= 0 ? "+" : "−") + formatMoney(abs(net), baseCurrencyNow()))
                            .sanvyaStyle(SanvyaType.statValue)
                            .foregroundStyle(heroInk)
                        Text(S.Dashboard.net)
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(heroInkMuted)
                            .padding(.bottom, 4)
                    }
                    HStack(spacing: 18) {
                        Text("\(S.Dashboard.inflow) \(formatMoney(totalIn, baseCurrencyNow()))")
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(heroInkMuted)
                        Text("\(S.Dashboard.outflow) \(formatMoney(totalOut, baseCurrencyNow()))")
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(heroInkMuted)
                    }
                    SanvyaAreaChart(
                        series: viewModel.months.map { SeriesPoint($0.month, toMajor(Money(amount: $0.netMinor, currency: baseCurrencyNow()))) },
                        accent: heroInk
                    )
                    .frame(height: 70)
                }
            }
        }
        .onAppear { viewModel.start() }
    }
}

private struct NetTrendTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = CashflowTileViewModel()

    var body: some View {
        TileShell(title: S.Dashboard.tileNetTrend, onOpen: onOpen, content: {
            if viewModel.months.isEmpty {
                TileEmpty(text: S.Dashboard.emptyCashflow)
            } else {
                SanvyaAreaChart(
                    series: viewModel.months.map { SeriesPoint($0.month, toMajor(Money(amount: $0.netMinor, currency: baseCurrencyNow()))) },
                    accent: Color.accent
                )
                .frame(height: 140)
            }
        })
        .onAppear { viewModel.start() }
    }
}

/* ------------------------ Subscriptions ------------------------ */

private struct SubscriptionsTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = SubscriptionsTileViewModel()

    var body: some View {
        HeroTile(title: S.Dashboard.tileSubscriptions, tint: .subs, onOpen: onOpen) {
            if viewModel.rows.isEmpty {
                Text(S.Dashboard.emptySubscriptions)
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(heroInkMuted)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(formatMoney(viewModel.monthlyMinor, baseCurrencyNow()))
                            .sanvyaStyle(SanvyaType.statValue)
                            .foregroundStyle(heroInk)
                        Text(S.Dashboard.perMonth)
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(heroInkMuted)
                            .padding(.bottom, 4)
                    }
                    ForEach(viewModel.rows) { row in
                        HStack(spacing: 8) {
                            Text(row.name)
                                .sanvyaStyle(SanvyaType.statLabel)
                                .foregroundStyle(heroInk)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(row.dueIso)
                                .sanvyaStyle(SanvyaType.statLabel)
                                .foregroundStyle(heroInkMuted)
                        }
                    }
                    if viewModel.hiddenCount > 0 {
                        Text(S.Dashboard.moreItems(count: viewModel.hiddenCount))
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(heroInkMuted)
                    }
                }
            }
        }
        .onAppear { viewModel.start() }
    }
}

/* ----------------------- Across currencies --------------------- */

private struct CurrenciesTile: View {
    let onOpen: (() -> Void)?
    @State private var viewModel = CurrenciesTileViewModel()

    var body: some View {
        TileShell(title: S.Dashboard.tileCurrencies, onOpen: onOpen, content: {
            // Web draws nothing below two currencies, and says so: one
            // full-width bar labelled with the only currency you hold is not
            // information.
            if viewModel.slices.count < 2 {
                TileEmpty(text: S.Dashboard.singleCurrency(base: baseCurrencyNow()))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(Array(viewModel.slices.enumerated()), id: \.element.id) { index, slice in
                                Rectangle()
                                    .fill(dashboardChartColors[index % dashboardChartColors.count])
                                    .frame(width: geo.size.width * CGFloat(max(0, slice.sharePct)) / 100)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 10)
                    .background(Color.surface2)
                    .clipShape(Capsule())

                    ForEach(Array(viewModel.slices.enumerated()), id: \.element.id) { index, slice in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(dashboardChartColors[index % dashboardChartColors.count])
                                .frame(width: 9, height: 9)
                            Text(slice.currency)
                                .sanvyaStyle(SanvyaType.statLabel)
                                .foregroundStyle(Color.text)
                            Text(formatMoney(slice.nativeMinor, slice.currency))
                                .sanvyaStyle(SanvyaType.statLabel)
                                .foregroundStyle(Color.text2)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(slice.currency == baseCurrencyNow()
                                 ? "\(slice.sharePct)%"
                                 : "≈ \(formatMoney(slice.baseMinor, baseCurrencyNow())) · \(slice.sharePct)%")
                                .sanvyaStyle(SanvyaType.statLabel)
                                .foregroundStyle(Color.text2)
                        }
                    }
                }
            }
        })
        .onAppear { viewModel.start() }
    }
}
