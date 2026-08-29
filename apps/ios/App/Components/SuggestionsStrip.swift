import SwiftUI
import Observation
import Factory
import Data
import Domain

/**
 Dashboard → "Worth a look" — a horizontal strip of features this person has not
 tried yet. A port of `apps/web/src/dashboard/Suggestions.tsx`.

 WHY IT IS NOT JUST A FEATURE LIST. Most of the app is invisible from the
 dashboard: someone tracking spends for six months may never learn that loans,
 budgets or bill-splitting exist. But a permanent "here is what else we sell"
 rail is an ad, and in a finance app that costs trust. So every rule in Domain's
 `pickSuggestions` exists to REMOVE cards:

  - each suggestion has a prerequisite, so nothing appears until there is enough
    history for it to be an observation rather than a pitch,
  - credit cards only surface for someone who actually holds one,
  - premium features are never suggested to a free user,
  - every card is dismissible, permanently,
  - and when there is nothing to say the strip renders NOTHING — no empty state,
    no "you have explored everything" badge.

 **Web's copy is inline English**, with a comment saying the dashboard is not
 internationalised so one translated widget would look odd. Both native
 dashboards ARE translated, so the copy is in the `dashboard` namespace here.

 Mirrors apps/android/.../ui/dashboard/SuggestionsStrip.kt.
 */

/// Dismissed features, persisted.
///
/// Same `localStorage` key web uses (`sanvya:suggestionsDismissed`) and the same
/// JSON-array shape, so the two clients mean one thing by a dismissal. Stored
/// ids are filtered through `SuggestionFeature(rawValue:)` on read: an id from
/// an older build must not sit in the set forever silencing nothing.
enum SuggestionsDismissed {
    private static let key = "sanvya:suggestionsDismissed"

    static func read() -> Set<String> {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return [] }
        return Set(parsed.compactMap { $0 as? String }.compactMap { SuggestionFeature(rawValue: $0)?.rawValue })
    }

    static func add(_ feature: SuggestionFeature) -> Set<String> {
        let next = read().union([feature.rawValue])
        if let data = try? JSONSerialization.data(withJSONObject: Array(next)),
           let raw = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(raw, forKey: key)
        }
        return next
    }
}

/**
 The strip's own view model, rather than more fields on `DashboardViewModel`.

 Web gives this widget its own component with its own query for the same reason:
 the counts are twelve integers nothing else on the dashboard wants, and folding
 them into the hero's flow would re-run the net-worth aggregate every time a
 receipt is saved.
 */
@MainActor
@Observable
final class SuggestionsViewModel {
    @ObservationIgnored @Injected(\.suggestionsRepository) private var suggestionsRepository

    var usage = UsageCounts()
    var dismissed: Set<String> = []
    /// The counts have been read at least once.
    var loaded = false
    /// Never judge mid-sync — see ``SuggestionsStrip``.
    var syncPending = true

    private var tasks: [Task<Void, Never>] = []

    func start() {
        guard tasks.isEmpty else { return }
        dismissed = SuggestionsDismissed.read()

        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                for try await counts in try self.suggestionsRepository.watchUsageCounts() {
                    self.usage = counts
                    self.loaded = true
                }
            } catch {
                // A count we could not take is not a count of zero. Leaving
                // `loaded` false keeps the strip silent rather than letting it
                // suggest a first budget to someone who has five.
            }
        })

        tasks.append(Task { [weak self] in
            await awaitInitialSync()
            guard let self, !Task.isCancelled else { return }
            self.syncPending = false
        })
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func dismiss(_ feature: SuggestionFeature) {
        dismissed = SuggestionsDismissed.add(feature)
    }
}

/// The strip. Renders nothing — not an empty state — when there is nothing to
/// suggest, which is the common case and is meant to be.
struct SuggestionsStrip: View {
    let isPaid: Bool
    let onOpen: (NavTab) -> Void

    @State private var viewModel = SuggestionsViewModel()

    private var picked: [SuggestionFeature] {
        // Never judge mid-sync. A returning user's rows have not arrived yet, so
        // every count reads zero — we would tell somebody with five budgets to
        // create their first one. Same reasoning as the first-run walkthrough's
        // own gate, and web says so in the same words.
        guard viewModel.loaded, !viewModel.syncPending else { return [] }
        return pickSuggestions(usage: viewModel.usage, dismissed: viewModel.dismissed, isPaid: isPaid)
    }

    var body: some View {
        Group {
            if !picked.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 8) {
                        Text(S.Dashboard.suggestTitle)
                            .sanvyaStyle(SanvyaType.h2)
                            .foregroundStyle(Color.text)
                        Spacer(minLength: 0)
                        Text(S.Dashboard.suggestSubtitle)
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(Color.text2)
                    }

                    // A horizontal rail. The cards bleed to the screen edge on
                    // purpose, so a half-visible card signals scrollability
                    // instead of stopping dead at the container edge — web does
                    // the same with negative margins.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(picked, id: \.rawValue) { feature in
                                SuggestionCard(
                                    feature: feature,
                                    onOpen: { onOpen(destination(for: feature)) },
                                    onDismiss: { viewModel.dismiss(feature) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
    }
}

private struct SuggestionCard: View {
    let feature: SuggestionFeature
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SanvyaCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    SanvyaIconView(icon(for: feature), size: 20, tint: .accent)
                        .frame(width: 36, height: 36)
                        .background(Color.accentGhost)
                        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
                    Spacer(minLength: 0)
                    // "Not interested" has to mean it, so the control that says
                    // so is on the card rather than behind a long press. An icon
                    // target rather than a labelled chip: web's is a 13pt glyph
                    // in the corner, and the words it would need ("Dismiss Track
                    // subscriptions") are exactly what a label is for.
                    Button(action: onDismiss) {
                        SanvyaIconView(SanvyaIcons.close, size: 13, tint: .text2)
                            .frame(width: 24, height: 24)
                            .background(Color.surface2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(SanvyaPressStyle())
                    .accessibilityLabel(S.Dashboard.suggestDismiss(title: title(for: feature)))
                }

                Text(title(for: feature))
                    .sanvyaStyle(SanvyaType.sectionTitle)
                    .foregroundStyle(Color.text)
                    .padding(.top, 8)

                Text(cardBody(for: feature))
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                SanvyaChip(cta(for: feature), isActive: false, action: onOpen)
                    .padding(.top, 10)
            }
            // Web's `width: min(256px, 78vw)`, as a fixed point width on a
            // phone-first rail.
            .frame(width: 256, alignment: .leading)
        }
    }
}

/**
 Where each card's call to action goes.

 Web's hrefs are `/cashflow#payments` and `/friends`; neither parses to a screen
 this shell has, and `appDestination(forHref:)` already answers the two that do
 (`/receipts/new` lands on Transactions, because receipt capture is a sheet over
 it rather than a tab). Spelled out rather than routed through the href parser so
 the mapping matches Android's `destinationOf` line for line.
 */
private func destination(for feature: SuggestionFeature) -> NavTab {
    switch feature {
    case .subscriptions: return .recurring
    case .budgets: return .budgets
    case .recurring: return .recurring
    case .creditCards: return .cards
    case .loans: return .loans
    case .goals: return .goals
    case .splits: return .splits
    case .receipts: return .transactions
    case .investments: return .investments
    }
}

/// Web's per-card MaterialIcon, resolved to this app's icon font.
private func icon(for feature: SuggestionFeature) -> String {
    switch feature {
    case .subscriptions: return SanvyaIcons.subscriptions
    case .budgets: return SanvyaIcons.pieChart
    case .recurring: return SanvyaIcons.autorenew
    case .creditCards: return SanvyaIcons.creditCard
    case .loans: return SanvyaIcons.requestQuote
    case .goals: return SanvyaIcons.savings
    case .splits: return SanvyaIcons.groups
    case .receipts: return SanvyaIcons.receiptLong
    case .investments: return SanvyaIcons.trendingUp
    }
}

private func title(for feature: SuggestionFeature) -> String {
    switch feature {
    case .subscriptions: return S.Dashboard.suggestSubscriptionsTitle
    case .budgets: return S.Dashboard.suggestBudgetsTitle
    case .recurring: return S.Dashboard.suggestRecurringTitle
    case .creditCards: return S.Dashboard.suggestCreditCardsTitle
    case .loans: return S.Dashboard.suggestLoansTitle
    case .goals: return S.Dashboard.suggestGoalsTitle
    case .splits: return S.Dashboard.suggestSplitsTitle
    case .receipts: return S.Dashboard.suggestReceiptsTitle
    case .investments: return S.Dashboard.suggestInvestmentsTitle
    }
}

private func cardBody(for feature: SuggestionFeature) -> String {
    switch feature {
    case .subscriptions: return S.Dashboard.suggestSubscriptionsBody
    case .budgets: return S.Dashboard.suggestBudgetsBody
    case .recurring: return S.Dashboard.suggestRecurringBody
    case .creditCards: return S.Dashboard.suggestCreditCardsBody
    case .loans: return S.Dashboard.suggestLoansBody
    case .goals: return S.Dashboard.suggestGoalsBody
    case .splits: return S.Dashboard.suggestSplitsBody
    case .receipts: return S.Dashboard.suggestReceiptsBody
    case .investments: return S.Dashboard.suggestInvestmentsBody
    }
}

private func cta(for feature: SuggestionFeature) -> String {
    switch feature {
    case .subscriptions: return S.Dashboard.suggestSubscriptionsCta
    case .budgets: return S.Dashboard.suggestBudgetsCta
    case .recurring: return S.Dashboard.suggestRecurringCta
    case .creditCards: return S.Dashboard.suggestCreditCardsCta
    case .loans: return S.Dashboard.suggestLoansCta
    case .goals: return S.Dashboard.suggestGoalsCta
    case .splits: return S.Dashboard.suggestSplitsCta
    case .receipts: return S.Dashboard.suggestReceiptsCta
    case .investments: return S.Dashboard.suggestInvestmentsCta
    }
}
