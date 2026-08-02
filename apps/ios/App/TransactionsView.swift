import SwiftUI
import Factory

struct TransactionsView: View {
    @Binding var isDrawerOpen: Bool
    @State private var viewModel = Container.shared.transactionsViewModel()
    @State private var searchText = ""
    @State private var selectedFilter = 0
    @State private var showingCreateSheet = false

    var filteredTxns: [TransactionUiModel] {
        viewModel.allTransactions.filter { txn in
            let matchesSearch = searchText.isEmpty || txn.description.localizedCaseInsensitiveContains(searchText)
            let matchesFilter = (selectedFilter == 0) || (selectedFilter == 1 && !txn.isIncome) || (selectedFilter == 2 && txn.isIncome)
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
                        if filteredTxns.isEmpty {
                            Text("No transactions found")
                                .foregroundColor(Color.text2)
                                .padding(.top, 40)
                        } else {
                            ForEach(filteredTxns) { txn in
                                RowTile(
                                    title: txn.description,
                                    subtitle: "\(txn.accountName) • \(txn.date)",
                                    trailing: {
                                        Text(txn.amount)
                                            .font(.body)
                                            .fontWeight(.bold)
                                            .foregroundColor(txn.isIncome ? Color.positive : Color.text)
                                    },
                                    leading: {
                                        Text(txn.categoryName)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.surface2)
                                            .cornerRadius(6)
                                    }
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Search transactions")
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.spring()) {
                            isDrawerOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .imageScale(.large)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateSheet = true }) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(Color.accent)
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateTransactionView()
            }
        }
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.cancel()
        }
    }
}

#Preview {
    TransactionsView(isDrawerOpen: .constant(false))
}
