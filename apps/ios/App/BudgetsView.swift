import SwiftUI

/// Ported from apps/web/app/budgets/page.tsx's list + docs/mobile/
/// screen-specs/budgets.md. Was list-read-only (hardcoded "All" category,
/// no tap-to-edit, CreateBudgetView's Save button never touched the
/// repository) before this pass (2026-08-06, task #24) -- now backed by
/// BudgetsViewModel's real create/update/delete.
///
/// Web's edit affordance is an in-place expand within the same card, not a
/// separate screen -- this uses a sheet-based EditBudgetView instead,
/// matching the native idiom already established for Accounts/Transactions
/// on both platforms (translate the logic, not the exact widget shape).
///
/// 2026-08-29: the two things a card could not do arrived together. Tapping
/// the spent figure opens the drill-down that produced it
/// (`SpentBreakdownView`), and the cumulative spend-vs-limit curve
/// (`BudgetSpendChart`) sits inside the card the way it does on web. The
/// strings the ViewModel used to compose in English -- "Spent x", "Over by x",
/// "All spending", "Monthly" -- are composed here instead, beside the rest of
/// this screen's `S.Budgets` reads.
struct BudgetsView: View {
    @State private var showingCreateSheet = false
    @State private var editingBudget: BudgetsViewModel.BudgetUiModel?
    /// Set only once the breakdown has finished dismissing -- see
    /// `openTransaction(_:)`.
    @State private var editingTransaction: TransactionsView.EditingTransactionId?
    @State private var viewModel = BudgetsViewModel()

    var body: some View {
        SanvyaPage(S.Budgets.title) {
            Button(action: { showingCreateSheet = true }) {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundColor(Color.accent)
            }
        } content: {
            Group {
                if viewModel.budgets.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(viewModel.budgets) { budget in
                                BudgetRowCard(
                                    budget: budget,
                                    onEdit: { editingBudget = budget },
                                    onShowSpent: { viewModel.openBreakdown(budgetId: budget.id) }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .sanvyaFormPresentation(isPresented: $showingCreateSheet) {
                CreateBudgetView()
            }
            .sanvyaFormPresentation(item: $editingBudget) { budget in
                EditBudgetView(budget: budget, viewModel: viewModel)
            }
            .sanvyaFormPresentation(item: $editingTransaction) { entry in
                EditTransactionView(transactionId: entry.id)
            }
            .sanvyaModal(
                isPresented: Binding(
                    get: { viewModel.breakdown != nil },
                    set: { if !$0 { viewModel.closeBreakdown() } }
                ),
                label: viewModel.breakdown.map { S.Budgets.breakdownTitleAria(title: $0.title) }
            ) {
                if let state = viewModel.breakdown {
                    SpentBreakdownView(state: state, onOpenTransaction: openTransaction)
                }
            }
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.cancel() }
        }
    }

    /// Close the drill-down, then open the transaction.
    ///
    /// Web's row is a `<Link>` with an `onClick={onClose}`: you leave the
    /// dialog behind. SwiftUI cannot swap one presentation for another in the
    /// same run loop turn -- the second is simply dropped -- so the edit sheet
    /// waits out the modal's dismissal rather than racing it.
    private func openTransaction(_ id: String) {
        viewModel.closeBreakdown()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            editingTransaction = TransactionsView.EditingTransactionId(id: id)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("◔").font(.system(size: 26))
            Text(S.Budgets.noBudgetsTitle).font(.title3).fontWeight(.bold).foregroundColor(Color.text)
            Text(S.Budgets.noBudgetsBody)
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)
            Button(action: { showingCreateSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(S.Budgets.createFirst).fontWeight(.semibold)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.accent)
                .foregroundColor(Color.surface)
                .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BudgetRowCard: View {
    let budget: BudgetsViewModel.BudgetUiModel
    var onEdit: () -> Void
    var onShowSpent: () -> Void

    var body: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 12) {
                // Only the header opens the edit sheet, so the spent figure
                // below can be a button of its own -- a Button nested inside a
                // Button's label never receives the tap. Same shape GoalRowCard
                // already uses.
                Button(action: onEdit) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(Color.text)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(Color.text2)
                        }
                        Spacer()
                        // An em dash, not "Infinity%": a limit of zero has no
                        // ratio to report. Web prints the same character.
                        Text(budget.pctRounded.map { "\($0)%" } ?? "—")
                            .font(.caption)
                            .foregroundColor(Color.text2)
                    }
                }
                .buttonStyle(.plain)

                ProgressView(value: min(budget.progress, 1.0))
                    .tint(progressTint)
                    .scaleEffect(x: 1, y: 1.5, anchor: .center)
                    .padding(.vertical, 4)

                HStack {
                    // The spent figure is the drill-down: tapping the number
                    // you are questioning is where people look for the answer.
                    // Web underlines it with a dotted rule to say so.
                    Button(action: onShowSpent) {
                        Text(S.Budgets.spent(amount: budget.spentAmountFormatted))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.text)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(S.Budgets.viewSpentAria)
                    Spacer()
                    Text(
                        budget.overLimit
                            ? S.Budgets.over(amount: budget.remainderAmountFormatted)
                            : S.Budgets.left(amount: budget.remainderAmountFormatted)
                    )
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(progressTint)
                }

                BudgetSpendChart(
                    series: budget.spendSeries,
                    limitMinor: budget.limitMinor,
                    currency: budget.currency,
                    tint: progressTint
                )
            }
        }
    }

    /// Web falls back to the scope when a budget has no name, and to "All
    /// spending" when it has neither.
    private var title: String {
        budget.title.isEmpty ? S.Budgets.allSpending : budget.title
    }

    private var subtitle: String {
        // A custom-dated budget has no period word -- the dates ARE the
        // timeframe.
        let timeframe = budget.isCustomDated ? budget.winLabel : "\(periodWord) · \(budget.winLabel)"
        // Web appends the scope only when the budget also has a name of its
        // own, since otherwise the scope is already the title.
        guard !budget.title.isEmpty, !budget.scopeLabel.isEmpty, budget.title != budget.scopeLabel else {
            return timeframe
        }
        return "\(timeframe) · \(budget.scopeLabel)"
    }

    private var periodWord: String {
        switch budget.period {
        case "daily": return S.Budgets.periodDaily
        case "weekly": return S.Budgets.periodWeekly
        case "yearly": return S.Budgets.periodYearly
        default: return S.Budgets.periodMonthly
        }
    }

    private var progressTint: Color {
        switch budget.progressColor {
        case .positive: return Color.positive
        case .warning: return Color.warning
        case .negative: return Color.negative
        }
    }
}

#Preview {
    BudgetsView()
}
