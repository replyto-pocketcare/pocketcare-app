import SwiftUI

/**
 The one place a `NavTab` becomes a screen.

 `AppShell` owns *where you are* (it persists the tab through backgrounding and
 process death) and hands that down as a binding, so a screen that needs to send
 you somewhere — Insights' "review this in Settings", Cards' empty state
 pointing at Accounts — writes to `tab` and the shell reacts. That is the only
 navigation channel; nothing here pushes onto a `NavigationStack` of its own.
 */
struct ContentView: View {
    /// An invite waiting to be accepted, owned by `SanvyaApp` so it survives the
    /// auth gate. Cleared here once the join screen is done with it.
    @Binding var inviteToken: String?

    /// The group a just-accepted invite put us in. Consumed by `SplitsView`.
    @State private var joinedGroupId: String?

    init(inviteToken: Binding<String?> = .constant(nil)) {
        self._inviteToken = inviteToken
    }

    var body: some View {
        // Measures the window and publishes the class to everything beneath —
        // the shell's chrome and every screen inside it. Outermost, because a
        // resize must reach all of them.
        WindowClassReader {
            AppShell { tab in
                screen(for: tab)
                    // `tab` only exists inside this closure, which is why the
                    // switch happens here rather than beside the join screen.
                    .onChange(of: joinedGroupId) { _, id in
                        if id != nil { tab.wrappedValue = .splits }
                    }
            }
        }
        // A cover, not a tab: /join is a landing for a link from outside the
        // app, and every visit to it ends by leaving. Giving it a tab would put
        // a spent invite in the navigation for the rest of the session.
        .fullScreenCover(isPresented: showingJoin) {
            JoinView(
                token: inviteToken,
                onJoined: { id in
                    joinedGroupId = id
                    inviteToken = nil
                },
                // The gate above this view is what shows sign-in, and it reacts
                // to `authState` on its own. Dropping the token is enough:
                // PendingInvite already holds it for the trip back.
                onSignIn: { inviteToken = nil },
                onDismiss: { inviteToken = nil }
            )
        }
    }

    private var showingJoin: Binding<Bool> {
        Binding(
            get: { !(inviteToken?.isEmpty ?? true) },
            set: { if !$0 { inviteToken = nil } }
        )
    }

    @ViewBuilder
    private func screen(for tab: Binding<NavTab>) -> some View {
        switch tab.wrappedValue {
        case .dashboard:     DashboardView(currentTab: tab)
        case .assistant:     AssistantView()

        case .accounts:      AccountsView()
        case .transactions:  TransactionsView()
        case .cards:         CreditCardsView(currentTab: tab)
        case .splits:        SplitsView(openGroupId: $joinedGroupId)
        case .search:        SearchView()

        case .budgets:       BudgetsView()
        case .goals:         GoalsView()
        case .recurring:     RecurringView()
        case .loans:         LoansView()

        case .investments:   InvestmentsView()
        case .reflect:       ReflectView()
        case .insights:      InsightsView(currentTab: tab)
        case .statements:    StatementsView()

        case .settings:      SettingsView()
        case .help:          HelpView()
        case .notifications: NotificationsView(onOpenSettings: { tab.wrappedValue = .settings })
        }
    }
}

#Preview {
    ContentView()
}
