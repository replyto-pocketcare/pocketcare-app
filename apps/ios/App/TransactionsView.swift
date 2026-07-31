import SwiftUI

struct TransactionsView: View {
    @State private var searchText = ""
    @State private var selectedFilter = 0
    @State private var showingCreateSheet = false

    let sampleTxns = [
        DummyTxnItem(id: "1", description: "Swiggy Gourmet", amount: "-₹840.00", date: "Today", isPositive: false),
        DummyTxnItem(id: "2", description: "Salary Credit", amount: "+₹85,000.00", date: "Yesterday", isPositive: true),
        DummyTxnItem(id: "3", description: "Reliance Fresh Groceries", amount: "-₹2,350.00", date: "29 Jul", isPositive: false),
        DummyTxnItem(id: "4", description: "Uber Ride", amount: "-₹420.00", date: "28 Jul", isPositive: false),
        DummyTxnItem(id: "5", description: "Splitwise Settlement (Ankit)", amount: "+₹1,500.00", date: "26 Jul", isPositive: true)
    ]

    var filteredTxns: [DummyTxnItem] {
        sampleTxns.filter { txn in
            let matchesSearch = searchText.isEmpty || txn.description.localizedCaseInsensitiveContains(searchText)
            let matchesFilter = (selectedFilter == 0) || (selectedFilter == 1 && !txn.isPositive) || (selectedFilter == 2 && txn.isPositive)
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Filter Picker
                Picker("Filter", selection: $selectedFilter) {
                    Text("All").tag(0)
                    Text("Expense").tag(1)
                    Text("Income").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                // List
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filteredTxns) { txn in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(txn.description)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Theme.ink)

                                    HStack(spacing: 6) {
                                        Text("Food & Dining")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Theme.clay100)
                                            .cornerRadius(6)

                                        Text(txn.date)
                                            .font(.caption)
                                            .foregroundColor(Theme.inkSoft)
                                    }
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
                    .padding(16)
                }
            }
            .background(Theme.clay50.ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Search transactions")
            .navigationTitle("Transactions")
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
                CreateTransactionView()
            }
        }
    }
}

#Preview {
    TransactionsView()
}
