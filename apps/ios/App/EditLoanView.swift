import SwiftUI
import Domain

/// Real edit form, matching apps/web/app/loans/[id]/page.tsx's `EditLoan`
/// inline form field-for-field per docs/mobile/screen-specs/loans.md
/// (task #27/#42). Same field set as AddLoanView minus the funding-
/// account/auto-mark fields (those are only ever set via a mark-paid
/// confirm or the add form, matching web's `EditLoan` exactly). Prefilled
/// from LoanDetailUiModel's raw* fields, writes via the SAME
/// LoanDetailViewModel instance the detail screen is already using (not a
/// fresh LoansViewModel), so its live watchLoan() subscription picks the
/// edit up immediately.
struct EditLoanView: View {
    let model: LoanDetailUiModel
    let viewModel: LoanDetailViewModel
    let onSaved: () -> Void

    @State private var lender: String
    @State private var rateType: String
    @State private var principalText: String
    @State private var tenureText: String
    @State private var rateText: String
    @State private var emiText: String
    @State private var emiTouched: Bool
    @State private var startDate: Date
    @State private var dueDayText: String
    @State private var alertTime: String
    @State private var saving = false
    @State private var errorText: String?

    init(model: LoanDetailUiModel, viewModel: LoanDetailViewModel, onSaved: @escaping () -> Void) {
        self.model = model
        self.viewModel = viewModel
        self.onSaved = onSaved
        _lender = State(initialValue: model.rawLender)
        _rateType = State(initialValue: model.rawRateType)
        _principalText = State(initialValue: model.rawPrincipalMajor)
        _tenureText = State(initialValue: model.rawTenure)
        _rateText = State(initialValue: model.rawInterestRate)
        _emiText = State(initialValue: model.rawEmiMajor)
        _emiTouched = State(initialValue: !model.rawEmiMajor.isEmpty)
        _dueDayText = State(initialValue: model.rawDueDay)
        _alertTime = State(initialValue: model.rawAlertTimeLocal)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        _startDate = State(initialValue: model.rawStartDate.isEmpty ? Date() : (fmt.date(from: String(model.rawStartDate.prefix(10))) ?? Date()))
    }

    private var principalMinor: Int64 { fromMajor(Double(principalText) ?? 0, model.currency).amount }
    private var computedEmiMinor: Int64 {
        rateType == "fixed" ? emiFromPrincipal(principalMinor, Double(rateText) ?? 0, Int(tenureText) ?? 0) : 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(S.Loans.lender)) {
                    TextField("e.g. HDFC Bank", text: $lender)
                }

                Section(header: Text(S.Loans.interestType)) {
                    Picker("", selection: $rateType) {
                        Text(S.Loans.fixed).tag("fixed")
                        Text(S.Loans.variable).tag("variable")
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Loan details")) {
                    TextField("Principal (\(model.currency))", text: $principalText).keyboardType(.decimalPad)
                    TextField(S.Loans.tenureMonths, text: $tenureText).keyboardType(.numberPad)
                    TextField(rateType == "variable" ? "Current interest %" : S.Loans.interestPa, text: $rateText).keyboardType(.decimalPad)
                    if rateType == "fixed" {
                        TextField("Monthly EMI (\(model.currency))", text: emiFieldBinding).keyboardType(.decimalPad)
                        if computedEmiMinor > 0 {
                            HStack {
                                Text(emiTouched ? "Auto-calculated EMI would be \(formatMoney(computedEmiMinor, model.currency))" : "EMI auto-calculated from principal, rate & tenure.")
                                    .font(.caption).foregroundColor(Color.text2)
                                if emiTouched {
                                    Spacer()
                                    Button(S.Loans.useIt) { emiTouched = false; emiText = "" }.font(.caption)
                                }
                            }
                        }
                    } else {
                        Text("Variable-rate loans: enter each month's EMI from this loan's detail page as bills come in.")
                            .font(.caption).foregroundColor(Color.text2)
                    }
                }

                Section(header: Text("Schedule")) {
                    DatePicker("Started on", selection: $startDate, displayedComponents: .date)
                    TextField("Due day (1-31)", text: $dueDayText).keyboardType(.numberPad)
                    DatePicker("Alert time", selection: Binding(
                        get: { timeStringToDate(alertTime) },
                        set: { alertTime = dateToTimeString($0) }
                    ), displayedComponents: .hourAndMinute)
                }

                if let errorText {
                    Section { Text(errorText).foregroundColor(Color.negative) }
                }

                Section {
                    Button(action: save) {
                        if saving {
                            ProgressView()
                        } else {
                            Text(S.Translation.commonSaveChanges).font(.headline).fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundColor(Color.surface)
                        }
                    }
                    .disabled(saving || (lender.trimmingCharacters(in: .whitespaces).isEmpty && principalText.isEmpty))
                    .listRowBackground(Color.accent)
                }
            }
            .navigationTitle(S.Loans.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Loans.cancel, action: onSaved).foregroundColor(Color.text2)
                }
            }
        }
    }

    private var emiFieldBinding: Binding<String> {
        Binding(
            get: { emiTouched ? emiText : (emiText.isEmpty ? (computedEmiMinor > 0 ? formatMajorPlain(computedEmiMinor) : "") : emiText) },
            set: { emiText = $0; emiTouched = true }
        )
    }

    private func save() {
        saving = true
        errorText = nil
        Task {
            let isoFormatter = DateFormatter()
            isoFormatter.dateFormat = "yyyy-MM-dd"
            let err = await viewModel.update(
                lender: lender, principalMajorText: principalText,
                emiMajorText: rateType == "variable" ? "" : emiFieldBinding.wrappedValue,
                interestRateText: rateText, tenureText: tenureText, startDate: isoFormatter.string(from: startDate),
                dueDayText: dueDayText, rateType: rateType, alertTimeUtc: localToUtcTime(alertTime)
            )
            saving = false
            if let err {
                errorText = err
            } else {
                onSaved()
            }
        }
    }
}
