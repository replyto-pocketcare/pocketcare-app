import SwiftUI

struct StatementTxnUiItem: Identifiable {
    let id: String
    let date: String
    let narration: String
    let amountFormatted: String
    let isDebit: Bool
    let category: String
}

struct StatementImportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var fileSelected = "HDFC_Statement_July2026.pdf"
    @State private var selectedAccount = "HDFC Primary Savings (*4821)"

    let parsedTxns = [
        StatementTxnUiItem(id: "1", date: "30 Jul 2026", narration: "UPI/Swiggy/29841029", amountFormatted: "-₹640", isDebit: true, category: "Food & Dining"),
        StatementTxnUiItem(id: "2", date: "28 Jul 2026", narration: "SALARY CREDIT ACME CORP", amountFormatted: "+₹1,25,000", isDebit: false, category: "Income"),
        StatementTxnUiItem(id: "3", date: "25 Jul 2026", narration: "UPI/Airtel Broadband/58129", amountFormatted: "-₹1,179", isDebit: true, category: "Bills & Utilities"),
        StatementTxnUiItem(id: "4", date: "22 Jul 2026", narration: "POS DMART SUPERMARKET", amountFormatted: "-₹4,320", isDebit: true, category: "Groceries")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Statement File")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("📄 Selected: \(fileSelected)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Text("Target: \(selectedAccount)")
                            .font(.caption)
                            .foregroundColor(Theme.inkSoft)
                    }

                    Text("✓ 4 Transactions Parsed • Zero Checksum Drift")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.sage)
                }

                Section(header: Text("Parsed Transactions Preview")) {
                    ForEach(parsedTxns) { txn in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(txn.narration)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("\(txn.date) • \(txn.category)")
                                    .font(.caption)
                                    .foregroundColor(Theme.inkSoft)
                            }
                            Spacer()
                            Text(txn.amountFormatted)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(txn.isDebit ? Theme.terracotta : Theme.sage)
                        }
                    }
                }

                Section {
                    Button(action: { dismiss() }) {
                        Text("Import & Reconcile Transactions")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(Theme.cream)
                    }
                    .listRowBackground(Theme.terracotta)
                }
            }
            .navigationTitle("Import Bank Statement")
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
    StatementImportView()
}
