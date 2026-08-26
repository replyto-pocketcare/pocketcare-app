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
    var body: some View {
        // Measures the window and publishes the class to everything beneath —
        // the shell's chrome and every screen inside it. Outermost, because a
        // resize must reach all of them.
        WindowClassReader {
            AppShell { tab in
                screen(for: tab)
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: Binding<NavTab>) -> some View {
        switch tab.wrappedValue {
        case .dashboard:     DashboardView(currentTab: tab)
        case .assistant:     AssistantView()

        case .accounts:      AccountsView()
        case .transactions:  TransactionsView()
        case .cards:         CreditCardsView(currentTab: tab)
        case .splits:        SplitsView()
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
