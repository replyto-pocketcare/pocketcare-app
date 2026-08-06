import SwiftUI

/// Real edit form + delete, matching apps/web/app/budgets/page.tsx's
/// BudgetRow openEdit()/saveEdit() field-for-field per
/// docs/mobile/screen-specs/budgets.md: name/limit/threshold/alert-time/
/// categories/labels editable; currency and start/end dates are NOT (web's
/// edit form has no currency picker; the period chips are hidden entirely
/// for a custom-dated budget -- see the `!budget.start_date` guard below,
/// same as web's `{!budget.start_date && <period chips>}`). iOS had no edit
/// screen for budgets at all before this pass (2026-08-06, task #24) --
/// BudgetsView.swift's rows were not tappable.
struct EditBudgetView: View {
    @Environment(\.dismiss) private var dismiss
    let budget: BudgetsViewModel.BudgetUiModel
    let viewModel: BudgetsViewModel
    var onDeleted: () -> Void = {}

    @State private var name: String
    @State private var limitText: String
    @State private var thresholdText: String
    @State private var alertTime: String
    @State private var selectedCategoryIds: [String]
    @State private var selectedLabels: [String]
    @State private var period: String
    @State private var saving = false
    @State private var errorText: String?
    @State private var showingDeleteConfirm = false

    init(budget: BudgetsViewModel.BudgetUiModel, viewModel: BudgetsViewModel, onDeleted: @escaping () -> Void = {}) {
        self.budget = budget
        self.viewModel = viewModel
        self.onDeleted = onDeleted
        _name = State(initialValue: budget.rawName)
        _limitText = State(initialValue: budget.limitMajor)
        _thresholdText = State(initialValue: String(budget.thresholdPct))
        _alertTime = State(initialValue: budget.alertTimeLocal)
        _selectedCategoryIds = State(initialValue: budget.categoryIds)
        _selectedLabels = State(initialValue: budget.labelNames)
        _period = State(initialValue: budget.period)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Budget name (optional)")) {
                    TextField("Falls back to the category/label scope", text: $name)
                }

                Section(header: Text("Limit (\(budget.currency))")) {
                    TextField("0", text: $limitText)
                        .keyboardType(.decimalPad)
                }

                Section(header: Text("Alert")) {
                    HStack {
                        Text("At")
                        TextField("80", text: $thresholdText)
                            .keyboardType(.numberPad)
                            .frame(width: 50)
                        Text("% of limit")
                        Spacer()
                        DatePicker("", selection: Binding(
                            get: { timeStringToDate(alertTime) },
                            set: { alertTime = dateToTimeString($0) }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    }
                }

                Section(header: Text("Categories (optional)")) {
                    BudgetCategoryMultiSelect(options: viewModel.expenseCategories, selectedIds: $selectedCategoryIds)
                }

                Section(header: Text("Labels (optional)")) {
                    LabelPickerRow(available: viewModel.labels.map(\.name), selected: $selectedLabels)
                }

                // Period chips only for a recurring budget -- a custom-dated
                // one can't be converted back to recurring from the edit
                // form, matching web's `{!budget.start_date && <chips>}`.
                if !budget.isCustomDated {
                    Section(header: Text("Recurrence")) {
                        HStack(spacing: 6) {
                            ForEach(["daily", "weekly", "monthly", "yearly"], id: \.self) { p in
                                Button(p.capitalized) { period = p }
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(period == p ? Color.accent : Color.surface2)
                                    .foregroundColor(period == p ? .white : Color.text)
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundColor(Color.negative)
                    }
                }

                Section {
                    Button(action: save) {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Save Changes")
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
                        Text("Delete Budget")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                }
            }
            .confirmationDialog("Delete this budget?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.delete(id: budget.id)
                        onDeleted()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func save() {
        saving = true
        errorText = nil
        Task {
            let err = await viewModel.update(
                id: budget.id,
                name: name,
                limitMajorText: limitText,
                currency: budget.currency,
                period: period,
                thresholdPctText: thresholdText,
                alertTimeLocal: alertTime,
                categoryIds: selectedCategoryIds,
                labelNames: selectedLabels
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
