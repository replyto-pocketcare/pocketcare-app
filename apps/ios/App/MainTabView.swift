import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
                }

            AccountsView()
                .tabItem {
                    Label("Accounts", systemImage: "creditcard.fill")
                }

            TransactionsView()
                .tabItem {
                    Label("Txns", systemImage: "list.bullet.rectangle.fill")
                }

            BudgetsView()
                .tabItem {
                    Label("Budgets", systemImage: "chart.pie.fill")
                }
        }
        .tint(Theme.terracotta)
    }
}

#Preview {
    MainTabView()
}
