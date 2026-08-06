import SwiftUI
import Domain

/// Real port of apps/web/src/ui/feed/{InsightFeed,InsightCard,Charts2D,
/// ProgressRail}.tsx (task #28), replacing an entirely fake predecessor that
/// read InsightsViewModel.insights/thisMonthSpending/lastMonthSpending (a
/// hardcoded "StreamTV" subscription + a made-up "dining" keyword heuristic
/// -- all now removed, see InsightsViewModel.swift). Mirrors Android's
/// InsightsScreen.kt, built the same session. Mobile always renders the
/// "mobile" single-card-per-viewport layout -- web's desktop coverflow has
/// no phone equivalent. Charts are hand-drawn via Canvas (no charting
/// library on mobile); see docs/mobile/screen-specs/insights.md's "Chart
/// rendering" section for the geometry each visual kind targets.
///
/// Vertical paging uses SwiftUI's `TabView(.page)` rotated 90° -- there is
/// no native vertical page style, so the whole TabView is rotated -90° and
/// each page's content rotated back +90° with width/height swapped. This is
/// the standard SwiftUI vertical-pager trick.
private let ROUTABLE_CTAS: Set<String> = ["/budgets", "/goals", "/transactions", "/investments"]

private let TYPE_LABEL: [String: String] = [
    "weekly_summary": "Weekly recap", "budget_warning": "Budget alert", "savings_achievement": "Achievement",
    "spending_trend": "Spending trend", "category_breakdown": "Breakdown", "streak": "Streak",
    "biggest_expense": "Biggest expense", "weekday_pattern": "Spending pattern", "label_breakdown": "By label",
    "subscriptions_load": "Subscriptions", "month_pace": "Month pace", "no_spend_days": "No-spend days",
    "goal_progress": "Goal progress", "category_spike": "Category spike", "avg_daily_spend": "Daily average",
    "dividend_income": "Dividend income", "portfolio_projection": "Projected wealth", "mindfulness": "Mindful spending",
]

struct InsightsView: View {
    @Binding var isDrawerOpen: Bool
    /// Insight CTAs deep-link to other screens (e.g. "Review budgets" ->
    /// Budgets tab). No NavigationStack push exists for this since these
    /// are top-level drawer tabs, not pushed screens -- matches Android's
    /// `onNavigate` callback into `SanvyaNavHost`, which this mirrors via
    /// `MainTabView`'s `currentTab`.
    @Binding var currentTab: NavTab
    @State private var viewModel = InsightsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.entitlementLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.isPaidUser {
                    LockedInsightsState { currentTab = .settings }
                } else if viewModel.cards.isEmpty {
                    EmptyInsightsState()
                } else {
                    InsightPagerFeed(
                        cards: viewModel.cards,
                        activeIndex: Binding(
                            get: { viewModel.activeIndex },
                            set: { viewModel.setActiveIndex($0) }
                        ),
                        onCta: { target in
                            guard ROUTABLE_CTAS.contains(target) else { return }
                            currentTab = tabFor(target)
                        }
                    )
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.spring()) { isDrawerOpen.toggle() }
                    } label: {
                        Image(systemName: "line.3.horizontal").imageScale(.large)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.cancel() }
        }
    }

    private func tabFor(_ target: String) -> NavTab {
        switch target {
        case "/budgets": return .budgets
        case "/goals": return .goals
        case "/transactions": return .transactions
        case "/investments": return .investments
        default: return .insights
        }
    }
}

// MARK: - Locked / empty states

private struct LockedInsightsState: View {
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock").font(.system(size: 28)).foregroundColor(Color.text2)
            Text("Unlock insights").font(.title3).fontWeight(.bold).foregroundColor(Color.text)
            Text("See weekly recaps, budget alerts, spending patterns and more — generated automatically from your own data.")
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)
            Button("Go premium", action: onUpgrade)
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .padding(.top, 4)
        }
        .padding(28)
        .background(Color.surface)
        .cornerRadius(SanvyaRadius.radiusLg)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyInsightsState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lightbulb").font(.system(size: 28)).foregroundColor(Color.text2)
            Text("Your stack is empty for now").font(.headline).fontWeight(.bold).foregroundColor(Color.text)
            Text("Add a few transactions and Sanvya will start surfacing weekly recaps, budget alerts and savings wins here.")
                .font(.caption)
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(Color.surface)
        .cornerRadius(SanvyaRadius.radiusLg)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pager feed

private struct InsightPagerFeed: View {
    let cards: [InsightCard]
    @Binding var activeIndex: Int
    let onCta: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TabView(selection: $activeIndex) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                        InsightCardView(card: card, onCta: onCta)
                            .rotationEffect(.degrees(-90))
                            .frame(width: geo.size.height, height: geo.size.width)
                            .tag(i)
                    }
                }
                .frame(width: geo.size.height, height: geo.size.width)
                .rotationEffect(.degrees(90), anchor: .topLeading)
                .offset(x: geo.size.width)
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Progress rail: vertical pill stack, right edge, centered.
                HStack {
                    Spacer()
                    VStack(spacing: 5) {
                        ForEach(cards.indices, id: \.self) { i in
                            Capsule()
                                .fill(i <= activeIndex ? Color.accent : Color.border)
                                .frame(width: 4)
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { withAnimation { activeIndex = i } }
                        }
                    }
                    .frame(height: min(320, CGFloat(cards.count) * 26))
                }
                .padding(.trailing, 10)

                VStack {
                    Spacer()
                    let remaining = max(0, cards.count - (activeIndex + 1))
                    Text("\(activeIndex + 1) of \(cards.count)" + (remaining > 0 ? " · \(remaining) left" : " · all caught up"))
                        .font(.caption)
                        .foregroundColor(Color.text2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.surface))
                        .padding(.bottom, 14)
                }
            }
        }
    }
}

// MARK: - Card

private func themeAccent(_ theme: InsightTheme) -> Color {
    switch theme {
    case .positive: return Color.positive
    case .warning: return Color.warning
    case .celebratory: return Color.accent
    case .neutral: return Color.forest
    }
}

private struct InsightCardView: View {
    let card: InsightCard
    let onCta: (String) -> Void

    var body: some View {
        let accent = themeAccent(card.theme)
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg)
                .fill(Color.surface2)
                .overlay {
                    if let visual = card.visual {
                        VisualChart(visual: visual, accent: accent).padding(10)
                    } else {
                        Text(card.headline)
                            .font(.title3).fontWeight(.bold).foregroundColor(Color.text)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                .frame(maxHeight: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(TYPE_LABEL[card.type] ?? card.type)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.surface2))

                    Text(card.headline)
                        .font(.title2).fontWeight(.bold).foregroundColor(Color.text)

                    if let subhead = card.subhead {
                        Text(subhead).font(.footnote).foregroundColor(Color.text2)
                    }

                    if let m = card.metric {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Text(m.display).font(.system(size: 28, weight: .bold)).foregroundColor(accent)
                            if let delta = m.deltaPct {
                                let up = m.direction == "up"
                                Text("\(up ? "▲" : "▼") \(abs(delta))%")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(up ? Color.positive : Color.negative)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(card.bullets, id: \.self) { b in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").fontWeight(.bold).foregroundColor(accent)
                                Text(b).font(.system(size: 13.5)).foregroundColor(Color.text)
                            }
                        }
                    }

                    if let cta = card.cta, ROUTABLE_CTAS.contains(cta.target) {
                        Button(cta.label) { onCta(cta.target) }
                            .font(.subheadline)
                            .foregroundColor(accent)
                            .padding(.top, 2)
                    }
                }
                .padding(20)
            }
            .background(Color.surface)
            .cornerRadius(SanvyaRadius.radiusLg)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 40)
    }
}

// MARK: - Charts

private func resolveColor(_ token: String?, _ index: Int, _ fallback: Color) -> Color {
    switch token {
    case "positive": return Color.positive
    case "warning": return Color.warning
    case "negative": return Color.negative
    case "forest": return Color.forest
    case "accent": return Color.accent
    case "border": return Color.border
    case nil: return Color(hex: INSIGHT_PALETTE[index % INSIGHT_PALETTE.count]) ?? fallback
    default: return fallback
    }
}

private struct VisualChart: View {
    let visual: VisualSpec
    let accent: Color

    var body: some View {
        switch visual {
        case .bars(let series, let unit, let horizontal):
            BarsChart(series: series, unit: unit, horizontal: horizontal, accent: accent)
        case .area(let series):
            AreaChart(series: series, accent: accent)
        case .donut(let series, let centerLabel, let centerSub):
            DonutChart(series: series, centerLabel: centerLabel, centerSub: centerSub, accent: accent)
        case .gauge(let value, let gmax, let warnAt, let dangerAt, _, let centerLabel):
            GaugeChart(value: value, gmax: gmax, warnAt: warnAt, dangerAt: dangerAt, centerLabel: centerLabel, accent: accent)
        case .progress(let value, let target, let centerLabel):
            ProgressChart(value: value, target: target, centerLabel: centerLabel, accent: accent)
        }
    }
}

private struct BarsChart: View {
    let series: [SeriesPoint]
    let unit: String?
    let horizontal: Bool
    let accent: Color

    var body: some View {
        if series.isEmpty {
            EmptyView()
        } else {
            let maxVal = max(series.map(\.value).max() ?? 1, 1e-9)
            GeometryReader { geo in
                if horizontal {
                    VStack(spacing: 8) {
                        ForEach(Array(series.enumerated()), id: \.offset) { i, s in
                            HStack(spacing: 8) {
                                Text(s.label).font(.system(size: 11)).foregroundColor(Color.text2).frame(width: 76, alignment: .leading)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(resolveColor(s.color, i, accent))
                                    .frame(width: max(CGFloat(s.value / maxVal), 0.02) * max(geo.size.width - 84, 0))
                                Spacer(minLength: 0)
                            }
                            .frame(maxHeight: .infinity)
                        }
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(series.enumerated()), id: \.offset) { i, s in
                            VStack(spacing: 4) {
                                Spacer(minLength: 0)
                                if s.value != 0 {
                                    Text(fmtCompact(s.value)).font(.system(size: 9)).foregroundColor(Color.text2)
                                }
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(resolveColor(s.color, i, accent))
                                    .frame(height: max(CGFloat(s.value / maxVal), 0.02) * max(geo.size.height - 24, 0))
                                Text(s.label).font(.system(size: 10)).foregroundColor(Color.text2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: geo.size.height, alignment: .bottom)
                }
            }
        }
    }
}

private struct AreaChart: View {
    let series: [SeriesPoint]
    let accent: Color

    var body: some View {
        if series.count < 2 {
            EmptyView()
        } else {
            Canvas { context, size in
                let values = series.map(\.value)
                let maxV = values.max() ?? 0
                let minV = min(0, values.min() ?? 0)
                let range = max(maxV - minV, 1e-9)
                let stepX = size.width / CGFloat(series.count - 1)
                func y(_ v: Double) -> CGFloat { size.height - CGFloat((v - minV) / range) * size.height }

                var line = Path()
                var fill = Path()
                for (i, s) in series.enumerated() {
                    let x = CGFloat(i) * stepX
                    let yy = y(s.value)
                    if i == 0 {
                        line.move(to: CGPoint(x: x, y: yy))
                        fill.move(to: CGPoint(x: x, y: size.height))
                        fill.addLine(to: CGPoint(x: x, y: yy))
                    } else {
                        line.addLine(to: CGPoint(x: x, y: yy))
                        fill.addLine(to: CGPoint(x: x, y: yy))
                    }
                }
                fill.addLine(to: CGPoint(x: CGFloat(series.count - 1) * stepX, y: size.height))
                fill.closeSubpath()

                context.fill(fill, with: .color(accent.opacity(0.18)))
                context.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
        }
    }
}

private struct DonutChart: View {
    let series: [SeriesPoint]
    let centerLabel: String?
    let centerSub: String?
    let accent: Color

    var body: some View {
        if series.isEmpty {
            EmptyView()
        } else {
            let total = max(series.reduce(0) { $0 + $1.value }, 1e-9)
            ZStack {
                Canvas { context, size in
                    let stroke = min(size.width, size.height) * 0.16
                    let rect = CGRect(x: stroke / 2, y: stroke / 2, width: size.width - stroke, height: size.height - stroke)
                    var startAngle = -90.0
                    for (i, s) in series.enumerated() {
                        let sweep = s.value / total * 360.0
                        var arc = Path()
                        arc.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                                   startAngle: .degrees(startAngle), endAngle: .degrees(startAngle + sweep * 0.96), clockwise: false)
                        context.stroke(arc, with: .color(resolveColor(s.color, i, accent)), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        startAngle += sweep
                    }
                }
                .padding(12)
                if centerLabel != nil || centerSub != nil {
                    VStack(spacing: 2) {
                        if let c = centerLabel { Text(c).font(.system(size: 20, weight: .bold)).foregroundColor(Color.text) }
                        if let s = centerSub { Text(s).font(.system(size: 11)).foregroundColor(Color.text2) }
                    }
                }
            }
        }
    }
}

private struct GaugeChart: View {
    let value: Double
    let gmax: Double
    let warnAt: Double?
    let dangerAt: Double?
    let centerLabel: String?
    let accent: Color

    var body: some View {
        let ratio = gmax > 0 ? min(max(value / gmax, 0), 1) : 0
        let color: Color = {
            if value >= (dangerAt ?? gmax) { return Color.negative }
            if value >= (warnAt ?? gmax * 0.8) { return Color.warning }
            return accent
        }()
        ZStack {
            Canvas { context, size in
                let stroke = min(size.width, size.height) * 0.14
                let rect = CGRect(x: stroke / 2, y: stroke / 2, width: size.width - stroke, height: size.height - stroke)
                let start = 150.0, sweepTotal = 240.0
                var track = Path()
                track.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: .degrees(start), endAngle: .degrees(start + sweepTotal), clockwise: false)
                context.stroke(track, with: .color(Color.border), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

                var fillArc = Path()
                fillArc.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: .degrees(start), endAngle: .degrees(start + sweepTotal * ratio), clockwise: false)
                context.stroke(fillArc, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            .padding(16)
            Text(centerLabel ?? "\(Int(ratio * 100))%").font(.system(size: 22, weight: .bold)).foregroundColor(Color.text)
        }
    }
}

private struct ProgressChart: View {
    let value: Double
    let target: Double?
    let centerLabel: String?
    let accent: Color

    var body: some View {
        let ratio: Double = {
            if let t = target, t > 0 { return min(max(value / t, 0), 1) }
            return 0.5
        }()
        ZStack {
            Canvas { context, size in
                let stroke = min(size.width, size.height) * 0.13
                let rect = CGRect(x: stroke / 2, y: stroke / 2, width: size.width - stroke, height: size.height - stroke)
                var track = Path()
                track.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
                context.stroke(track, with: .color(Color.border), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

                var fillArc = Path()
                fillArc.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * ratio), clockwise: false)
                context.stroke(fillArc, with: .color(accent), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            .padding(16)
            Text(centerLabel ?? "\(Int(ratio * 100))%").font(.system(size: 22, weight: .bold)).foregroundColor(Color.text)
        }
    }
}

private func fmtCompact(_ v: Double) -> String {
    if v == 0 { return "" }
    if abs(v) >= 1000 {
        let k = v / 1000
        return k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
    }
    return v == v.rounded() ? "\(Int(v))" : String(format: "%.0f", v)
}

#Preview {
    InsightsView(isDrawerOpen: .constant(false), currentTab: .constant(.insights))
}
