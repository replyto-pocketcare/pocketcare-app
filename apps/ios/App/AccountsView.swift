import SwiftUI

struct AccountsView: View {
    @State private var showingCreateSheet = false

    let sampleAccounts = [
        DummyAccountItem(id: "1", name: "HDFC Savings", balance: "₹1,42,500.00", isNegative: false),
        DummyAccountItem(id: "2", name: "SBI Salary Account", balance: "₹45,200.00", isNegative: false),
        DummyAccountItem(id: "3", name: "ICICI Amazon Pay CC", balance: "₹-18,200.00", isNegative: true),
        DummyAccountItem(id: "4", name: "Physical Cash", balance: "₹3,400.00", isNegative: false),
        DummyAccountItem(id: "5", name: "Zerodha Stocks", balance: "₹3,15,000.00", isNegative: false)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(sampleAccounts) { acct in
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(acct.name)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.ink)

                                Text("Savings • INR")
                                    .font(.caption)
                                    .foregroundColor(Theme.inkSoft)
                            }
                            Spacer()
                            Text(acct.balance)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(acct.isNegative ? Theme.terracotta : Theme.sage)
                        }
                        .padding(16)
                        .background(Theme.cream)
                        .cornerRadius(16)
                    }
                }
                .padding(16)
            }
            .background(Theme.clay50.ignoresSafeArea())
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateSheet = true }) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(Theme.terracotta)
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateAccountView()
            }
        }
    }
}

#Preview {
    AccountsView()
}
