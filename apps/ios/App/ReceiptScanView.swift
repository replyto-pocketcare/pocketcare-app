import SwiftUI

struct ReceiptLineItemUiItem: Identifiable {
    let id: String
    let description: String
    let quantity: Int
    let amountFormatted: String
    let assignedMember: String
}

struct ReceiptScanView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var merchant = "Olive Garden Restaurant"
    @State private var date = "01 Aug 2026"
    @State private var totalText = "3450"

    let lineItems = [
        ReceiptLineItemUiItem(id: "1", description: "Pasta Carbonara", quantity: 2, amountFormatted: "₹1,200", assignedMember: "You"),
        ReceiptLineItemUiItem(id: "2", description: "Margherita Pizza", quantity: 1, amountFormatted: "₹850", assignedMember: "Rahul"),
        ReceiptLineItemUiItem(id: "3", description: "Tiramisu Dessert", quantity: 2, amountFormatted: "₹600", assignedMember: "Priya"),
        ReceiptLineItemUiItem(id: "4", description: "Tax & Service Charge", quantity: 1, amountFormatted: "₹800", assignedMember: "Everyone (Proportional)")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        Text("📷 Photo / OCR Scan Attached")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.text)
                        Text("AI detected 4 line items with 100% confidence")
                            .font(.caption)
                            .foregroundColor(Color.text2)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }

                Section(header: Text("Receipt Details")) {
                    TextField("Merchant Name", text: $merchant)
                    HStack {
                        TextField("Total (₹)", text: $totalText)
                            .keyboardType(.numberPad)
                        TextField("Date", text: $date)
                    }
                }

                Section(header: Text("Itemized Line Items")) {
                    ForEach(lineItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.description)
                                    .font(.body)
                                    .fontWeight(.semibold)
                                Text("Qty: \(item.quantity) • Assigned: \(item.assignedMember)")
                                    .font(.caption)
                                    .foregroundColor(Color.text2)
                            }
                            Spacer()
                            Text(item.amountFormatted)
                                .font(.body)
                                .fontWeight(.bold)
                                .foregroundColor(Color.accent)
                        }
                    }
                }

                Section {
                    Button(action: { dismiss() }) {
                        Text("Save Receipt & Allocate Shares")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(Color.surface)
                    }
                    .listRowBackground(Color.accent)
                }
            }
            .navigationTitle("Receipt Scan & Split")
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
    ReceiptScanView()
}
