import SwiftUI
import Domain

/// Search — ported from apps/web/app/search/page.tsx.
///
/// The list rows are `TransactionRowView`, the same component Transactions and
/// the dashboard's Recent tile use, because web renders the same
/// `<TransactionTile>` on all three. The filter is Domain's, vector-tested.
///
/// **Not ported: the deep-link prefill.** Web reads `?q=&type=&account=…` so
/// the assistant can hand a user a pre-filtered search. There is no assistant
/// on either native platform yet and no URL to read, so building the reader
/// first would be a parameter nothing can set. Tracked in PARITY_AUDIT.
struct SearchView: View {
    @State private var viewModel = SearchViewModel()

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            SanvyaPage(S.Search.title) {
                SanvyaInput(text: $vm.criteria.query, placeholder: S.Search.searchEverything)

                HStack(spacing: 8) {
                    SanvyaChip(filtersLabel, isActive: viewModel.showFilters) {
                        viewModel.showFilters.toggle()
                    }
                    if viewModel.activeFilters > 0 {
                        SanvyaChip(S.Search.clear, isActive: false) { viewModel.clearFilters() }
                    }
                    Spacer(minLength: 0)
                }

                if viewModel.showFilters { filterCard() }

                Text(S.Search.resultsCount(count: viewModel.resultCount))
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)

                if viewModel.items.isEmpty {
                    SanvyaCard {
                        Text(S.Search.noMatching)
                            .sanvyaStyle(SanvyaType.body)
                            .foregroundStyle(Color.text2)
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.items) { item in
                            TransactionRowView(item: item)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
    }

    /// "Filters" on its own, "Filters · 3" once something is set — web puts the
    /// count in the chip so a collapsed panel still says it is doing something.
    private var filtersLabel: String {
        let n = viewModel.activeFilters
        return n > 0 ? "\(S.Search.filters) · \(n)" : S.Search.filters
    }

    @ViewBuilder
    private func filterCard() -> some View {
        @Bindable var vm = viewModel
        SanvyaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 6) {
                    ForEach(searchTypes, id: \.self) { ty in
                        SanvyaChip(searchTypeLabel(ty), isActive: viewModel.criteria.type == ty) {
                            viewModel.criteria.type = ty
                        }
                    }
                }

                // Chips, not a wheel. Web uses a `<select>`, but this codebase
                // draws every one-of-a-few choice as chips (see
                // RecurringFormView) and a Picker here would be the only one.
                // "All accounts" is web's empty first option.
                FlowLayout(spacing: 6) {
                    SanvyaChip(S.Search.allAccounts, isActive: viewModel.criteria.accountId.isEmpty) {
                        viewModel.criteria.accountId = ""
                    }
                    ForEach(viewModel.accounts, id: \.id) { account in
                        SanvyaChip(account.name, isActive: viewModel.criteria.accountId == account.id) {
                            viewModel.criteria.accountId = account.id
                        }
                    }
                }

                // Both ends labelled. Web's comment says why: an empty date
                // input gives no clue which end of the range it is.
                HStack(spacing: 8) {
                    labelled(S.Search.fromDate) {
                        // Plain ISO text, same as Recurring and Statements and
                        // the same as Android — see RecurringFormView for why
                        // DatePicker is not used on one platform only.
                        SanvyaInput(text: $vm.criteria.from, placeholder: "YYYY-MM-DD")
                    }
                    labelled(S.Search.toDate) {
                        SanvyaInput(text: $vm.criteria.to, placeholder: "YYYY-MM-DD")
                    }
                }

                HStack(spacing: 8) {
                    labelled(S.Search.minAmount) {
                        SanvyaInput(text: $vm.criteria.min)
                            .keyboardType(.decimalPad)
                    }
                    labelled(S.Search.maxAmount) {
                        SanvyaInput(text: $vm.criteria.max)
                            .keyboardType(.decimalPad)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func labelled<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .sanvyaStyle(SanvyaType.statLabel)
                .foregroundStyle(Color.text2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func searchTypeLabel(_ key: String) -> String {
        switch key {
        case "income": S.Search.typeIncome
        case "expense": S.Search.typeExpense
        case "transfer": S.Search.typeTransfer
        default: S.Search.typeAll
        }
    }
}

#Preview {
    SearchView()
}
