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
struct BudgetsView: View {
    @State private var showingCreateSheet = false
    @State private var editingBudget: BudgetsViewModel.BudgetUiModel?
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
                                Button {
                                    editingBudget = budget
                                } label: {
                                    BudgetRowCard(budget: budget)
                                }
                                .buttonStyle(.plain)
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
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.cancel() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("◔").font(.system(size: 26))
            Text(S.Budgets.noBudgetsTitle).font(.title3).fontWeight(.bold).foregroundColor(Color.text)
            Text("Set a spending limit to get alerts before you go over.")
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)
            Button(action: { showingCreateSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Create first budget").fontWeight(.semibold)
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

    var body: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(budget.title)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(Color.text)
                        Text(budget.timeframeText)
                            .font(.caption)
                            .foregroundColor(Color.text2)
                    }
                    Spacer()
                    Text("\(Int((budget.progress * 100).rounded()))%")
                        .font(.caption)
                        .foregroundColor(Color.text2)
                }

                ProgressView(value: min(budget.progress, 1.0))
                    .tint(progressTint)
                    .scaleEffect(x: 1, y: 1.5, anchor: .center)
                    .padding(.vertical, 4)

                HStack {
                    Text(budget.spentFormatted)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.text)
                    Spacer()
                    Text(budget.remainingOrOverText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(progressTint)
                }
            }
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
