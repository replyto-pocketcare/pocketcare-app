import SwiftUI
import Domain

/// Scoped-down port of apps/web/src/investments/AddDialog.tsx's
/// AddInvestmentDialog per docs/mobile/screen-specs/investments.md's
/// Deferred section (task #26, new file 2026-08-06), mirroring Android's
/// AddHoldingScreen.kt. Deferred vs. web: the live instrument catalog
/// picker (every holding here is entered free-text/manually, i.e. always
/// off_list=true) and SIP recurring-transfer setup. Kept, and REAL (not
/// cosmetic): the existing-vs-new funding choice and its actual
/// transfer/adjustment transaction write (InvestmentsRepository.addHolding),
/// matching web's write.ts exactly.
struct AddHoldingView: View {
    let initialGroupKey: String?
    let viewModel: InvestmentsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var assetClass: AssetClass = .stock
    @State private var accountId: String = ""
    @State private var name = ""
    @State private var exchange = ""
    @State private var quantityText = ""
    @State private var costText = ""
    @State private var currentValueText = ""
    @State private var rateText = ""
    @State private var maturityText = ""
    @State private var fundingExisting = true
    @State private var sourceAccountId: String = ""
    @State private var saving = false
    @State private var errorText: String?

    private var isLump: Bool { assetClass == .fd }
    private var currency: String { viewModel.invAccounts.first(where: { $0.id == accountId })?.currency ?? baseCurrencyNow() }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Type")) {
                    Picker("Type", selection: $assetClass) {
                        ForEach(AssetClass.allCases, id: \.self) { c in
                            Text("\(c.icon) \(c.label)").tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if viewModel.invAccounts.count > 1 {
                    Section(header: Text("Investment account")) {
                        Picker("Account", selection: $accountId) {
                            ForEach(viewModel.invAccounts) { a in
                                Text(a.name).tag(a.id)
                            }
                        }
                    }
                }

                Section {
                    TextField(assetClass == .stock || assetClass == .mf ? "Symbol / name" : "Name", text: $name)
                    if assetClass == .stock {
                        TextField("Exchange (NSE / BSE)", text: $exchange)
                            .textInputAutocapitalization(.characters)
                    }
                }

                Section(header: Text(isLump ? "Amount" : "Quantity & cost")) {
                    if isLump {
                        TextField("Amount invested (\(currency))", text: $costText).keyboardType(.decimalPad)
                    } else {
                        TextField(quantityLabel, text: $quantityText).keyboardType(.decimalPad)
                        TextField(costLabel, text: $costText).keyboardType(.decimalPad)
                    }
                }

                if assetClass == .fd {
                    Section(header: Text("Fixed deposit details")) {
                        TextField("Interest % p.a.", text: $rateText).keyboardType(.decimalPad)
                        TextField("Maturity (YYYY-MM-DD)", text: $maturityText)
                    }
                }

                if assetClass != .stock && assetClass != .mf && assetClass != .sip {
                    Section {
                        TextField("Current value (\(currency), optional)", text: $currentValueText).keyboardType(.decimalPad)
                    }
                }

                Section(header: Text("Is this money already invested, or new?")) {
                    Picker("Funding", selection: $fundingExisting) {
                        Text("Already hold it").tag(true)
                        Text("Fund it now").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if !fundingExisting {
                        if viewModel.fundingAccounts.isEmpty {
                            Text("Add a funding account first.").foregroundColor(Color.negative)
                        } else {
                            Picker("Deduct from", selection: $sourceAccountId) {
                                ForEach(viewModel.fundingAccounts) { f in
                                    Text("\(f.name) · \(f.balanceFormatted)").tag(f.id)
                                }
                            }
                        }
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundColor(Color.negative) }
                }

                Section {
                    Button(action: save) {
                        if saving { ProgressView() }
                        else {
                            Text("Add investment").font(.headline).fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundColor(Color.surface)
                        }
                    }
                    .disabled(saving || accountId.isEmpty)
                    .listRowBackground(Color.accent)
                }
            }
            .navigationTitle("Add investment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(Color.text2)
                }
            }
        }
        .onAppear {
            applyDefaultAccounts()
            if let key = initialGroupKey {
                if key.hasPrefix("ex:") {
                    assetClass = .stock
                    let ex = String(key.dropFirst(3))
                    exchange = ex == "OTHER" ? "" : ex
                } else if key.hasPrefix("cls:") {
                    assetClass = AssetClass.fromKey(String(key.dropFirst(4)))
                }
            }
        }
        // invAccounts/fundingAccounts load asynchronously (see
        // InvestmentsViewModel.startObserving) and may still be empty at
        // .onAppear time -- re-apply defaults once they arrive so the
        // Picker/Add button aren't stuck on an empty accountId.
        .onChange(of: viewModel.invAccounts) { _, _ in applyDefaultAccounts() }
        .onChange(of: viewModel.fundingAccounts) { _, _ in applyDefaultAccounts() }
    }

    private var quantityLabel: String {
        let w = assetClass.unitWord
        return w.isEmpty ? "Quantity" : w.prefix(1).uppercased() + String(w.dropFirst())
    }

    private var costLabel: String {
        (assetClass == .mf || assetClass == .sip) ? "NAV / avg cost" : "Avg cost (\(currency))"
    }

    private func applyDefaultAccounts() {
        if accountId.isEmpty { accountId = viewModel.invAccounts.first?.id ?? "" }
        if sourceAccountId.isEmpty { sourceAccountId = viewModel.fundingAccounts.first?.id ?? "" }
    }

    private func save() {
        saving = true
        errorText = nil
        Task {
            let err = await viewModel.addHolding(
                investmentAccountId: accountId, assetClass: assetClass, name: name,
                exchange: exchange.isEmpty ? nil : exchange, quantityText: quantityText,
                avgCostMajorText: costText, currentValueMajorText: currentValueText, annualRateText: rateText,
                maturityDate: maturityText.isEmpty ? nil : maturityText, currency: currency,
                fundingExisting: fundingExisting, fundingSourceAccountId: fundingExisting ? nil : sourceAccountId
            )
            saving = false
            if let err { errorText = err } else { dismiss() }
        }
    }
}
