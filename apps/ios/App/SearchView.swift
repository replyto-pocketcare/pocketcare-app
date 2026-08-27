import SwiftUI
import Data
import Domain

/// Search — ported from apps/web/app/search/page.tsx.
///
/// The list rows are `TransactionRowView`, the same component Transactions and
/// the dashboard's Recent tile use, because web renders the same
/// `<TransactionTile>` on all three. The filter is Domain's, vector-tested.
///
/// The deep-link prefill (`?q=&type=&account=…`) arrives as `prefill`, already
/// decoded by Domain's `searchPrefillFromQuery`. It is applied ONCE, in the view
/// model, exactly as web's effect guards itself with a `prefilled` flag — a
/// redraw must not undo what the user has since typed.
struct SearchView: View {
    /// Set by a deep link (an assistant action, a notification). Cleared by the
    /// shell once consumed, so returning to the tab does not re-apply it.
    @Binding var prefill: SearchPrefill?

    @State private var viewModel = SearchViewModel()

    init(prefill: Binding<SearchPrefill?> = .constant(nil)) {
        self._prefill = prefill
    }

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
        .onAppear {
            viewModel.start()
            consumePrefill()
        }
        .onChange(of: prefill == nil) { _, _ in consumePrefill() }
        .onDisappear { viewModel.cancel() }
    }

    /// Apply a deep link's filters, then clear the binding so returning to this
    /// tab later does not re-apply filters the user has since changed.
    private func consumePrefill() {
        guard let prefill else { return }
        viewModel.applyPrefill(prefill)
        self.prefill = nil
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
