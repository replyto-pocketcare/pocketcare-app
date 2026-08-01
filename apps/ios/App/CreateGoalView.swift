import SwiftUI

struct CreateGoalView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var targetText: String = ""
    @State private var targetDate: String = "Dec 2026"
    @State private var initialAllocationText: String = "0"

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Goal Details")) {
                    TextField("Goal Name (e.g. Emergency Fund)", text: $name)
                    TextField("Target Date (e.g. Dec 2026)", text: $targetDate)
                }

                Section(header: Text("Target Amount")) {
                    HStack {
                        Text("₹")
                            .font(.headline)
                            .foregroundColor(Theme.terracotta)
                        TextField("500000", text: $targetText)
                            .keyboardType(.numberPad)
                    }
                }

                Section(header: Text("Initial Allocation")) {
                    HStack {
                        Text("₹")
                            .font(.headline)
                            .foregroundColor(Theme.sage)
                        TextField("0", text: $initialAllocationText)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Create Goal")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(Theme.cream)
                    }
                    .listRowBackground(Theme.terracotta)
                }
            }
            .navigationTitle("New Goal")
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
    CreateGoalView()
}
