import SwiftUI

/**
 The expenses behind a budget's "spent" figure — web's
 apps/web/src/budgets/SpentBreakdown.tsx.

 The rows come from `BudgetRepository.transactionsThisPeriod`, which shares its
 scope clause with `spentThisPeriod` — so this list is the same query that
 produced the number, not a second interpretation of "what counts". A drill-down
 that disagrees with the figure above it is worse than none, because it makes
 the user distrust the budget rather than the screen.

 Mirrors `apps/android/.../ui/budgets/SpentBreakdownDialog.kt`.
 */
struct SpentBreakdownView: View {
    let state: BudgetsViewModel.SpentBreakdownState
    var onOpenTransaction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.text)
            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(Color.text2)
                .padding(.top, 2)
                .padding(.bottom, 12)

            if state.rows == nil {
                SanvyaSpinner(size: 26)
                    .frame(maxWidth: .infinity, minHeight: 96)
            } else if let rows = state.rows, rows.isEmpty {
                Text(S.Budgets.breakdownEmpty)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let rows = state.rows {
                ForEach(rows) { row in
                    Button {
                        onOpenTransaction(row.id)
                    } label: {
                        BreakdownRow(row: row)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Color.border)
                }
                HStack {
                    Text(S.Budgets.breakdownTotal)
                    Spacer()
                    Text(state.listedTotalFormatted)
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.text)
                .padding(.top, 12)

                if state.mismatch {
                    Text(S.Budgets.breakdownMismatch(amount: state.spentAmountFormatted))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }
        }
    }

    /// Loading and "nothing here" are DIFFERENT states, and web draws them
    /// differently for a reason: a budget with no spend yet and a budget still
    /// reading look identical if both are an empty list.
    private var summary: String {
        state.rows == nil
            ? S.Budgets.breakdownLoading
            : S.Budgets.breakdownSummary(count: state.count, amount: state.spentAmountFormatted)
    }
}

private struct BreakdownRow: View {
    let row: BudgetsViewModel.BudgetTxnUiModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(row.amountFormatted)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Web's own fallback chain, in order: what the user typed, then the note,
    /// then the category, then a translated "Expense".
    private var title: String {
        if let d = row.description, !d.isEmpty { return d }
        if let n = row.note, !n.isEmpty { return n }
        if let c = row.categoryName, !c.isEmpty { return c }
        return S.Budgets.breakdownFallback
    }

    private var subtitle: String {
        var parts = [row.dateLabel]
        if let c = row.categoryName, !c.isEmpty { parts.append(c) }
        if let a = row.accountName, !a.isEmpty { parts.append(a) }
        return parts.joined(separator: " · ")
    }
}
