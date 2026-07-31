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
                    Label("Transactions", systemImage: "list.bullet.rectangle.fill")
                }
        }
        .tint(Theme.terracotta)
    }
}

#Preview {
    MainTabView()
}
