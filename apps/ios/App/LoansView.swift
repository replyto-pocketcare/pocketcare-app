import SwiftUI

/// Ported from apps/web/app/loans/page.tsx + [id]/page.tsx per
/// docs/mobile/screen-specs/loans.md (task #27/#42). Replaces the previous
/// broken placeholder (flat ungrouped list, non-optional access on now-
/// nullable Loan fields, a non-functional "Mark EMI Paid" alert with a
/// literal `// TODO: Handle confirm`, and a `"Loans & Recurring"` title
/// that appears to be invented drift merging with a separate, unbuilt
/// "Recurring" nav item -- same class of bug as the earlier-fixed Goals/
/// Cashflow merge). Detail is local `@State` (which loan id is selected),
/// not a pushed NavigationStack destination, matching this app's own
/// established Investments drill-in / Goals sheet conventions rather than
/// introducing a new navigation pattern.
struct LoansView: View {
    @Binding var isDrawerOpen: Bool
    @State private var viewModel = LoansViewModel()
    @State private var selectedLoanId: String?
    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let selectedLoanId {
                    LoanDetailContentView(loanId: selectedLoanId, onBack: { self.selectedLoanId = nil }, onDeleted: { self.selectedLoanId = nil })
                } else if viewModel.loans.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            totalCard
                            ForEach(viewModel.loans) { loan in
                                LoanRowCardView(loan: loan) { selectedLoanId = loan.id }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(selectedLoanId != nil ? "" : "Loans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if selectedLoanId != nil {
                            selectedLoanId = nil
                        } else {
                            withAnimation(.spring()) { isDrawerOpen.toggle() }
                        }
                    } label: {
                        Image(systemName: selectedLoanId != nil ? "chevron.left" : "line.3.horizontal")
                            .imageScale(.large)
                    }
                }
                if selectedLoanId == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingAddSheet = true }) {
                            Image(systemName: "plus").font(.headline).foregroundColor(Color.accent)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddLoanView(viewModel: viewModel)
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
    }

    private var totalCard: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total EMIs / month").font(.caption).foregroundColor(Color.text2)
                Text(viewModel.totalEmiFormatted).font(.title).fontWeight(.bold).foregroundColor(Color.text)
            }
            Spacer()
            Text("\(viewModel.loans.count) loan\(viewModel.loans.count == 1 ? "" : "s")")
                .font(.caption).foregroundColor(Color.text2)
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("≈").font(.system(size: 26))
            Text("No loans yet").font(.title3).fontWeight(.bold).foregroundColor(Color.text)
            Text("Track EMIs, interest, and payoff progress for any loan.")
                .font(.subheadline).foregroundColor(Color.text2).multilineTextAlignment(.center)
            Button(action: { showingAddSheet = true }) {
                Label("Add first loan", systemImage: "plus")
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoanRowCardView: View {
    let loan: LoansViewModel.LoanUiModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    Text(loan.lender).font(.subheadline).fontWeight(.bold).foregroundColor(Color.text)
                    Spacer()
                    Text(loan.active ? "Active" : "Closed")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(loan.active ? Color.positive : Color.text2)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background((loan.active ? Color.positive : Color.text2).opacity(0.15))
                        .clipShape(Capsule())
                }
                HStack {
                    Text(loan.rangeOrRate).font(.caption).foregroundColor(Color.text2)
                    Spacer()
                    Text(loan.paidCountText).font(.caption).fontWeight(.semibold).foregroundColor(Color.text)
                }
                if loan.hasTenure {
                    ProgressView(value: loan.progress)
                        .tint(loan.active ? Color.accent : Color.positive)
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Loan amount").font(.caption2).foregroundColor(Color.text2)
                        Text(loan.principalFormatted).font(.subheadline).fontWeight(.semibold).foregroundColor(Color.text)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("EMI amount").font(.caption2).foregroundColor(Color.text2)
                        Text(loan.emiFormatted).font(.subheadline).fontWeight(.semibold).foregroundColor(Color.text)
                    }
                }
            }
            .padding(16)
            .background(Color.surface)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

/// Loan detail content -- summary cards, next-due/remaining strip,
/// auto-mark toggle, EMI schedule, mark-paid sheet, inline edit/delete.
/// Ported from apps/web/app/loans/[id]/page.tsx.
struct LoanDetailContentView: View {
    let loanId: String
    let onBack: () -> Void
    let onDeleted: () -> Void

    @State private var viewModel = LoanDetailViewModel()
    @State private var editing = false
    @State private var showDeleteConfirm = false
    @State private var payForMonth: Int?

    var body: some View {
        Group {
            if let model = viewModel.uiModel {
                if editing {
                    EditLoanView(model: model, viewModel: viewModel, onSaved: { editing = false })
                } else {
                    detail(model)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { viewModel.load(id: loanId) }
        .onDisappear { viewModel.cancel() }
        .alert("Delete \(viewModel.uiModel?.lender ?? "loan")?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { viewModel.delete(onDone: onDeleted) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the loan and its EMI history.")
        }
        .sheet(item: Binding(get: { payForMonth.map { IdentifiableInt(value: $0) } }, set: { payForMonth = $0?.value })) { wrapped in
            if let model = viewModel.uiModel, let row = model.rows.first(where: { $0.month == wrapped.value }) {
                MarkPaidSheetView(
                    month: wrapped.value, dueLabel: row.dueFormatted, emiAmountMinor: row.emiMinor,
                    emiAmountFormatted: row.emiMinor > 0 ? row.amountFormatted : nil, currency: model.currency,
                    accounts: viewModel.markPaidAccounts, defaultAccountId: viewModel.defaultFundingAccountId,
                    onConfirm: { paidOn, accountId in
                        viewModel.markPaid(month: wrapped.value, paidOn: paidOn, accountId: accountId, emiAmountMinor: row.emiMinor, currency: model.currency)
                        payForMonth = nil
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func detail(_ model: LoanDetailUiModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text(model.lender).font(.title2).fontWeight(.bold).foregroundColor(Color.text)
                    Spacer()
                    Button("Edit") { editing = true }.foregroundColor(Color.accent)
                    Button("Delete") { showDeleteConfirm = true }.foregroundColor(Color.negative)
                }

                HStack(spacing: 10) {
                    SummaryCardView(label: "Principal", value: model.principalFormatted)
                    SummaryCardView(label: "Monthly EMI", value: model.emiFormatted)
                }
                HStack(spacing: 10) {
                    SummaryCardView(label: "Interest rate", value: model.interestRateText)
                    SummaryCardView(label: "EMIs paid", value: model.emisPaidText)
                }

                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next EMI due").font(.caption).foregroundColor(Color.text2)
                            Text(model.nextEmiDueFormatted).font(.headline).foregroundColor(Color.text)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Remaining").font(.caption).foregroundColor(Color.text2)
                            Text(model.remainingText).font(.headline).foregroundColor(Color.text)
                        }
                    }
                    if model.isVariable, let v = model.variablePaidFormatted {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Paid so far").font(.caption).foregroundColor(Color.text2)
                                Text(v).font(.headline).foregroundColor(Color.text)
                            }
                            Spacer()
                        }
                    } else if let ti = model.totalInterestFormatted {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total interest (schedule)").font(.caption).foregroundColor(Color.text2)
                                Text(ti).font(.headline).foregroundColor(Color.negative)
                            }
                            Spacer()
                        }
                    }
                    if model.hasTenure {
                        ProgressView(value: model.progress).tint(Color.accent)
                    }
                }
                .padding(16)
                .background(Color.surface)
                .cornerRadius(16)

                if !model.rows.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-mark past-due EMIs paid").font(.subheadline).fontWeight(.semibold).foregroundColor(Color.text)
                            Text((model.autoMarkPaid ? "On" : "Off") + (model.autoMarkDueDayText.isEmpty ? "" : " · \(model.autoMarkDueDayText)"))
                                .font(.caption).foregroundColor(Color.text2)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { model.autoMarkPaid }, set: { _ in viewModel.toggleAutoMark() }))
                            .labelsHidden()
                    }
                    .padding(14)
                    .background(Color.surface)
                    .cornerRadius(12)
                }

                Text(model.isVariable ? "Month-by-month EMIs" : "Amortization schedule")
                    .font(.caption).fontWeight(.semibold).foregroundColor(Color.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.rows.isEmpty {
                    Text(model.emptyScheduleHint ? "Add an interest rate, tenure, or EMI to see a payoff schedule." : "No EMIs yet.")
                        .font(.subheadline).foregroundColor(Color.text2)
                } else {
                    ForEach(model.rows) { row in
                        EmiRowCardView(
                            row: row, isVariable: model.isVariable,
                            onMark: { payForMonth = row.month },
                            onUnmark: { viewModel.unmarkPaid(month: row.month) },
                            onSaveVariableAmount: { major in viewModel.setVariableAmount(month: row.month, majorText: major, currency: model.currency) }
                        )
                    }
                }
            }
            .padding(16)
        }
    }
}

private struct IdentifiableInt: Identifiable { let value: Int; var id: Int { value } }

private struct SummaryCardView: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundColor(Color.text2)
            Text(value).font(.headline).fontWeight(.bold).foregroundColor(Color.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.surface)
        .cornerRadius(12)
    }
}

private struct EmiRowCardView: View {
    let row: EmiRowUiModel
    let isVariable: Bool
    let onMark: () -> Void
    let onUnmark: () -> Void
    let onSaveVariableAmount: (String) -> Void

    @State private var amountText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                dot
                VStack(alignment: .leading, spacing: 2) {
                    Text("EMI #\(row.month)").font(.caption2).foregroundColor(Color.text2)
                    Text(row.amountFormatted).font(.subheadline).fontWeight(.bold).foregroundColor(Color.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    switch row.state {
                    case .autoMarked:
                        chip("Auto-marked", Color.positive, nil)
                    case .paid:
                        chip("Paid", Color.positive, onUnmark)
                    case .due:
                        chip("Mark paid", Color.orange, onMark)
                    }
                    Text(row.state != .due ? "on \(row.paidOnOrDueFormatted)" : "due \(row.dueFormatted)")
                        .font(.caption2).foregroundColor(Color.text2)
                }
            }
            .padding(14)

            Divider()

            if isVariable {
                HStack {
                    Text("EMI this month").font(.caption2).foregroundColor(Color.text2)
                    Spacer()
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Button("Save") { onSaveVariableAmount(amountText) }.font(.caption)
                }
                .padding(14)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Principal").font(.caption2).foregroundColor(Color.text2)
                        Text(row.principalFormatted ?? "—").font(.subheadline).fontWeight(.semibold).foregroundColor(Color.text)
                    }
                    Spacer()
                    if row.hasInterest {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Interest").font(.caption2).foregroundColor(Color.text2)
                            Text(row.interestFormatted ?? "—").font(.subheadline).fontWeight(.semibold).foregroundColor(Color.negative)
                        }
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Balance").font(.caption2).foregroundColor(Color.text2)
                            Text(row.balanceFormatted ?? "—").font(.subheadline).fontWeight(.semibold).foregroundColor(Color.text)
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(Color.surface)
        .cornerRadius(12)
        .onAppear { amountText = row.rawAmountMajor }
    }

    private var dot: some View {
        let (bg, ch): (Color, String) = (row.state == .due) ? (Color.orange, "!") : (Color.positive, "✓")
        return ZStack {
            Circle().fill(bg).frame(width: 24, height: 24)
            Text(ch).font(.caption).fontWeight(.bold).foregroundColor(.white)
        }
    }

    private func chip(_ text: String, _ tint: Color, _ action: (() -> Void)?) -> some View {
        Group {
            if let action {
                Button(action: action) { chipLabel(text, tint) }.buttonStyle(.plain)
            } else {
                chipLabel(text, tint)
            }
        }
    }

    private func chipLabel(_ text: String, _ tint: Color) -> some View {
        Text(text).font(.caption2).fontWeight(.semibold).foregroundColor(tint)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(tint.opacity(0.15))
            .clipShape(Capsule())
    }
}

/// Mark-EMI-paid sheet -- date picker, optional funding account, matching
/// web's MarkPaidDialog.
struct MarkPaidSheetView: View {
    let month: Int
    let dueLabel: String
    let emiAmountMinor: Int64
    let emiAmountFormatted: String?
    let currency: String
    let accounts: [MarkPaidAccountOption]
    let defaultAccountId: String?
    let onConfirm: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var paidOn = Date()
    @State private var accountId: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !dueLabel.isEmpty || emiAmountFormatted != nil {
                        Text([dueLabel.isEmpty ? nil : "Due \(dueLabel)", emiAmountFormatted].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundColor(Color.text2)
                    }
                    DatePicker("Paid on", selection: $paidOn, displayedComponents: .date)
                }
                Section(header: Text("Also record as an expense")) {
                    Picker("Account", selection: $accountId) {
                        Text("Don't record").tag("")
                        ForEach(accounts) { a in
                            Text("\(a.name) · \(a.balanceFormatted)").tag(a.id)
                        }
                    }
                }
                Section {
                    Button(accountId.isEmpty ? "Mark paid" : "Mark paid & record") {
                        let fmt = DateFormatter()
                        fmt.dateFormat = "yyyy-MM-dd"
                        onConfirm(fmt.string(from: paidOn), accountId.isEmpty ? nil : accountId)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .navigationTitle("Mark EMI #\(month) paid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(Color.text2)
                }
            }
            .onAppear { accountId = defaultAccountId ?? "" }
        }
    }
}

#Preview {
    LoansView(isDrawerOpen: .constant(false))
}
