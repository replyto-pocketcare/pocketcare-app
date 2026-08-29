import SwiftUI
import Domain

/// Port of apps/web/src/investments/AddDialog.tsx's AddInvestmentDialog,
/// mirroring Android's AddHoldingScreen.kt.
///
/// Two things web has that this did not, both added this pass and both
/// load-bearing rather than cosmetic:
///
///  - **The SIP branch.** "SIP" was a selectable type that collected nothing:
///    no amount, no frequency, no debit day, no source account. The row it
///    wrote had `planned_id = nil` and no `sip_amount`, so a SIP could not be
///    created on a phone at all, and the Stop-SIP control added the week
///    before could only ever appear on a holding created on web.
///  - **The instrument picker.** Symbol and exchange were free text, so every
///    holding a phone created was written `off_list = 1` -- unpriceable,
///    unmatchable to a dividend row, and a different thing from the same
///    instrument added on web.
///
/// `initialGroupKey` prefills the asset class / exchange from a group tile's
/// "+ Add to {group}" button, matching web's addCtx context.
struct AddHoldingView: View {
    let initialGroupKey: String?
    @Bindable var viewModel: InvestmentsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var assetClass: AssetClass = .stock
    @State private var accountId: String = ""
    /// Web's `listed` toggle: a listed class can still be entered by hand, and
    /// then it is off_list like anything else.
    @State private var fromCatalog = true
    @State private var chosen: Instrument?
    @State private var name = ""
    @State private var quantityText = ""
    @State private var costText = ""
    @State private var currentValueText = ""
    @State private var rateText = ""
    /// A `DatePicker` cannot be empty, unlike web's `<input type="date">`, so
    /// an FD's maturity defaults a year out rather than to today -- "matures
    /// today" is a claim, and today is the one date it is certainly not.
    @State private var maturityDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var fundingExisting = true
    @State private var sourceAccountId: String = ""
    @State private var sipAmountText = ""
    @State private var sipFrequency = sipCycles[1]
    @State private var sipStartDate = Date()
    @State private var sipDayText = String(clampSipDay(Calendar.current.component(.day, from: Date())))
    @State private var sipSourceAccountId: String = ""
    @State private var saving = false
    @State private var errorText: String?

    private var isSip: Bool { assetClass == .sip }
    private var isLump: Bool { assetClass == .fd }
    private var usePicker: Bool { isListed(assetClass) && fromCatalog }
    private var account: InvestmentsViewModel.InvAccountOption? {
        viewModel.invAccounts.first(where: { $0.id == accountId })
    }
    /// Web: a catalog instrument trades in its OWN currency, which is not
    /// necessarily the demat account's -- an NSE holding in an account
    /// denominated in USD is still priced in INR.
    private var currency: String {
        (usePicker ? chosen?.currency : nil) ?? account?.currency ?? baseCurrencyNow()
    }

    private var nameOk: Bool {
        usePicker ? chosen != nil : !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(S.Accounts.typeLabel)) {
                    Picker(S.Accounts.typeLabel, selection: $assetClass) {
                        ForEach(AssetClass.allCases, id: \.self) { c in
                            Text("\(c.icon) \(assetClassDisplayLabel(c.rawValue))").tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if viewModel.invAccounts.count > 1 {
                    Section(header: Text(S.Investments.investmentAccount)) {
                        Picker(S.Investments.investmentAccount, selection: $accountId) {
                            ForEach(viewModel.invAccounts) { a in
                                Text(a.name).tag(a.id)
                            }
                        }
                    }
                }

                instrumentSection

                // A SIP is amount-based and collects its amount below, so it
                // never asks for units or a price here -- web does the same.
                if !isSip {
                    Section(header: Text(isLump ? S.Investments.amountInvested(cur: currency) : S.Investments.qty)) {
                        if isLump {
                            TextField(S.Investments.amountInvested(cur: currency), text: $costText).keyboardType(.decimalPad)
                        } else {
                            TextField(assetClass == .mf ? S.Investments.units : S.Investments.qty, text: $quantityText)
                                .keyboardType(.decimalPad)
                            TextField(
                                assetClass == .mf ? S.Investments.navAvgCost(cur: currency) : S.Investments.avgCost(cur: currency),
                                text: $costText
                            ).keyboardType(.decimalPad)
                        }
                    }
                }

                if isLump {
                    Section {
                        TextField(S.Investments.interestPa, text: $rateText).keyboardType(.decimalPad)
                        DatePicker(S.Investments.maturityDate, selection: $maturityDate, displayedComponents: .date)
                    }
                }

                if isSip { sipSection }

                if !isSip && !isListed(assetClass) {
                    Section {
                        TextField(S.Investments.currentValueOptional(cur: currency), text: $currentValueText)
                            .keyboardType(.decimalPad)
                    }
                }

                // Funding is not offered for a SIP: its money movement IS the
                // recurring transfer, so an existing-vs-new choice here would
                // post a second, imaginary one.
                if !isSip { fundingSection }

                if let errorText {
                    Section { Text(errorText).foregroundColor(Color.negative) }
                }

                Section {
                    Button(action: save) {
                        if saving { ProgressView() }
                        else {
                            Text(S.Investments.addInvestment).font(.headline).fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundColor(Color.surface)
                        }
                    }
                    // Web's `canAdd`, which folds in `nameOk = useCatalogPicker
                    // ? !!instrument : !!name.trim()`. Gating the BUTTON rather
                    // than erroring on submit is the point: with the picker open
                    // there is no name field on screen, so an "Enter a name"
                    // error would name a control the user cannot see.
                    .disabled(saving || accountId.isEmpty || !nameOk)
                    .listRowBackground(Color.accent)
                }
            }
            .navigationTitle(S.Investments.addInvestment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Investments.cancel) { dismiss() }.foregroundColor(Color.text2)
                }
            }
        }
        .onAppear {
            applyDefaultAccounts()
            // The picker's query and exchange live on the SHARED view model (a
            // sheet here, not a pushed route with its own instance), so they
            // survive a dismissal. Web opens a fresh dialog every time; reset
            // them so this one does too.
            viewModel.instrumentQuery = ""
            viewModel.instrumentExchange = nil
            if let key = initialGroupKey {
                if key.hasPrefix("ex:") {
                    assetClass = .stock
                    let ex = String(key.dropFirst(3))
                    // Scope the catalog to the exchange the drill-in came from,
                    // so "+ Add to NSE_IN" opens on NSE_IN rather than the
                    // whole world.
                    viewModel.instrumentExchange = ex == "OTHER" ? nil : ex
                } else if key.hasPrefix("cls:") {
                    assetClass = AssetClass.fromKey(String(key.dropFirst(4)))
                    if !isListed(assetClass) { fromCatalog = false }
                }
            }
        }
        // invAccounts/fundingAccounts load asynchronously (see
        // InvestmentsViewModel.startObserving) and may still be empty at
        // .onAppear time -- re-apply defaults once they arrive so the
        // Picker/Add button aren't stuck on an empty accountId.
        .onChange(of: viewModel.invAccounts) { _, _ in applyDefaultAccounts() }
        .onChange(of: viewModel.fundingAccounts) { _, _ in applyDefaultAccounts() }
        .onChange(of: fromCatalog) { _, newValue in
            if !newValue { chosen = nil }
        }
        .onChange(of: assetClass) { _, newValue in
            // Leaving a listed class clears the catalog pick: a crypto coin is
            // not an NSE ticker.
            if isListed(newValue) { fromCatalog = true } else { fromCatalog = false; chosen = nil }
        }
    }

    // MARK: - sections

    @ViewBuilder
    private var instrumentSection: some View {
        if isListed(assetClass) {
            Section {
                Picker(S.Investments.instrumentSource, selection: $fromCatalog) {
                    Text(S.Investments.inOurList).tag(true)
                    Text(S.Investments.notListed).tag(false)
                }
                .pickerStyle(.segmented)
            }
        }
        if usePicker {
            Section(header: Text(S.Investments.exchangeLabel)) {
                Picker(S.Investments.exchangeLabel, selection: exchangeBinding) {
                    Text(S.Investments.allExchanges).tag("")
                    ForEach(viewModel.catalogExchanges, id: \.self) { ex in
                        Text(ex).tag(ex)
                    }
                }
                TextField(S.Investments.instrumentSearch, text: $viewModel.instrumentQuery)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.instrumentQuery) { _, _ in chosen = nil }
                if let chosen {
                    InstrumentRow(instrument: chosen, selected: true) { self.chosen = nil }
                } else if viewModel.instrumentResults.isEmpty {
                    Text(viewModel.instrumentQuery.isEmpty ? S.Investments.startTypingInstrument : S.Investments.noInstrumentMatches)
                        .font(.caption).foregroundColor(Color.text2)
                } else {
                    // Eight, not all thirty: a Form section is not a scroll
                    // area of its own, and thirty rows would bury every field
                    // below it. Eight suggestions is what fits.
                    ForEach(viewModel.instrumentResults.prefix(8)) { i in
                        InstrumentRow(instrument: i, selected: false) { chosen = i }
                    }
                }
                Text(S.Investments.catalogSeedNote).font(.caption2).foregroundColor(Color.text3)
            }
        } else {
            Section {
                TextField(S.Investments.nameLabel(type: assetClassDisplayLabel(assetClass.rawValue)), text: $name)
            }
        }
    }

    /// The picker binds through "" rather than nil: SwiftUI's `Picker` cannot
    /// tag an optional selection without every tag being optional too, and
    /// "all exchanges" is the empty scope either way.
    private var exchangeBinding: Binding<String> {
        Binding(
            get: { viewModel.instrumentExchange ?? "" },
            set: { viewModel.instrumentExchange = $0.isEmpty ? nil : $0; chosen = nil }
        )
    }

    @ViewBuilder
    private var sipSection: some View {
        Section(header: Text(S.Investments.sipAmount(cur: currency))) {
            TextField(S.Investments.sipAmount(cur: currency), text: $sipAmountText).keyboardType(.decimalPad)
            Picker(S.Investments.sipFrequency, selection: $sipFrequency) {
                ForEach(sipCycles, id: \.self) { c in
                    Text(sipFrequencyLabel(c)).tag(c)
                }
            }
            .pickerStyle(.segmented)
            DatePicker(S.Investments.sipStartDate, selection: $sipStartDate, displayedComponents: .date)
            // Digits only, two of them: the column is documented 1-28 and the
            // value is clamped into that range on submit by `clampSipDay`, so
            // a typed 31 becomes 28 rather than a schedule that walks
            // backwards through February.
            TextField(S.Investments.sipDebitDayHint, text: $sipDayText)
                .keyboardType(.numberPad)
                .onChange(of: sipDayText) { _, newValue in
                    let digits = String(newValue.filter { $0.isNumber }.prefix(2))
                    if digits != newValue { sipDayText = digits }
                }
            if viewModel.fundingAccounts.isEmpty {
                Text(S.Investments.addBankFirst).foregroundColor(Color.negative)
            } else {
                Picker(S.Investments.debitsFrom, selection: $sipSourceAccountId) {
                    ForEach(viewModel.fundingAccounts) { f in
                        Text("\(f.name) · \(f.balanceFormatted)").tag(f.id)
                    }
                }
            }
            Text(S.Investments.sipNote(
                amount: sipAmountText.isEmpty ? S.Investments.theAmount : sipAmountText,
                account: account?.name ?? S.Investments.thisAccount
            ))
            .font(.caption2).foregroundColor(Color.text3)
        }
    }

    @ViewBuilder
    private var fundingSection: some View {
        Section(header: Text(S.Investments.newOrHold)) {
            Picker(S.Investments.newOrHold, selection: $fundingExisting) {
                Text(S.Investments.alreadyHold).tag(true)
                Text(S.Investments.newFund).tag(false)
            }
            .pickerStyle(.segmented)

            if !fundingExisting {
                if viewModel.fundingAccounts.isEmpty {
                    Text(S.Investments.noFundAccount).foregroundColor(Color.negative)
                } else {
                    Picker(S.Investments.deductFrom(amount: S.Investments.theAmount), selection: $sourceAccountId) {
                        ForEach(viewModel.fundingAccounts) { f in
                            Text("\(f.name) · \(f.balanceFormatted)").tag(f.id)
                        }
                    }
                }
            } else {
                Text(S.Investments.existingNote).font(.caption2).foregroundColor(Color.text3)
            }
        }
    }

    // MARK: - actions

    private func applyDefaultAccounts() {
        if accountId.isEmpty { accountId = viewModel.invAccounts.first?.id ?? "" }
        if sourceAccountId.isEmpty { sourceAccountId = viewModel.fundingAccounts.first?.id ?? "" }
        if sipSourceAccountId.isEmpty { sipSourceAccountId = viewModel.fundingAccounts.first?.id ?? "" }
    }

    private func save() {
        saving = true
        errorText = nil
        Task {
            let failure = await viewModel.addHolding(
                investmentAccountId: accountId, assetClass: assetClass,
                // Gated on `usePicker`, not just on `chosen`: toggling to "Not
                // listed" after picking must write an off_list holding, and a
                // stale selection would quietly make it catalogued.
                instrument: usePicker ? chosen : nil, name: name,
                exchange: viewModel.instrumentExchange, quantityText: quantityText,
                avgCostMajorText: costText, currentValueMajorText: currentValueText, annualRateText: rateText,
                maturityDate: isLump ? IsoDay.string(from: maturityDate) : nil, currency: currency,
                fundingExisting: fundingExisting, fundingSourceAccountId: fundingExisting ? nil : sourceAccountId,
                sipAmountMajorText: sipAmountText, sipFrequency: sipFrequency,
                sipStartDate: IsoDay.string(from: sipStartDate), sipDayText: sipDayText,
                sipSourceAccountId: sipSourceAccountId
            )
            saving = false
            if let failure { errorText = investmentFormMessage(failure) } else { dismiss() }
        }
    }
}

/// Web's SIP_CYCLES. Daily is deliberately absent: `sipFreq` has three
/// translations because web offers three cycles.
private let sipCycles = ["weekly", "monthly", "yearly"]

private func sipFrequencyLabel(_ key: String) -> String {
    switch key {
    case "weekly": return S.Investments.sipFreqWeekly
    case "yearly": return S.Investments.sipFreqYearly
    default: return S.Investments.sipFreqMonthly
    }
}

/// One catalog row: ticker and name on the left, exchange and trading
/// currency on the right -- web's InstrumentPicker option, verbatim.
private struct InstrumentRow: View {
    let instrument: Instrument
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(instrument.symbol).font(.subheadline).fontWeight(.semibold).foregroundColor(Color.text)
                    Text(instrument.name).font(.caption2).foregroundColor(Color.text2).lineLimit(1)
                }
                Spacer()
                Text("\(instrument.exchange) · \(instrument.currency)").font(.caption2).foregroundColor(Color.text2)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? Color.accentGhost : Color.surface)
    }
}
