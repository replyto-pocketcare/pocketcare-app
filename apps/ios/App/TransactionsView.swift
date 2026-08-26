import SwiftUI
import Factory

/// Transactions list — rewritten 2026-08-05 per
/// docs/mobile/screen-specs/transactions.md. Previous version had no
/// transfer filter tab, no tags/labels, no way to open a row for editing
/// (EditTransactionView didn't exist), and the ViewModel's category name
/// was a hardcoded "General".
struct TransactionsView: View {
    @State private var viewModel = Container.shared.transactionsViewModel()
    @State private var editingId: EditingTransactionId?
    @State private var showingCreateSheet = false

    var body: some View {
        SanvyaPage(S.Transactions.title) {
            Button(action: { showingCreateSheet = true }) {
                Image(systemName: "plus").font(.headline).foregroundColor(Color.accent)
            }
        } content: {
            VStack(spacing: 10) {
                TextField(S.Transactions.searchPlaceholder, text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(txTypeFilters, id: \.self) { ty in
                            let selected = ty == viewModel.typeFilter
                            // The chip label is a translated string, not the
                            // filter KEY capitalised. `ty.capitalized`
                            // rendered "All"/"Income" in every language.
                            Button(txTypeFilterLabel(ty)) { viewModel.typeFilter = ty }
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selected ? Color.accent : Color.surface2)
                                .foregroundColor(selected ? .white : Color.text)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }

                ScrollView {
                    if viewModel.items.isEmpty {
                        Text(S.Transactions.noMatching)
                            .foregroundColor(Color.text2)
                            .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.items) { item in
                                Button {
                                    editingId = EditingTransactionId(id: item.id)
                                } label: {
                                    TransactionRowView(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .sanvyaFormPresentation(isPresented: $showingCreateSheet) {
                CreateTransactionView()
            }
            .sanvyaFormPresentation(item: $editingId) { entry in
                EditTransactionView(transactionId: entry.id)
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
    }

    struct EditingTransactionId: Identifiable { let id: String }
}

/// The translated label for a type-filter key.
///
/// Shared with the Search screen, which offers the same four chips from the
/// same `search` namespace on web — the keys differ per namespace, the mapping
/// does not, so it is written once here.
func txTypeFilterLabel(_ key: String) -> String {
    switch key {
    case "income": S.Transactions.filterIncome
    case "expense": S.Transactions.filterExpense
    case "transfer": S.Transactions.filterTransfer
    default: S.Transactions.filterAll
    }
}

#Preview {
    TransactionsView()
}
