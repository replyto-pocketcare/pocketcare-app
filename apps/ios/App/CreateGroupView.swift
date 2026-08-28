import SwiftUI

/// Real port of web's "New group" modal (task #30). Was previously a dead
/// mockup -- `Create` just called `dismiss()`, no member picker, no
/// currency, nothing persisted.
struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: SplitsViewModel
    let onCreated: (String) -> Void

    @State private var name: String = ""
    @State private var kind: String = "group"
    @State private var currency: String = FormOptions.defaultCurrency
    @State private var selectedMembers: Set<String> = []
    // Web's two `<input type="date">`s can be empty; a SwiftUI DatePicker
    // cannot. `hasDates` is that empty state, made explicit.
    @State private var hasDates = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var auto = false
    @State private var error: String?
    @State private var saving = false

    private var startIso: String { hasDates ? IsoDay.string(from: start) : "" }
    private var endIso: String { hasDates ? IsoDay.string(from: end) : "" }
    private var kindLabel: String { kind == "trip" ? S.Groups.kindTrip : S.Groups.kindGroup }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        Text(S.Groups.kindGroup).tag("group")
                        Text(S.Groups.kindTrip).tag("trip")
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Details")) {
                    TextField(kind == "trip" ? "Trip name (e.g. Goa Trip)" : "Group name (e.g. Roommates)", text: $name)
                    Picker(S.Accounts.currency, selection: $currency) {
                        // Was a hand-written three-item list — the only picker
                        // in the app that offered fewer than the other nine.
                        ForEach(FormOptions.currencies, id: \.self) { Text($0).tag($0) }
                    }
                }

                // Web's date range and its auto-split checkbox. Without them a
                // trip created on mobile could never auto-split: the flag is
                // only settable against a range, and the range was only
                // settable from the edit sheet, which most users never open.
                Section(header: Text(S.Groups.datesOptional)) {
                    Toggle(S.Groups.datesOptional, isOn: $hasDates)
                    if hasDates {
                        DatePicker(S.Statements.fromDate, selection: $start, displayedComponents: .date)
                        // `in: start...` is web's `min={start}`: an inverted
                        // range matches no transaction at all.
                        DatePicker(S.Statements.toDate, selection: $end, in: start..., displayedComponents: .date)
                        Toggle(isOn: $auto) {
                            Text(S.Groups.autoSplitCreate(kind: kindLabel))
                                .font(.caption).foregroundColor(.text2)
                        }
                    }
                }

                Section(header: Text("Add members")) {
                    if viewModel.connections.isEmpty {
                        Text("No connections yet — you can add members later.").font(.caption).foregroundColor(.text2)
                    } else {
                        ForEach(viewModel.connections, id: \.id) { c in
                            Button(action: { toggle(c.id) }) {
                                HStack {
                                    Text(c.name).foregroundColor(.text)
                                    Spacer()
                                    if selectedMembers.contains(c.id) { Image(systemName: "checkmark").foregroundColor(.accent) }
                                }
                            }
                        }
                    }
                }

                if let error { Text(error).foregroundColor(.negative).font(.caption) }

                Section {
                    Button(action: create) {
                        Text(saving ? "Creating\u{2026}" : "Create \(kind.capitalized)")
                            .font(.headline).fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(Color.surface)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                    .listRowBackground(Color.accent)
                }
            }
            .navigationTitle(kind == "trip" ? "New Trip" : S.Recurring.groupNewCta)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Groups.cancel) { dismiss() }
                        .foregroundColor(Color.text2)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedMembers.contains(id) { selectedMembers.remove(id) } else { selectedMembers.insert(id) }
    }

    private func create() {
        saving = true
        Task {
            let id = await viewModel.createGroup(
                name: name.trimmingCharacters(in: .whitespaces),
                kind: kind,
                currency: currency,
                memberIds: Array(selectedMembers),
                startDate: startIso,
                endDate: endIso,
                autoSplit: auto
            )
            saving = false
            if let id {
                onCreated(id)
            } else {
                error = "Couldn't create the group."
            }
        }
    }
}

#Preview {
    CreateGroupView(viewModel: SplitsViewModel(), onCreated: { _ in })
}
