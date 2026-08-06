import SwiftUI
import Domain

/// Real create form, matching apps/web/app/loans/page.tsx's `AddLoan`
/// inline modal field-for-field per docs/mobile/screen-specs/loans.md
/// (task #27/#42). New file -- iOS had no loan-creation screen at all
/// before this pass, mirroring Android's AddLoanScreen.kt.
struct AddLoanView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: LoansViewModel

    @State private var lender = ""
    @State private var rateType = "fixed"
    @State private var principalText = ""
    @State private var tenureText = ""
    @State private var rateText = ""
    @State private var emiText = ""
    @State private var emiTouched = false
    @State private var startDate = Date()
    @State private var dueDayText = ""
    @State private var alertTime = "09:00"
    @State private var autoMark = false
    @State private var fundingAccountId = ""
    @State private var saving = false
    @State private var errorText: String?

    private var principalMinor: Int64 { fromMajor(Double(principalText) ?? 0, "INR").amount }
    private var computedEmiMinor: Int64 {
        rateType == "fixed" ? emiFromPrincipal(principalMinor, Double(rateText) ?? 0, Int(tenureText) ?? 0) : 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Lender")) {
                    TextField("e.g. HDFC Bank", text: $lender)
                }

                Section(header: Text("Interest type")) {
                    Picker("", selection: $rateType) {
                        Text("Fixed").tag("fixed")
                        Text("Variable").tag("variable")
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Loan details")) {
                    TextField("Principal (INR)", text: $principalText).keyboardType(.decimalPad)
                    TextField("Tenure (months)", text: $tenureText).keyboardType(.numberPad)
                    TextField(rateType == "variable" ? "Current interest %" : "Interest % p.a.", text: $rateText).keyboardType(.decimalPad)
                    if rateType == "fixed" {
                        TextField("Monthly EMI (INR)", text: emiFieldBinding).keyboardType(.decimalPad)
                        if computedEmiMinor > 0 {
                            HStack {
                                Text(emiTouched ? "Auto-calculated EMI was \(formatMoney(computedEmiMinor, "INR"))" : "EMI auto-calculated from principal, rate & tenure.")
                                    .font(.caption).foregroundColor(Color.text2)
                                if emiTouched {
                                    Spacer()
                                    Button("Use it") { emiTouched = false; emiText = "" }.font(.caption)
                                }
                            }
                        }
                    } else {
                        Text("Variable-rate loans: enter each month's EMI from the loan's detail page as bills come in.")
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

                Section(header: Text("Where is this EMI charged?")) {
                    Picker("Funding account", selection: $fundingAccountId) {
                        Text("Not linked — I'll mark each EMI paid myself").tag("")
                        ForEach(viewModel.fundingAccounts) { a in
                            Text(a.isCreditCard ? "\(a.name) · credit card" : a.name).tag(a.id)
                        }
                    }
                    Text(isCreditCardSelected
                         ? "Each EMI will be added to this card when it falls due, and counted in the card's total due."
                         : "When an EMI falls due it'll be recorded against this account automatically.")
                        .font(.caption2).foregroundColor(Color.text2)
                }

                Section {
                    Toggle(isOn: $autoMark) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-mark EMIs paid once due")
                            Text("Past-due EMIs count as paid automatically — toggle off any time to revert.")
                                .font(.caption2).foregroundColor(Color.text2)
                        }
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundColor(Color.negative) }
                }

                Section {
                    Button(action: save) {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Add loan").font(.headline).fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundColor(Color.surface)
                        }
                    }
                    .disabled(saving || (lender.trimmingCharacters(in: .whitespaces).isEmpty && principalText.isEmpty))
                    .listRowBackground(Color.accent)
                }
            }
            .navigationTitle("Add loan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(Color.text2)
                }
            }
        }
    }

    private var isCreditCardSelected: Bool {
        viewModel.fundingAccounts.first { $0.id == fundingAccountId }?.isCreditCard ?? false
    }

    private var emiFieldBinding: Binding<String> {
        Binding(
            get: { emiTouched ? emiText : (computedEmiMinor > 0 ? formatMajorPlain(computedEmiMinor) : emiText) },
            set: { emiText = $0; emiTouched = true }
        )
    }

    private func save() {
        saving = true
        errorText = nil
        Task {
            let isoFormatter = DateFormatter()
            isoFormatter.dateFormat = "yyyy-MM-dd"
            let err = await viewModel.create(
                lender: lender, principalMajorText: principalText,
                emiMajorText: rateType == "variable" ? nil : (emiFieldBinding.wrappedValue.isEmpty ? nil : emiFieldBinding.wrappedValue),
                interestRateText: rateText, tenureText: tenureText, startDate: isoFormatter.string(from: startDate),
                dueDayText: dueDayText, autoMarkPaid: autoMark, rateType: rateType,
                fundingAccountId: fundingAccountId.isEmpty ? nil : fundingAccountId,
                alertTimeUtc: localToUtcTime(alertTime)
            )
            saving = false
            if let err {
                errorText = err
            } else {
                dismiss()
            }
        }
    }
}

#Preview {
    AddLoanView(viewModel: LoansViewModel())
}
