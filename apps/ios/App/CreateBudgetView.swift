import SwiftUI

struct CreateBudgetView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var limitText: String = ""
    @State private var period: String = "monthly"

    let periods = ["monthly", "weekly", "yearly"]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Budget Info")) {
                    TextField("Budget Name (e.g. Monthly Dining)", text: $name)

                    Picker("Recurrence Period", selection: $period) {
                        Text("Monthly").tag("monthly")
                        Text("Weekly").tag("weekly")
                        Text("Yearly").tag("yearly")
                    }
                }

                Section(header: Text("Limit Amount")) {
                    HStack {
                        Text("₹")
                            .font(.headline)
                            .foregroundColor(Color.accent)
                        TextField("8000", text: $limitText)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Create Budget")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(Color.surface)
                    }
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
        }
    }
}

#Preview {
    CreateBudgetView()
}
