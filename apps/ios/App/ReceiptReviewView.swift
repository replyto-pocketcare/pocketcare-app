import SwiftUI
import Domain

private let lineKinds = ["item", "tax", "service_charge", "tip", "discount"]

/// `.fullScreenCover(item:)` needs `Identifiable`, and a bare group id string
/// is not one.
private struct SplitTarget: Identifiable {
    let groupId: String
    var id: String { groupId }
}

/// Real port of apps/web/app/receipts/review/page.tsx (task #62). See
/// docs/mobile/screen-specs/receipt-scan.md.
struct ReceiptReviewView: View {
    let scanId: String
    let onSaved: (String) -> Void
    let onCancel: () -> Void

    @State private var viewModel = ReceiptReviewViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let draft = viewModel.draft {
                    content(draft)
                } else {
                    Text(viewModel.error ?? S.Receipts.reviewNotFound)
                        .foregroundColor(.text2)
                        .padding()
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(S.Receipts.reviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(S.Translation.commonCancel, action: onCancel).foregroundColor(.text2) }
            }
        }
        .task(id: scanId) { await viewModel.load(scanId) }
        .onChange(of: viewModel.savedTransactionId) { _, newValue in
            if let id = newValue { onSaved(id) }
        }
        // A cover, not a push: the split screen is a second full task with its
        // own save, and leaving it must not drop you back mid-review with a
        // half-written expense behind you.
        .fullScreenCover(item: Binding(
            get: { viewModel.splitGroupId.map(SplitTarget.init(groupId:)) },
            set: { if $0 == nil { viewModel.splitGroupId = nil } }
        )) { target in
            SplitReceiptView(
                scanId: scanId,
                groupId: target.groupId,
                accountId: viewModel.accountId ?? "",
                categoryId: viewModel.categoryId ?? "",
                onSaved: { _ in onCancel() },
                onCancel: { viewModel.splitGroupId = nil }
            )
        }
    }

    private var primaryLabel: String {
        if viewModel.saving { return "\u{2026}" }
        return viewModel.wantsSplit ? S.Receipts.reviewContinueToSplit : S.Receipts.reviewSave
    }

    /// Pick an existing group, or name a new one. Web uses a `<select>` whose
    /// empty option means "create a new group"; the same shape reads better on
    /// a phone as a chip row, so the "new group" field appears when nothing is
    /// selected rather than behind a placeholder option.
    @ViewBuilder
    private var splitPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(S.Receipts.reviewGroup)
                .font(.caption)
                .foregroundColor(.text2)
            FlowLayout(spacing: 6) {
                SanvyaChip(S.Receipts.reviewNewGroup, isActive: viewModel.groupId.isEmpty) {
                    viewModel.groupId = ""
                }
                ForEach(viewModel.groups, id: \.id) { g in
                    SanvyaChip(g.name, isActive: viewModel.groupId == g.id) {
                        viewModel.groupId = g.id
                        viewModel.newGroupName = ""
                    }
                }
            }
            if viewModel.groupId.isEmpty {
                Text(S.Receipts.reviewNewGroupName)
                    .font(.caption)
                    .foregroundColor(.text2)
                SanvyaInput(
                    text: Binding(get: { viewModel.newGroupName }, set: { viewModel.newGroupName = $0 }),
                    placeholder: S.Receipts.reviewNewGroupPlaceholder
                )
            }
            Text(S.Receipts.reviewSplitNote)
                .font(.caption2)
                .foregroundColor(.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func content(_ draft: ReceiptDraft) -> some View {
        let rec = viewModel.reconcileResult()
        let subs = viewModel.subtotalsResult()
        let balanced = rec?.ok ?? false
        let canSave = balanced && viewModel.accountId != nil && !viewModel.saving

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PocketCard {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(S.Receipts.reviewMerchant, text: Binding(get: { draft.merchant ?? "" }, set: { viewModel.setMerchant($0) }))
                        TextField("Date (YYYY-MM-DD)", text: Binding(get: { draft.occurredAt ?? "" }, set: { viewModel.setOccurredAt($0) }))
                        Text(S.Receipts.reviewAccount).font(.caption2).foregroundColor(.text2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.accounts, id: \.id) { a in
                                    chip(a.name, selected: viewModel.accountId == a.id) { viewModel.accountId = a.id }
                                }
                            }
                        }
                        Text(S.Receipts.reviewCategory).font(.caption2).foregroundColor(.text2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip(S.Receipts.reviewNoCategory, selected: viewModel.categoryId == nil) { viewModel.categoryId = nil }
                                ForEach(viewModel.categories, id: \.id) { c in
                                    chip(c.name, selected: viewModel.categoryId == c.id) { viewModel.categoryId = c.id }
                                }
                            }
                        }
                    }
                }

                Text(S.Receipts.reviewItems).font(.headline).fontWeight(.bold).foregroundColor(.text)
                ForEach(draft.lines, id: \.id) { line in
                    lineEditor(line)
                }
                HStack(spacing: 10) {
                    Button("+ Add item") { viewModel.addLine("item") }.buttonStyle(.bordered)
                    Button("+ Add charge") { viewModel.addLine("tax") }.buttonStyle(.bordered)
                }

                PocketCard {
                    VStack(alignment: .leading, spacing: 10) {
                        if let subs {
                            subtotalRow(S.Receipts.reviewSubtotalItems, subs.items, draft.currency)
                            if subs.discount != 0 { subtotalRow(S.Receipts.kindDiscount, subs.discount, draft.currency) }
                            if subs.serviceCharge != 0 { subtotalRow(S.Receipts.kindServiceCharge, subs.serviceCharge, draft.currency) }
                            if subs.tax != 0 { subtotalRow(S.Receipts.kindTax, subs.tax, draft.currency) }
                            if subs.tip != 0 { subtotalRow(S.Receipts.kindTip, subs.tip, draft.currency) }
                        }
                        TextField(
                            S.Receipts.reviewTotal,
                            text: Binding(
                                get: { draft.total.map { formatMajor($0) } ?? "" },
                                set: { viewModel.setTotal(parseMajor($0)) }
                            )
                        )
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 200)

                        if let r = rec {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(
                                    balanced
                                        ? "Adds up: \(formatMoney(r.computed, draft.currency)) \u{2713}"
                                        : (r.reason == "missing_total"
                                            ? S.Receipts.reviewNeedTotal
                                            : "Lines add up to \(formatMoney(r.computed, draft.currency)), but the receipt says \(r.stated.map { formatMoney($0, draft.currency) } ?? "\u{2014}").")
                                )
                                .font(.caption)
                                .foregroundColor(.text)
                                if !balanced, r.reason == "mismatch" {
                                    HStack(spacing: 8) {
                                        Button("Add \(formatMoney(r.delta, draft.currency)) as a line") { viewModel.addDifferenceAsLine() }
                                            .buttonStyle(.borderedProminent)
                                        Button("Use \(formatMoney(r.computed, draft.currency))") { viewModel.useComputedTotal() }
                                            .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .padding(10)
                            .background(balanced ? Color.surface2 : Color.negative.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }

                // Record or split. This was a dead "Split this bill — coming
                // soon" pill, hardcoded in English, until the itemized write
                // path landed (2026-08-27). It is the real toggle now.
                PocketCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            SanvyaChip(S.Receipts.reviewJustRecord, isActive: !viewModel.wantsSplit) {
                                viewModel.wantsSplit = false
                            }
                            SanvyaChip(S.Receipts.reviewSplitIt, isActive: viewModel.wantsSplit) {
                                viewModel.wantsSplit = true
                            }
                        }

                        if viewModel.wantsSplit { splitPicker }

                        if let error = viewModel.error {
                            Text(error).foregroundColor(.negative).font(.caption)
                        }
                        PrimaryButton(primaryLabel) {
                            if viewModel.wantsSplit {
                                viewModel.continueToSplit()
                            } else {
                                viewModel.saveAsTransaction()
                            }
                        }
                        .disabled(!canSave)
                        if !balanced {
                            Text(S.Receipts.reviewMustBalance)
                                .font(.caption2).foregroundColor(.text2)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func lineEditor(_ line: ReceiptLine) -> some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField(S.Receipts.reviewDescription, text: Binding(
                        get: { line.description },
                        set: { v in viewModel.updateLine(line.id) { copyLine($0, description: v) } }
                    ))
                    Button(action: { viewModel.removeLine(line.id) }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.text2)
                    }
                }
                HStack(spacing: 10) {
                    TextField(S.Receipts.reviewQty, text: Binding(
                        get: { line.quantity.map { String(Double($0) / 1000.0) } ?? "" },
                        set: { v in
                            let n = Double(v.trimmingCharacters(in: .whitespaces))
                            let newQuantity: Int64? = (v.isEmpty || n == nil) ? nil : Int64((n! * 1000).rounded())
                            viewModel.updateLine(line.id) { l in
                                ReceiptLine(id: l.id, kind: l.kind, description: l.description, quantity: newQuantity, unit: l.unit, unitPrice: l.unitPrice, amount: l.amount, confidence: l.confidence)
                            }
                        }
                    ))
                    .keyboardType(.decimalPad)
                    TextField(S.Receipts.reviewAmount, text: Binding(
                        get: { formatMajor(line.amount) },
                        set: { v in
                            let minor = parseMajor(v) ?? 0
                            viewModel.updateLine(line.id) { copyLine($0, amount: $0.kind == "discount" ? -abs(minor) : abs(minor)) }
                        }
                    ))
                    .keyboardType(.decimalPad)
                }
                HStack(spacing: 6) {
                    ForEach(lineKinds, id: \.self) { k in
                        chip(k.replacingOccurrences(of: "_", with: " "), selected: line.kind == k) {
                            viewModel.updateLine(line.id) { l in
                                let amount = k == "discount" ? -abs(l.amount) : abs(l.amount)
                                return copyLine(l, kind: k, amount: amount)
                            }
                        }
                    }
                }
            }
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Color.accent.opacity(0.18) : Color.surface2)
                .foregroundColor(selected ? Color.accent : Color.text)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func subtotalRow(_ label: String, _ amountMinor: Int64, _ currency: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.text2)
            Spacer()
            Text(formatMoney(amountMinor, currency)).font(.caption)
        }
    }
}

/// `ReceiptLine` has no `Comparable`/`Equatable`-derived `.with(...)`
/// helper (it's a plain value type, no golden-vector reason to add one) --
/// this local copy-with mirrors web's `updateLine`'s spread-merge shape.
/// Only covers the fields this screen's editors actually change
/// (description/kind/amount, all "replace with a real value", never "clear
/// back to nil") -- quantity's "clear to nil" case is handled inline at its
/// one call site instead of forcing a double-optional parameter here.
private func copyLine(_ line: ReceiptLine, description: String? = nil, kind: String? = nil, amount: Int64? = nil) -> ReceiptLine {
    ReceiptLine(
        id: line.id,
        kind: kind ?? line.kind,
        description: description ?? line.description,
        quantity: line.quantity,
        unit: line.unit,
        unitPrice: line.unitPrice,
        amount: amount ?? line.amount,
        confidence: line.confidence
    )
}

private func formatMajor(_ minor: Int64, digits: Int = 2) -> String {
    let scale = pow(10.0, Double(digits))
    return String(format: "%.\(digits)f", Double(minor) / scale)
}

private func parseMajor(_ text: String, digits: Int = 2) -> Int64? {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    guard let n = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) else { return 0 }
    let scale = pow(10.0, Double(digits))
    return Int64((n * scale).rounded())
}

// formatMoney moved to App/Components/MoneyFormat.swift.
