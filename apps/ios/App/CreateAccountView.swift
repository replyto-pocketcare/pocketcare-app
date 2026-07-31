import SwiftUI

struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedType: String = "savings"
    @State private var currency: String = "INR"
    @State private var openingBalance: String = "0"
    @State private var allowNegative: Bool = false
    @State private var includeInNetWorth: Bool = true

    let types = [
        ("savings", "Savings Account"),
        ("current", "Current Account"),
        ("credit_card", "Credit Card"),
        ("cash", "Cash Wallet"),
        ("stocks", "Stocks"),
        ("mutual_funds", "Mutual Funds")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Account Details")) {
                    TextField("Account Name (e.g. HDFC Savings)", text: $name)

                    Picker("Account Type", selection: $selectedType) {
                        ForEach(types, id: \.0) { key, label in
                            Text(label).tag(key)
                        }
                    }

                    Picker("Currency", selection: $currency) {
                        Text("INR (₹)").tag("INR")
                        Text("USD ($)").tag("USD")
                        Text("EUR (€)").tag("EUR")
                        Text("GBP (£)").tag("GBP")
                    }
                }

                Section(header: Text("Initial Balance")) {
                    TextField("Opening Balance (₹)", text: $openingBalance)
                        .keyboardType(.numberPad)
                }

                Section(header: Text("Preferences")) {
                    Toggle("Allow Overdraft / Negative Balance", isOn: $allowNegative)
                    Toggle("Include in Net Worth", isOn: $includeInNetWorth)
                }

                Section {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Save Account")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(Theme.cream)
                    }
                    .listRowBackground(Theme.terracotta)
                }
            }
            .navigationTitle("New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.inkSoft)
                }
            }
        }
    }
}

#Preview {
    CreateAccountView()
}
