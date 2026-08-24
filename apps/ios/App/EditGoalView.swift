import SwiftUI

/// Real edit form + delete, matching apps/web/app/goals/page.tsx's
/// GoalCard openEdit()/saveEdit() field-for-field per
/// docs/mobile/screen-specs/goals.md: name/target/alert-time editable --
/// currency, is_emergency_fund, and priority are not (create-only/
/// immutable from this screen, matching web exactly). New file -- iOS had
/// no edit screen for goals at all before this pass (2026-08-06, task
/// #25); GoalsView.swift's rows were not tappable and had no delete path.
struct EditGoalView: View {
    @Environment(\.dismiss) private var dismiss
    let goal: GoalsViewModel.GoalUiModel
    let viewModel: GoalsViewModel

    @State private var name: String
    @State private var targetText: String
    @State private var alertTime: String
    @State private var saving = false
    @State private var errorText: String?
    @State private var showingDeleteConfirm = false

    init(goal: GoalsViewModel.GoalUiModel, viewModel: GoalsViewModel) {
        self.goal = goal
        self.viewModel = viewModel
        _name = State(initialValue: goal.rawName)
        _targetText = State(initialValue: goal.targetMajor)
        _alertTime = State(initialValue: goal.alertTimeLocal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(S.Goals.goalName)) {
                    TextField(S.Goals.goalName, text: $name)
                }

                Section(header: Text("Target amount (\(goal.currency))")) {
                    TextField("0", text: $targetText)
                        .keyboardType(.decimalPad)
                }

                Section(header: Text("Alert")) {
                    DatePicker("Alert time", selection: Binding(
                        get: { timeStringToDate(alertTime) },
                        set: { alertTime = dateToTimeString($0) }
                    ), displayedComponents: .hourAndMinute)
                }

                if let errorText {
                    Section { Text(errorText).foregroundColor(Color.negative) }
                }

                Section {
                    Button(action: save) {
                        if saving {
                            ProgressView()
                        } else {
                            Text(S.Translation.commonSaveChanges)
                                .font(.headline)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundColor(Color.surface)
                        }
                    }
                    .disabled(saving)
                    .listRowBackground(Color.accent)
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Text("Delete Goal").frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Goals.cancel) { dismiss() }.foregroundColor(Color.text2)
                }
            }
            .confirmationDialog(S.Goals.deleteTitle, isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                Button(S.Goals.delete, role: .destructive) {
                    Task {
                        await viewModel.delete(id: goal.id)
                        dismiss()
                    }
                }
                Button(S.Goals.cancel, role: .cancel) {}
            }
        }
    }

    private func save() {
        saving = true
        errorText = nil
        Task {
            let err = await viewModel.update(id: goal.id, name: name, targetMajorText: targetText, alertTimeLocal: alertTime)
            saving = false
            if let err {
                errorText = err
            } else {
                dismiss()
            }
        }
    }
}
