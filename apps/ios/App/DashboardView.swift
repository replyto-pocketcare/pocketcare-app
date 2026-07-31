import SwiftUI

struct DummyAccountItem: Identifiable {
    let id: String
    let name: String
    let balance: String
    let isNegative: Bool
}

struct DummyTxnItem: Identifiable {
    let id: String
    let description: String
    let amount: String
    let date: String
    let isPositive: Bool
}

struct DashboardView: View {
    let dummyAccounts = [
        DummyAccountItem(id: "1", name: "Main Savings", balance: "₹1,42,500.00", isNegative: false),
        DummyAccountItem(id: "2", name: "HDFC Credit Card", balance: "₹-18,200.00", isNegative: true),
        DummyAccountItem(id: "3", name: "Cash Wallet", balance: "₹3,400.00", isNegative: false)
    ]

    let dummyTxns = [
        DummyTxnItem(id: "1", description: "Grocery Market", amount: "-₹1,250.00", date: "Today", isPositive: false),
        DummyTxnItem(id: "2", description: "Salary Credit", amount: "+₹85,000.00", date: "Yesterday", isPositive: true),
        DummyTxnItem(id: "3", description: "Coffee & Snacks", amount: "-₹340.00", date: "28 Jul", isPositive: false),
        DummyTxnItem(id: "4", description: "Split Settlement (Rahul)", amount: "+₹1,200.00", date: "26 Jul", isPositive: true)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Net Worth Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("NET WORTH")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.cream.opacity(0.8))

                        Text("₹1,27,700.00")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Theme.cream)

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Assets")
                                    .font(.caption2)
                                    .foregroundColor(Theme.cream.opacity(0.7))
                                Text("₹1,45,900")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Theme.cream)
                            }
                            Spacer()
                            VStack(alignment: .leading) {
                                Text("Liabilities")
                                    .font(.caption2)
                                    .foregroundColor(Theme.cream.opacity(0.7))
                                Text("₹18,200")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Theme.cream)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.terracotta)
                    .cornerRadius(20)

                    // Quick Actions
                    HStack(spacing: 16) {
                        Spacer()
                        QuickActionButtonView(icon: "plus", label: "Expense")
                        Spacer()
                        QuickActionButtonView(icon: "arrow.triangle.2.circlepath", label: "Transfer")
                        Spacer()
                        QuickActionButtonView(icon: "person.2", label: "Settle Up")
                        Spacer()
                    }

                    // Accounts Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Accounts")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.ink)
                            Spacer()
                            Button(action: {}) {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(Theme.inkSoft)
                            }
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(dummyAccounts) { acct in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(acct.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(Theme.ink)
                                        Spacer()
                                        Text(acct.balance)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .foregroundColor(acct.isNegative ? Theme.terracotta : Theme.olive600)
                                    }
                                    .padding(16)
                                    .frame(width: 170, height: 100, alignment: .leading)
                                    .background(Theme.cream)
                                    .cornerRadius(16)
                                }
                            }
                        }
                    }

                    // Recent Activity Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Activity")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.ink)

                        ForEach(dummyTxns) { txn in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(txn.description)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Theme.ink)
                                    Text(txn.date)
                                        .font(.caption)
                                        .foregroundColor(Theme.inkSoft)
                                }
                                Spacer()
                                Text(txn.amount)
                                    .font(.body)
                                    .fontWeight(.bold)
                                    .foregroundColor(txn.isPositive ? Theme.sage : Theme.ink)
                            }
                            .padding(16)
                            .background(Theme.cream)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.clay50.ignoresSafeArea())
            .navigationTitle("PocketCare")
        }
    }
}

struct QuickActionButtonView: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.terracotta)
                .frame(width: 50, height: 50)
                .background(Theme.cream)
                .clipShape(Circle())

            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(Theme.ink)
        }
    }
}

#Preview {
    DashboardView()
}
