import SwiftUI

private let budgetCurrencies = FormOptions.currencies
private let budgetPeriods = FormOptions.periods

private func periodChipLabel(_ p: String) -> String {
    switch p {
    case "daily": return "Daily"
    case "weekly": return "Weekly"
    case "yearly": return "Yearly"
    default: return "Monthly"
    }
}

/// Real create form, matching apps/web/app/budgets/page.tsx's "New budget"
/// modal field-for-field per docs/mobile/screen-specs/budgets.md. Replaces
/// the previous version, which was the same "Save calls dismiss(), never
/// touches the repository" bug already found and fixed on Accounts/
/// Transactions this engagement (found again here 2026-08-06, task #24).
struct CreateBudgetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = BudgetsViewModel()

    @State private var name = ""
    @State private var limitText = ""
    @State private var currency = FormOptions.defaultCurrency
    @State private var thresholdText = "80"
    @State private var alertTime = "09:00"
    @State private var selectedCategoryIds: [String] = []
    @State private var selectedLabels: [String] = []
    @State private var isCustomDated = false
    @State private var period = "monthly"
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Budget name (optional)")) {
                    TextField("Falls back to the category/label scope", text: $name)
                }

                Section(header: Text("Limit")) {
                    HStack {
                        TextField("0", text: $limitText)
                            .keyboardType(.decimalPad)
                        Picker("", selection: $currency) {
                            ForEach(budgetCurrencies, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 90)
                    }
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

                Section(header: Text("Timeframe")) {
                    Picker("", selection: $isCustomDated) {
                        Text("Recurring").tag(false)
                        Text("Custom dates").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if !isCustomDated {
                        HStack(spacing: 6) {
                            ForEach(budgetPeriods, id: \.self) { p in
                                Button(periodChipLabel(p)) { period = p }
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(period == p ? Color.accent : Color.surface2)
                                    .foregroundColor(period == p ? .white : Color.text)
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                    } else {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
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
                            Text("Create Budget")
                                .font(.headline)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundColor(Color.surface)
                        }
                    }
                    .disabled(saving)
                    .listRowBackground(Color.accent)
                }
            }
            .navigationTitle("New Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                }
            }
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.cancel() }
        }
    }

    private func save() {
        saving = true
        errorText = nil
        Task {
            let isoFormatter = DateFormatter()
            isoFormatter.dateFormat = "yyyy-MM-dd"
            let err = await viewModel.create(
                name: name,
                limitMajorText: limitText,
                currency: currency,
                thresholdPctText: thresholdText,
                alertTimeLocal: alertTime,
                categoryIds: selectedCategoryIds,
                labelNames: selectedLabels,
                isCustomDated: isCustomDated,
                period: period,
                startDate: isCustomDated ? isoFormatter.string(from: startDate) : nil,
                endDate: isCustomDated ? isoFormatter.string(from: endDate) : nil
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

/// Toggleable-chip multi-select over expense categories -- native-idiomatic
/// equivalent of web's <MultiSelect>, matching FlowLayout's established
/// wrapping-chip-row pattern (TransactionFormComponents.swift's
/// LabelPickerRow, same idea, different data source since categories need
/// id-based not name-based selection).
struct BudgetCategoryMultiSelect: View {
    let options: [BudgetsViewModel.CategoryOption]
    @Binding var selectedIds: [String]

    var body: some View {
        if options.isEmpty {
            Text("No expense categories yet").foregroundColor(Color.text2).font(.caption)
        } else {
            FlowLayout(spacing: 8) {
                ForEach(options) { option in
                    let isSelected = selectedIds.contains(option.id)
                    Button(option.name) { toggle(option.id) }
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.accent : Color.surface2)
                        .foregroundColor(isSelected ? .white : Color.text)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if let idx = selectedIds.firstIndex(of: id) { selectedIds.remove(at: idx) } else { selectedIds.append(id) }
    }
}

/// "HH:MM" <-> Date helpers for the alert-time DatePicker -- local
/// wall-clock time only (no timezone conversion here; that happens in
/// BudgetsViewModel's localToUtcTime at save time).
func timeStringToDate(_ s: String) -> Date {
    let parts = s.split(separator: ":")
    var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    comps.hour = parts.count == 2 ? Int(parts[0]) : 9
    comps.minute = parts.count == 2 ? Int(parts[1]) : 0
    return Calendar.current.date(from: comps) ?? Date()
}

func dateToTimeString(_ date: Date) -> String {
    let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", comps.hour ?? 9, comps.minute ?? 0)
}

#Preview {
    CreateBudgetView()
}
