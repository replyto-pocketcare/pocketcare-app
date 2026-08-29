import SwiftUI
import Domain

/// "+ Add funds" / "+ Block funds" modal, matching apps/web/app/goals/
/// page.tsx's allocate() Modal per docs/mobile/screen-specs/goals.md: a
/// source savings-account picker, an amount field, a "left to target"
/// hint, and a submit capped at the goal's remaining amount. New file --
/// no allocate path existed on iOS before this pass (2026-08-06, task
/// #25).
struct AllocateGoalView: View {
    @Environment(\.dismiss) private var dismiss
    let goal: GoalsViewModel.GoalUiModel
    let viewModel: GoalsViewModel

    @State private var sourceAccountId: String?
    @State private var amountText = ""
    @State private var saving = false
    @State private var errorText: String?

    // Web has TWO labels here, not one: `allocLabel` titles the modal ("Add
    // funds" / "Block funds") and a shorter verb sits on the submit button
    // ("Add" / "Block"). They were collapsed into one English literal.
    private var allocLabel: String { goal.isEmergencyFund ? S.Goals.addFunds : S.Goals.blockFunds }
    private var submitLabel: String { goal.isEmergencyFund ? S.Goals.add : S.Goals.block }
    /// Web appends "We'll cap this at the remaining amount." once the entered
    /// figure is past the target, so the cap is not a surprise after the fact.
    private var overCap: Bool { (Double(amountText) ?? 0) > toMajor(money(goal.remainingMinor, goal.currency)) }

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.savingsAccounts.isEmpty {
                    Section {
                        Text(S.Goals.addSavingsFirst).foregroundColor(Color.text2)
                    }
                } else {
                    Section(header: Text(S.Goals.fromAccount)) {
                        Picker(S.Translation.settingsAccount, selection: Binding(
                            get: { sourceAccountId ?? viewModel.savingsAccounts.first?.id ?? "" },
                            set: { sourceAccountId = $0 }
                        )) {
                            ForEach(viewModel.savingsAccounts) { acc in
                                Text(acc.name).tag(acc.id)
                            }
                        }
                    }

                    Section(header: Text(S.Goals.amount(currency: goal.currency))) {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                        Text(S.Goals.leftToTarget(amount: remainingText) + (overCap ? S.Goals.willCap : ""))
                            .font(.caption)
                            .foregroundColor(Color.text2)
                    }

                    if let errorText {
                        Section { Text(errorText).foregroundColor(Color.negative) }
                    }

                    Section {
                        Button(action: allocate) {
                            if saving {
                                ProgressView()
                            } else {
                                Text(submitLabel)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .foregroundColor(Color.surface)
                            }
                        }
                        .disabled(saving || amountText.isEmpty)
                        .listRowBackground(Color.accent)
                    }
                }
            }
            .navigationTitle("\(allocLabel) · \(goal.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Goals.cancel) { dismiss() }.foregroundColor(Color.text2)
                }
            }
        }
    }

    private var remainingText: String {
        // The app's own formatter, not `/ 100.0` and `%.2f`. Both hardcoded
        // the same assumption twice over -- the scale AND the decimal count --
        // so a zero-decimal currency read as a hundredth of itself and then
        // printed two fake decimals after it.
        formatMoney(goal.remainingMinor, goal.currency)
    }

    private func allocate() {
        guard let src = sourceAccountId ?? viewModel.savingsAccounts.first?.id else { return }
        saving = true
        errorText = nil
        Task {
            let err = await viewModel.allocate(
                goalId: goal.id,
                sourceAccountId: src,
                amountMajorText: amountText,
                remainingMinor: goal.remainingMinor,
                currency: goal.currency
            )
            saving = false
            if let err {
                errorText = err
            } else {
                dismiss()
            }
        }
    }
}
