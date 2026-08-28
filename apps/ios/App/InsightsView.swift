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
/**
 The CTA targets this screen can follow, and the tab each one means.

 `/subscriptions` is a MAPPING, not a rename. Web's `/subscriptions` page is a
 redirect to `/recurring` — its own comment says it is "kept so old links —
 dashboard tiles, insights CTAs, bookmarks — still land" — and the
 subscriptions-load insight (`Insights.swift`, cadenceKey `subscriptions_load`)
 is one of those links. It was absent from this list, so that card drew a
 "Manage subscriptions" button that did nothing at all.
 */
private let ROUTABLE_CTAS: [String: NavTab] = [
    "/budgets": .budgets,
    "/goals": .goals,
    "/transactions": .transactions,
    "/investments": .investments,
    "/subscriptions": .recurring,
]

private let TYPE_LABEL: [String: String] = [
    "weekly_summary": "Weekly recap", "budget_warning": "Budget alert", "savings_achievement": "Achievement",
    "spending_trend": "Spending trend", "category_breakdown": "Breakdown", "streak": "Streak",
    "biggest_expense": "Biggest expense", "weekday_pattern": "Spending pattern", "label_breakdown": "By label",
    "subscriptions_load": S.Translation.navSubscriptions, "month_pace": "Month pace", "no_spend_days": "No-spend days",
    "goal_progress": "Goal progress", "category_spike": "Category spike", "avg_daily_spend": "Daily average",
    "dividend_income": "Dividend income", "portfolio_projection": "Projected wealth", "mindfulness": "Mindful spending",
]

struct InsightsView: View {
    /// Insight CTAs deep-link to other screens (e.g. "Review budgets" ->
    /// Budgets tab). No NavigationStack push exists for this since these
    /// are top-level drawer tabs, not pushed screens -- matches Android's
    /// `onNavigate` callback into `SanvyaNavHost`, which this mirrors via
    /// the shell's current tab (see `ContentView.swift`).
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
                            guard let tab = ROUTABLE_CTAS[target] else { return }
                            currentTab = tab
                        }
                    )
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(S.Insights.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.cancel() }
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
            Button(S.Insights.goPremium, action: onUpgrade)
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
                        SanvyaVisualChart(visual: visual, accent: accent).padding(10)
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

#Preview {
    InsightsView(currentTab: .constant(.insights))
}
