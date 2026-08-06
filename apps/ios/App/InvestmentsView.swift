import SwiftUI

/// Ported from apps/web/app/investments/page.tsx per
/// docs/mobile/screen-specs/investments.md (task #26). Replaces the
/// previous flat, ungrouped, read-only list (whose "+" toolbar button was
/// a no-op `Button(action: {})`) with a real grouped-list/drill-in port
/// mirroring Android's InvestmentsScreen.kt.
///
/// Drill-in is local `@State` (which group tile is expanded), not a
/// pushed `NavigationStack` destination -- it's just a filtered view of
/// the same list, matching web's own DrillIn being page-local state
/// rather than a route (and matching Android's own in-screen approach).
/// Edit is inline within the holding row (web's own EditHolding
/// behavior), same rationale as Android's HoldingTile.
struct InvestmentsView: View {
    @Binding var isDrawerOpen: Bool
    @State private var viewModel = InvestmentsViewModel()
    @State private var drilledKey: String?
    @State private var showingAddSheet = false

    private var drilledGroup: InvestmentsViewModel.GroupUiModel? {
        guard let drilledKey else { return nil }
        return viewModel.groups.first { $0.key == drilledKey }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.invAccounts.isEmpty {
                    emptyAccountState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let drilledGroup {
                                ForEach(drilledGroup.holdings) { holding in
                                    HoldingRowView(
                                        holding: holding,
                                        onUpdate: { qty, avgCost, curVal, rate in
                                            Task { _ = await viewModel.updateHolding(id: holding.id, quantityText: qty, avgCostMajorText: avgCost, currentValueMajorText: curVal, annualRateText: rate, currency: holding.currency) }
                                        },
                                        onDelete: { viewModel.deleteHolding(holding.id) }
                                    )
                                }
                                Button("+ Add to \(drilledGroup.label)") { showingAddSheet = true }
                                    .foregroundColor(Color.accent)
                                    .fontWeight(.semibold)
                            } else {
                                PortfolioTotalCard(valueFormatted: viewModel.totalValueFormatted, gainFormatted: viewModel.totalGainFormatted, gainPositive: viewModel.totalGainPositive)
                                if viewModel.groups.isEmpty {
                                    Text("No holdings yet — tap + to add your first investment.")
                                        .font(.subheadline)
                                        .foregroundColor(Color.text2)
                                        .padding(.vertical, 24)
                                } else {
                                    ForEach(viewModel.groups) { group in
                                        GroupTileView(group: group) { drilledKey = group.key }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(drilledGroup?.label ?? "Investments")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if drilledGroup != nil {
                            drilledKey = nil
                        } else {
                            withAnimation(.spring()) { isDrawerOpen.toggle() }
                        }
                    } label: {
                        Image(systemName: drilledGroup != nil ? "chevron.left" : "line.3.horizontal")
                            .imageScale(.large)
                    }
                }
                if !viewModel.invAccounts.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingAddSheet = true }) {
                            Image(systemName: "plus").font(.headline).foregroundColor(Color.accent)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddHoldingView(initialGroupKey: drilledGroup?.key, viewModel: viewModel)
        }
    }

    private var emptyAccountState: some View {
        VStack(spacing: 10) {
            Text("▤").font(.system(size: 26))
            Text("No investment account yet").font(.title3).fontWeight(.bold).foregroundColor(Color.text)
            Text("Add a demat, stocks, or mutual-funds account to start tracking investments.")
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg.ignoresSafeArea())
    }
}

private struct PortfolioTotalCard: View {
    let valueFormatted: String
    let gainFormatted: String
    let gainPositive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Total portfolio value").font(.caption).fontWeight(.medium).foregroundColor(Color.text2)
            Text(valueFormatted).font(.system(size: 30, weight: .bold)).foregroundColor(Color.text)
            Text(gainFormatted).font(.caption).fontWeight(.semibold).foregroundColor(gainPositive ? Color.positive : Color.negative)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.surface)
        .cornerRadius(18)
    }
}

private struct GroupTileView: View {
    let group: InvestmentsViewModel.GroupUiModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.label).font(.subheadline).fontWeight(.bold).foregroundColor(Color.text)
                        Text("\(group.holdingsCount) holding\(group.holdingsCount == 1 ? "" : "s")").font(.caption).foregroundColor(Color.text2)
                    }
                    Spacer()
                    Text(group.gainPctFormatted).font(.caption).fontWeight(.semibold).foregroundColor(group.gainPositive ? Color.positive : Color.negative)
                }
                HStack {
                    Text(group.valueFormatted).font(.body).fontWeight(.bold).foregroundColor(Color.text)
                    Spacer()
                    Text(group.gainFormatted).font(.caption).fontWeight(.semibold).foregroundColor(group.gainPositive ? Color.positive : Color.negative)
                }
            }
            .padding(18)
            .background(Color.surface)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

/// "Zerodha-style" holding row, matching web's HoldingTile + Android's
/// HoldingTile: left side is label + off-list "untracked" chip + qty;
/// right side is value + gain; bottom row is asset-class meta + FD
/// extras. Tapping the edit icon expands an inline edit form in place.
private struct HoldingRowView: View {
    let holding: InvestmentsViewModel.HoldingUiModel
    let onUpdate: (String, String, String, String) -> Void
    let onDelete: () -> Void

    @State private var editing = false
    @State private var showDeleteConfirm = false
    @State private var quantityText = ""
    @State private var avgCostText = ""
    @State private var currentValueText = ""
    @State private var annualRateText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(holding.label).font(.body).fontWeight(.bold).foregroundColor(Color.text)
                        if holding.offList {
                            Text("untracked").font(.caption2).foregroundColor(Color.text2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.text2.opacity(0.15)).cornerRadius(8)
                        }
                    }
                    if !holding.quantityLine.isEmpty {
                        Text(holding.quantityLine).font(.caption).foregroundColor(Color.text2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(holding.valueFormatted).font(.body).fontWeight(.bold).foregroundColor(Color.text)
                    Text(holding.gainFormatted).font(.caption).fontWeight(.semibold).foregroundColor(holding.gainPositive ? Color.positive : Color.negative)
                }
            }
            HStack {
                Text(holding.fdExtra.map { "\(holding.metaLine) · \($0)" } ?? holding.metaLine)
                    .font(.caption2).foregroundColor(Color.text2)
                Spacer()
                Button {
                    if !editing {
                        quantityText = holding.rawQuantity == holding.rawQuantity.rounded() ? String(Int64(holding.rawQuantity)) : String(holding.rawQuantity)
                        avgCostText = holding.rawAvgCostMajor
                        currentValueText = holding.rawCurrentValueMajor
                        annualRateText = holding.rawAnnualRate
                    }
                    editing.toggle()
                } label: {
                    Image(systemName: "pencil").font(.caption).foregroundColor(Color.text2)
                }
                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash").font(.caption).foregroundColor(Color.negative)
                }
            }
            if editing {
                VStack(spacing: 8) {
                    TextField("Quantity", text: $quantityText).textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                    TextField("Avg cost (\(holding.currency))", text: $avgCostText).textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                    if !holding.isListedClass {
                        TextField("Current value (\(holding.currency))", text: $currentValueText).textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                    }
                    if holding.fdExtra != nil || !annualRateText.isEmpty {
                        TextField("Annual rate (%)", text: $annualRateText).textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                    }
                    HStack {
                        Button("Cancel") { editing = false }
                        Spacer()
                        Button("Save") {
                            onUpdate(quantityText, avgCostText, currentValueText, annualRateText)
                            editing = false
                        }.fontWeight(.semibold)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(14)
        .alert("Remove \(holding.label)?", isPresented: $showDeleteConfirm) {
            Button("Remove", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the holding. It doesn't reverse any transfer used to fund it.")
        }
    }
}

#Preview {
    InvestmentsView(isDrawerOpen: .constant(false))
}
