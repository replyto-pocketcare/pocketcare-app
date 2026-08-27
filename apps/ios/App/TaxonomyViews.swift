import SwiftUI
import Data
import Domain

/// Manage categories — ported from apps/web/app/settings/categories/page.tsx.
///
/// Reached from Settings, as on web. The tree is Domain's, vector-tested; this
/// file is the rows, the inline rename and the add row.
struct CategoriesView: View {
    @State private var viewModel = CategoriesViewModel()
    @State private var editingId: String?
    @State private var editingName = ""
    @State private var pendingDelete: TaxonomyCategory?

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            SanvyaPage(S.Categories.title) {
                SanvyaCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        SanvyaInput(text: $vm.search, placeholder: S.Categories.searchPlaceholder)
                        tree
                        addRow()
                    }
                }
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
        .confirmationDialog(
            S.Categories.deleteTitle,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { category in
            // Web's confirm dialog labels its confirm button "Delete" and its
            // cancel "Cancel" — the shared common strings, not this screen's.
            Button(S.Translation.commonDelete, role: .destructive) { viewModel.delete(category.id) }
            Button(S.Categories.cancel, role: .cancel) {}
        } message: { category in
            Text(S.Categories.deleteMsg(name: category.name))
        }
    }

    @ViewBuilder
    private var tree: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.nodes) { node in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        // The disclosure control is a plain +/− box on web, not
                        // a chevron; keeping the glyph keeps the two platforms
                        // and the browser saying the same thing.
                        Button {
                            viewModel.toggle(node.category.id)
                        } label: {
                            Text(node.isOpen ? "−" : "+")
                                .sanvyaStyle(SanvyaType.statLabel)
                                .foregroundStyle(Color.text2)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(node.isOpen ? S.Categories.collapse : S.Categories.expand)
                        // A forced-open parent (there is a search) cannot be
                        // collapsed on web either — the control is still drawn,
                        // and tapping it changes state that only takes effect
                        // once the search is cleared.
                        categoryRow(node.category, childCount: node.childCount, indent: false)
                    }
                    if node.isOpen {
                        ForEach(node.children) { child in
                            categoryRow(child, childCount: nil, indent: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: TaxonomyCategory, childCount: Int?, indent: Bool) -> some View {
        if editingId == category.id {
            HStack(spacing: 8) {
                SanvyaInput(text: $editingName, placeholder: S.Categories.name)
                SanvyaChip(S.Categories.save, isActive: false) {
                    viewModel.rename(category.id, to: editingName)
                    editingId = nil
                }
                SanvyaChip(S.Categories.cancel, isActive: false) { editingId = nil }
            }
            .padding(.leading, indent ? 26 : 0)
        } else {
            HStack(spacing: 6) {
                Text(indent ? "↳ \(category.name)" : category.name)
                    .sanvyaStyle(indent ? SanvyaType.statLabel : SanvyaType.body)
                    .foregroundStyle(indent ? Color.text2 : Color.text)
                    .lineLimit(1)
                if !indent {
                    Text(kindLabel(category.kind) + (childCount.map { $0 > 0 ? " · \($0)" : "" } ?? ""))
                        .sanvyaStyle(SanvyaType.statLabel)
                        .foregroundStyle(Color.text2)
                }
                Spacer(minLength: 0)
                SanvyaChip(S.Categories.edit, isActive: false) {
                    editingName = category.name
                    editingId = category.id
                }
                SanvyaChip("×", isActive: false) { pendingDelete = category }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, indent ? 5 : 6)
            .padding(.leading, indent ? 16 : 0)
            .overlay {
                if !indent {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.border, lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func addRow() -> some View {
        @Bindable var vm = viewModel
        VStack(alignment: .leading, spacing: 8) {
            SanvyaInput(text: $vm.newName, placeholder: S.Categories.newCategory)
            FlowLayout(spacing: 8) {
                SanvyaChip(S.Categories.expense, isActive: viewModel.newKind == "expense") {
                    viewModel.newKind = "expense"
                }
                SanvyaChip(S.Categories.income, isActive: viewModel.newKind == "income") {
                    viewModel.newKind = "income"
                }
            }
            // Chips, not a wheel — the same choice RecurringFormView makes, and
            // web's own `<select>` has exactly this shape: an empty first
            // option meaning "top level", then one per top-level category.
            FlowLayout(spacing: 8) {
                SanvyaChip(S.Categories.topLevel, isActive: viewModel.newParentId.isEmpty) {
                    viewModel.newParentId = ""
                }
                ForEach(viewModel.parentOptions) { option in
                    SanvyaChip(
                        S.Categories.under(name: option.name),
                        isActive: viewModel.newParentId == option.id
                    ) { viewModel.newParentId = option.id }
                }
            }
            SanvyaButton(action: { viewModel.add() }) { Text(S.Categories.add) }
                .disabled(!viewModel.canAdd)
        }
    }

    private func kindLabel(_ kind: String) -> String {
        kind == "income" ? S.Categories.kindIncome : S.Categories.kindExpense
    }
}

/// Manage labels — ported from apps/web/app/settings/labels/page.tsx.
struct LabelsView: View {
    @State private var viewModel = LabelsViewModel()
    @State private var editingId: String?
    @State private var editingName = ""
    @State private var editingColor = LabelsViewModel.defaultColor
    @State private var pendingDelete: LabelRowView.Model?

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            SanvyaPage(S.Labels.title) {
                SanvyaCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        SanvyaInput(text: $vm.search, placeholder: S.Labels.searchPlaceholder)

                        if viewModel.labels.isEmpty {
                            Text(S.Labels.noLabels)
                                .sanvyaStyle(SanvyaType.statLabel)
                                .foregroundStyle(Color.text2)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(viewModel.labels, id: \.id) { label in
                                    row(label)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SanvyaInput(text: $vm.newName, placeholder: S.Labels.newLabel)
                            // The SAME swatch row the account form uses, not a
                            // free colour well. Web's `<input type="color">`
                            // has no Compose equivalent, and building one on
                            // iOS alone would put the two platforms out of step
                            // over a control neither spec has settled — the
                            // same call RecurringFormView made about dates.
                            // The palette is web's own ACCOUNT_COLORS, and it
                            // cannot produce white-on-white the way a free
                            // picker can. Recorded in PARITY_AUDIT.
                            ColorSwatchRow(selected: viewModel.newColor) { viewModel.newColor = $0 }
                            SanvyaButton(action: { viewModel.add() }) { Text(S.Labels.addLabel) }
                                .disabled(!viewModel.canAdd)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
        .confirmationDialog(
            S.Labels.deleteTitle,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { label in
            Button(S.Translation.commonDelete, role: .destructive) { viewModel.delete(label.id) }
            Button(S.Labels.cancel, role: .cancel) {}
        } message: { label in
            Text(S.Labels.deleteMsg(name: label.name))
        }
    }

    @ViewBuilder
    private func row(_ label: LabelRow) -> some View {
        if editingId == label.id {
            HStack(spacing: 10) {
                SanvyaInput(text: $editingName)
                ColorSwatchRow(selected: editingColor) { editingColor = $0 }
                SanvyaChip(S.Labels.save, isActive: false) {
                    viewModel.save(label.id, name: editingName, color: editingColor)
                    editingId = nil
                }
                SanvyaChip(S.Labels.cancel, isActive: false) { editingId = nil }
            }
            .padding(12)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.border, lineWidth: 1)
            }
        } else {
            LabelRowView(
                model: .init(id: label.id, name: label.name, color: label.color ?? LabelsViewModel.defaultColor),
                onEdit: {
                    editingName = label.name
                    editingColor = label.color ?? LabelsViewModel.defaultColor
                    editingId = label.id
                },
                onDelete: { pendingDelete = .init(id: label.id, name: label.name, color: label.color ?? LabelsViewModel.defaultColor) }
            )
        }
    }
}

/// One label, read-only. Its own view because the list and the delete
/// confirmation both need the same three fields.
struct LabelRowView: View {
    struct Model: Identifiable, Equatable {
        let id: String
        let name: String
        let color: String
    }

    let model: Model
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: model.color) ?? Color.accent)
                .frame(width: 14, height: 14)
            Text(model.name)
                .sanvyaStyle(SanvyaType.body)
                .foregroundStyle(Color.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onEdit) {
                SanvyaIconView(SanvyaIcons.edit, size: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(S.Labels.edit)
            Button(action: onDelete) {
                SanvyaIconView(SanvyaIcons.delete, size: 18)
                    .foregroundStyle(Color.negative)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(S.Labels.delete)
        }
        .padding(12)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.border, lineWidth: 1)
        }
    }
}
