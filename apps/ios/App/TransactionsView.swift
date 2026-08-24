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
        NavigationStack {
            VStack(spacing: 10) {
                TextField("Search note or label", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(txTypeFilters, id: \.self) { ty in
                            let selected = ty == viewModel.typeFilter
                            Button(ty.capitalized) { viewModel.typeFilter = ty }
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
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(S.Transactions.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateSheet = true }) {
                        Image(systemName: "plus").font(.headline).foregroundColor(Color.accent)
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateTransactionView()
            }
            .sheet(item: $editingId) { entry in
                EditTransactionView(transactionId: entry.id)
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
    }

    struct EditingTransactionId: Identifiable { let id: String }
}

private struct TransactionRowView: View {
    let item: TransactionListItem

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(avatarColor(item.title))
                .frame(width: 34, height: 34)
                .overlay(Text(item.avatarLetter).font(.system(size: 14, weight: .bold)).foregroundColor(.white))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.text)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color.text2)
                        .lineLimit(2)
                }
                if !item.tagsText.isEmpty {
                    Text(item.tagsText)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color.text2)
                        .lineLimit(1)
                }
                if let account = item.accountName {
                    Text(account).font(.system(size: 11.5)).foregroundColor(Color.text2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.amountFormatted)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundColor(item.isPositive ? Color.positive : Color.text)
                Text(item.dateFormatted).font(.system(size: 11)).foregroundColor(Color.text2)
            }
        }
        .padding(14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
    }
}

#Preview {
    TransactionsView()
}
