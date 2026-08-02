import SwiftUI

struct CreateTransactionView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var description: String = ""
    @State private var transactionType = 0 // 0: Expense, 1: Income, 2: Transfer
    @State private var selectedCategory: String = "Food & Dining"
    @State private var selectedAccount: String = "HDFC Savings"

    let categories = ["Food & Dining", "Groceries", "Shopping", "Transport", "Bills & Utilities", "Salary", "Transfer"]
    let accounts = ["HDFC Savings", "SBI Salary Account", "ICICI Credit Card", "Cash Wallet"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $transactionType) {
                        Text("Expense").tag(0)
                        Text("Income").tag(1)
                        Text("Transfer").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Amount")) {
                    HStack {
                        Text("₹")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Color.accent)
                        TextField("0.00", text: $amountText)
                            .font(.system(size: 28, weight: .bold))
                            .keyboardType(.decimalPad)
                    }
                }

                Section(header: Text("Details")) {
                    TextField("Description (e.g. Swiggy Lunch)", text: $description)

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }

                    Picker("Account", selection: $selectedAccount) {
                        ForEach(accounts, id: \.self) { acct in
                            Text(acct).tag(acct)
                        }
                    }
                }

                Section {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Save Transaction")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(Color.surface)
                    }
                    .listRowBackground(Color.accent)
                }
            }
            .navigationTitle("New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                }
            }
        }
    }
}

#Preview {
    CreateTransactionView()
}
