import SwiftUI

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

    private var actionLabel: String { goal.isEmergencyFund ? S.Goals.add : S.Goals.block }

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.savingsAccounts.isEmpty {
                    Section {
                        Text("Add a savings account first.").foregroundColor(Color.text2)
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

                    Section(header: Text("Amount (\(goal.currency))")) {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                        Text("Left to target: \(remainingText)")
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
                                Text(actionLabel)
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
            .navigationTitle("\(actionLabel) funds · \(goal.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Goals.cancel) { dismiss() }.foregroundColor(Color.text2)
                }
            }
        }
    }

    private var remainingText: String {
        let major = Double(goal.remainingMinor) / 100.0
        return String(format: "%.2f %@", major, goal.currency)
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
