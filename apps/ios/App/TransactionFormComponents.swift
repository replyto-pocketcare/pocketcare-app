import SwiftUI
import Data

/// Shared pieces for Create/EditTransactionView — mirrors Android's
/// CategoryPicker.kt / the inline LabelPickerRow in
/// CreateTransactionScreen.kt (added the same session). Kept in its own
/// file per the Phase B "component reuse" rule.

/// Flat category picker ("Parent › Child" for children) -- a faithful-logic
/// (not pixel-identical widget) port of `SearchSelect`, matches
/// docs/mobile/screen-specs/transactions.md's New section note.
struct CategoryPickerView: View {
    let categories: [CategoryRow]
    @Binding var selectedId: String?

    var body: some View {
        let roots = categories.filter { $0.parentId == nil }
        Picker("Category", selection: $selectedId) {
            Text("Uncategorised").tag(String?.none)
            ForEach(roots, id: \.id) { parent in
                Text(parent.name).tag(String?.some(parent.id))
                ForEach(categories.filter { $0.parentId == parent.id }, id: \.id) { child in
                    Text("  \(parent.name) › \(child.name)").tag(String?.some(child.id))
                }
            }
        }
        .pickerStyle(.menu)
    }
}

/// Multi-select chip picker over existing labels + free-text add -- matches
/// LabelPicker's behavior (pick existing, or type a new name and add it).
struct LabelPickerRow: View {
    let available: [String]
    @Binding var selected: [String]
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let allNames = Array(Set(available + selected)).sorted()
            if !allNames.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(allNames, id: \.self) { name in
                        let isSelected = selected.contains(name)
                        Button(name) { toggle(name) }
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.accent : Color.surface2)
                            .foregroundColor(isSelected ? .white : Color.text)
                            .clipShape(Capsule())
                    }
                }
            }
            HStack {
                TextField("New label", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = draft.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty, !selected.contains(trimmed) { selected.append(trimmed) }
                    draft = ""
                }
            }
        }
    }

    private func toggle(_ name: String) {
        if let idx = selected.firstIndex(of: name) { selected.remove(at: idx) } else { selected.append(name) }
    }
}
