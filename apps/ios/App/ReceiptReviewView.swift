import SwiftUI
import Domain

private let lineKinds = ["item", "tax", "service_charge", "tip", "discount"]

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
                    Text(viewModel.error ?? "That scan is no longer available.")
                        .foregroundColor(.text2)
                        .padding()
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Check the details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel).foregroundColor(.text2) }
            }
        }
        .task(id: scanId) { await viewModel.load(scanId) }
        .onChange(of: viewModel.savedTransactionId) { _, newValue in
            if let id = newValue { onSaved(id) }
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
                        TextField("Merchant", text: Binding(get: { draft.merchant ?? "" }, set: { viewModel.setMerchant($0) }))
                        TextField("Date (YYYY-MM-DD)", text: Binding(get: { draft.occurredAt ?? "" }, set: { viewModel.setOccurredAt($0) }))
                        Text("PAID FROM").font(.caption2).foregroundColor(.text2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.accounts, id: \.id) { a in
                                    chip(a.name, selected: viewModel.accountId == a.id) { viewModel.accountId = a.id }
                                }
                            }
                        }
                        Text("CATEGORY").font(.caption2).foregroundColor(.text2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip("Uncategorised", selected: viewModel.categoryId == nil) { viewModel.categoryId = nil }
                                ForEach(viewModel.categories, id: \.id) { c in
                                    chip(c.name, selected: viewModel.categoryId == c.id) { viewModel.categoryId = c.id }
                                }
                            }
                        }
                    }
                }

                Text("Items & charges").font(.headline).fontWeight(.bold).foregroundColor(.text)
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
                            subtotalRow("Items", subs.items, draft.currency)
                            if subs.discount != 0 { subtotalRow("Discount", subs.discount, draft.currency) }
                            if subs.serviceCharge != 0 { subtotalRow("Service charge", subs.serviceCharge, draft.currency) }
                            if subs.tax != 0 { subtotalRow("Tax", subs.tax, draft.currency) }
                            if subs.tip != 0 { subtotalRow("Tip", subs.tip, draft.currency) }
                        }
                        TextField(
                            "Total on the receipt",
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
                                            ? "Enter the total printed on the receipt."
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

                PocketCard {
                    VStack(alignment: .leading, spacing: 10) {
                        // "Split this bill" is intentionally disabled here --
                        // pairs with automatic split detection (task #63/64).
                        // See receipt-scan.md scope note #5.
                        Text("Split this bill — coming soon")
                            .font(.caption)
                            .foregroundColor(.text2)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.surface2)
                            .clipShape(Capsule())
                        if let error = viewModel.error {
                            Text(error).foregroundColor(.negative).font(.caption)
                        }
                        PrimaryButton(viewModel.saving ? "Saving\u{2026}" : "Save transaction") {
                            viewModel.saveAsTransaction()
                        }
                        .disabled(!canSave)
                        if !balanced {
                            Text("The lines need to add up to the total before this can be saved.")
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
                    TextField("Description", text: Binding(
                        get: { line.description },
                        set: { v in viewModel.updateLine(line.id) { copyLine($0, description: v) } }
                    ))
                    Button(action: { viewModel.removeLine(line.id) }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.text2)
                    }
                }
                HStack(spacing: 10) {
                    TextField("Qty", text: Binding(
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
                    TextField("Amount", text: Binding(
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
