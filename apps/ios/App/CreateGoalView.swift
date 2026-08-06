import SwiftUI

private let GOAL_CURRENCIES = ["INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED"]

/// Real create form, matching apps/web/app/goals/page.tsx's inline "New
/// goal" card field-for-field per docs/mobile/screen-specs/goals.md. Was
/// the same "Save calls dismiss(), persists nothing" bug already found and
/// fixed in CreateAccountView.swift/CreateTransactionView.swift, plus
/// invented fields (free-text "Target Date", an "Initial Allocation"
/// concept absent from the real form) -- rewritten to the real field set:
/// name, target + currency, alert time, EF checkbox (only when no EF goal
/// exists yet).
struct CreateGoalView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: GoalsViewModel

    @State private var name = ""
    @State private var targetText = ""
    @State private var currency = "INR"
    @State private var isEmergencyFund = false
    @State private var alertTime = "09:00"
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Goal name")) {
                    TextField("e.g. Emergency Fund", text: $name)
                }

                Section(header: Text("Target amount")) {
                    HStack {
                        TextField("0", text: $targetText)
                            .keyboardType(.decimalPad)
                        Picker("Currency", selection: $currency) {
                            ForEach(GOAL_CURRENCIES, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section(header: Text("Alert")) {
                    DatePicker("Alert time", selection: Binding(
                        get: { timeStringToDate(alertTime) },
                        set: { alertTime = dateToTimeString($0) }
                    ), displayedComponents: .hourAndMinute)
                }

                if !viewModel.hasEmergencyFund {
                    Section {
                        Toggle("This is my emergency fund", isOn: $isEmergencyFund)
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundColor(Color.negative) }
                }

                Section {
                    Button(action: save) {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Create Goal")
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
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(Color.text2)
                }
            }
        }
    }

    private func save() {
        saving = true
        errorText = nil
        Task {
            let err = await viewModel.create(
                name: name,
                targetMajorText: targetText,
                currency: currency,
                isEmergencyFund: isEmergencyFund,
                alertTimeLocal: alertTime
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

#Preview {
    CreateGoalView(viewModel: GoalsViewModel())
}
