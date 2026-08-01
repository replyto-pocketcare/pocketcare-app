import SwiftUI

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var kind: String = "trip"
    @State private var startDate: String = ""
    @State private var endDate: String = ""
    @State private var autoSplit: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        Text("Trip").tag("trip")
                        Text("Group").tag("group")
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Details")) {
                    TextField(kind == "trip" ? "Trip Name (e.g. Goa Trip)" : "Group Name (e.g. Roommates)", text: $name)
                }

                Section(header: Text("Dates (Optional)")) {
                    TextField("Start Date", text: $startDate)
                    TextField("End Date", text: $endDate)
                }

                Section {
                    Toggle("Auto-split expenses during trip dates", isOn: $autoSplit)
                }

                Section {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Create \(kind.capitalized)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(Theme.cream)
                    }
                    .listRowBackground(Theme.terracotta)
                }
            }
            .navigationTitle(kind == "trip" ? "New Trip" : "New Group")
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
    CreateGroupView()
}
