import SwiftUI
import Domain
import Data

/// Real port of apps/web/app/groups/[id]/page.tsx (task #30). See
/// docs/mobile/screen-specs/splits.md for the deliberate scope cut
/// (equal-split "Add expense" only; invite/itemized deferred). Embedded
/// content within SplitsView's own NavigationStack (its back button lives
/// in the parent's toolbar), matching LoanDetailContentView's convention.
struct GroupDetailView: View {
    let groupId: String
    let onBack: () -> Void

    @State private var viewModel = GroupDetailViewModel()
    @State private var showingAddExpense = false
    @State private var showingInvite = false
    @State private var settleTarget: MemberUiModel?
    @State private var showingEdit = false
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if !viewModel.loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(viewModel.group?.name ?? S.Groups.kindGroup).font(.title2).fontWeight(.bold).foregroundColor(.text)
                            Spacer()
                            SanvyaChip(S.Groups.invite, isActive: false) { showingInvite = true }
                            PrimaryButton(S.Splits.addExpense) { showingAddExpense = true }
                                .frame(width: 140)
                        }

                        // Web puts these behind a kebab. A chip row is the
                        // native equivalent and keeps the destructive one
                        // visibly separate from the two additive ones above.
                        HStack(spacing: 8) {
                            SanvyaChip(S.Groups.edit, isActive: false) { showingEdit = true }
                            SanvyaChip(S.Groups.delete, isActive: false) { confirmingDelete = true }
                            Spacer(minLength: 0)
                        }

                        if let summary = viewModel.summary {
                            GroupSummaryCard(summary: summary)
                        }

                        sectionHeader(S.Groups.membersTitle)
                        VStack(spacing: 4) {
                            ForEach(viewModel.members) { m in
                                Button(action: { if !m.isSelf { settleTarget = m } }) {
                                    memberRow(m)
                                }
                                .buttonStyle(.plain)
                                .disabled(m.isSelf)
                            }
                        }

                        if !viewModel.expenses.isEmpty {
                            sectionHeader(S.Groups.expensesTitle)
                            VStack(spacing: 4) {
                                ForEach(viewModel.expenses) { e in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(e.description).foregroundColor(.text).fontWeight(.medium)
                                            Text(e.date).font(.caption2).foregroundColor(.text2)
                                        }
                                        Spacer()
                                        Text(e.amountFormatted).fontWeight(.bold).foregroundColor(.text)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        if !viewModel.settlements.isEmpty {
                            sectionHeader("Settlements")
                            VStack(spacing: 4) {
                                ForEach(viewModel.settlements) { s in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(s.fromName) \u{2192} \(s.toName)").font(.subheadline).fontWeight(.medium).foregroundColor(.text)
                                            Text(s.date).font(.caption2).foregroundColor(.text2)
                                        }
                                        Spacer()
                                        Text(s.amountFormatted).fontWeight(.semibold).foregroundColor(.text2)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .task(id: groupId) { await viewModel.select(groupId) }
        .sanvyaModal(isPresented: $showingInvite, label: S.Groups.invite) {
            InviteSheet(
                groupName: viewModel.group?.name ?? "",
                viewModel: viewModel,
                onClose: { showingInvite = false }
            )
        }
        .sanvyaFormPresentation(isPresented: $showingAddExpense) {
            AddExpenseView(viewModel: viewModel, members: viewModel.members)
        }
        .sanvyaFormPresentation(item: $settleTarget) { target in
            SettleUpView(
                viewModel: viewModel,
                target: target,
                // The GROUP's currency. It is not on MemberUiModel because it
                // is not a property of the member — every balance in a group is
                // denominated in the group's own currency.
                currency: viewModel.group?.currency ?? baseCurrencyNow()
            )
        }
        .sanvyaFormPresentation(isPresented: $showingEdit) {
            if let g = viewModel.group {
                EditGroupSheet(group: g, viewModel: viewModel)
            }
        }
        .alert(S.Groups.deleteTitle, isPresented: $confirmingDelete) {
            Button(S.Translation.commonCancel, role: .cancel) {}
            Button(S.Groups.delete, role: .destructive) {
                Task {
                    // Leave the screen only if the delete actually landed.
                    // Popping first and failing after would show the user a
                    // group list that still contains the group they deleted.
                    if await viewModel.deleteGroup() == nil { onBack() }
                }
            }
        } message: {
            Text(S.Groups.deleteMsg(name: viewModel.group?.name ?? ""))
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2).fontWeight(.semibold).foregroundColor(.text2)
    }

    private func memberRow(_ m: MemberUiModel) -> some View {
        HStack {
            Text(m.name).foregroundColor(.text).fontWeight(.medium)
            Spacer()
            Text(memberBalanceText(m))
                .font(.subheadline)
                .foregroundColor(m.net == 0 ? .text2 : (m.net > 0 ? .positive : .negative))
        }
        .padding(.vertical, 6)
    }

    private func memberBalanceText(_ m: MemberUiModel) -> String {
        if m.net == 0 { return S.Groups.settledTitle }
        return m.net > 0 ? "Owes you \(formatMoney(m.net, baseCurrencyNow()))" : "You owe \(formatMoney(-m.net, baseCurrencyNow()))"
    }
}

private struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: GroupDetailViewModel
    let members: [MemberUiModel]

    @State private var description = ""
    @State private var amount = ""
    @State private var payerId: String
    @State private var accountId: String?
    @State private var participantIds: Set<String>
    @State private var error: String?
    @State private var saving = false

    init(viewModel: GroupDetailViewModel, members: [MemberUiModel]) {
        self.viewModel = viewModel
        self.members = members
        _payerId = State(initialValue: members.first(where: { $0.isSelf })?.userId ?? members.first?.userId ?? "")
        _participantIds = State(initialValue: Set(members.map(\.userId)))
        _accountId = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Split equally among the people you select below.").font(.caption).foregroundColor(.text2)
                    TextField(S.Receipts.reviewDescription, text: $description)
                    TextField(S.Translation.transactionAmount, text: $amount).keyboardType(.decimalPad)
                }
                Section(header: Text("Paid by")) {
                    Picker("Paid by", selection: $payerId) {
                        ForEach(members) { m in Text(m.name).tag(m.userId) }
                    }
                }
                if !viewModel.accounts.isEmpty {
                    Section(header: Text(S.Receipts.reviewAccount)) {
                        Picker(S.Translation.settingsAccount, selection: Binding(get: { accountId ?? viewModel.accounts.first?.id ?? "" }, set: { accountId = $0 })) {
                            ForEach(viewModel.accounts) { a in Text(a.name).tag(a.id) }
                        }
                    }
                }
                Section(header: Text(S.Transactions.splitBetween)) {
                    ForEach(members) { m in
                        Button(action: { toggle(m.userId) }) {
                            HStack {
                                Text(m.name).foregroundColor(.text)
                                Spacer()
                                if participantIds.contains(m.userId) { Image(systemName: "checkmark").foregroundColor(.accent) }
                            }
                        }
                    }
                }
                if let error { Text(error).foregroundColor(.negative).font(.caption) }
                Section {
                    Button(action: save) {
                        Text(saving ? S.Translation.commonSaving : S.Splits.addExpense).frame(maxWidth: .infinity)
                    }
                    .disabled(amount.isEmpty || payerId.isEmpty || participantIds.isEmpty || saving)
                    .listRowBackground(Color.accent)
                    .foregroundColor(.white)
                }
            }
            .navigationTitle(S.Splits.addExpense)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(S.Groups.cancel) { dismiss() }.foregroundColor(.text2) }
            }
        }
    }

    private func toggle(_ id: String) {
        if participantIds.contains(id) { participantIds.remove(id) } else { participantIds.insert(id) }
    }

    private func save() {
        saving = true
        Task {
            let err = await viewModel.addExpense(description: description, amountMajorText: amount, payerId: payerId, payerAccountId: accountId ?? viewModel.accounts.first?.id, participantIds: Array(participantIds))
            saving = false
            error = err
            if err == nil { dismiss() }
        }
    }
}

private struct SettleUpView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: GroupDetailViewModel
    let target: MemberUiModel
    let currency: String

    @State private var amount: String
    @State private var accountId: String?
    @State private var error: String?
    @State private var saving = false

    private var direction: String { target.net >= 0 ? "received" : "paid" }

    init(viewModel: GroupDetailViewModel, target: MemberUiModel, currency: String) {
        self.viewModel = viewModel
        self.target = target
        self.currency = currency
        // `toMajor`, not `/ 100.0` and `%.2f`. Those hardcoded the same
        // assumption twice over — the scale AND the decimal count — so a
        // zero-decimal currency prefilled a hundredth of the balance and then
        // printed two decimals that do not exist in it.
        _amount = State(initialValue: majorText(abs(target.net), currency))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Settle up with \(target.name)")) {
                    TextField(S.Translation.transactionAmount, text: $amount).keyboardType(.decimalPad)
                }
                if direction == "paid" {
                    Section {
                        Button(action: { viewModel.startUpiFetch(otherUserId: target.userId) }) {
                            if case .fetching = viewModel.upiStage {
                                HStack { ProgressView(); Text("Preparing the payment\u{2026}") }
                            } else {
                                Text(S.Payments.payButton)
                            }
                        }
                        .disabled({ if case .fetching = viewModel.upiStage { return true }; return false }())
                    }
                }
                if !viewModel.accounts.isEmpty {
                    Section(header: Text(S.Translation.settingsAccount)) {
                        Picker(S.Translation.settingsAccount, selection: Binding(get: { accountId ?? viewModel.accounts.first?.id ?? "" }, set: { accountId = $0 })) {
                            ForEach(viewModel.accounts) { a in Text(a.name).tag(a.id) }
                        }
                    }
                }
                if let error { Text(error).foregroundColor(.negative).font(.caption) }
                Section {
                    Button(action: settleManually) {
                        Text("Mark settled manually").frame(maxWidth: .infinity)
                    }
                    .disabled(amount.isEmpty || saving)
                }
            }
            .navigationTitle(S.Splits.settleUp)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(S.Groups.cancel) { viewModel.resetUpiStage(); dismiss() }.foregroundColor(.text2) }
            }
        }
        .sheet(isPresented: isUpiSheetPresented) {
            upiSheetContent
        }
        .alert("Couldn't fetch payment details", isPresented: isUpiErrorPresented, actions: {
            Button("OK") { viewModel.resetUpiStage() }
        }, message: {
            Text(upiErrorMessage)
        })
    }

    private var isUpiErrorPresented: Binding<Bool> {
        Binding(
            get: { if case .error = viewModel.upiStage { return true }; return false },
            set: { if !$0 { viewModel.resetUpiStage() } }
        )
    }

    private var upiErrorMessage: String {
        if case let .error(message, code) = viewModel.upiStage {
            return code == "no_handle" ? "\(target.name) hasn't added a UPI ID yet." : message
        }
        return ""
    }

    private var isUpiSheetPresented: Binding<Bool> {
        Binding(
            get: {
                if case .ready = viewModel.upiStage { return true }
                return false
            },
            set: { if !$0 { viewModel.resetUpiStage() } }
        )
    }

    @ViewBuilder
    private var upiSheetContent: some View {
        if case let .ready(vpa, displayName) = viewModel.upiStage {
            PayViaUpiSheet(
                counterpartyName: displayName ?? target.name,
                vpa: vpa,
                amountMinor: fromMajor(
                    Double(amount) ?? toMajor(money(abs(target.net), currency)),
                    currency
                ).amount,
                onPaid: { ref in
                    Task {
                        let err = await viewModel.recordUpiSettlement(otherUserId: target.userId, amountMajorText: amount, direction: direction, upiRef: ref)
                        viewModel.resetUpiStage()
                        if err == nil { dismiss() }
                    }
                }
            )
        }
    }

    private func settleManually() {
        saving = true
        Task {
            let err = await viewModel.settleManually(otherUserId: target.userId, amountMajorText: amount, direction: direction, accountId: accountId ?? viewModel.accounts.first?.id)
            saving = false
            error = err
            if err == nil { dismiss() }
        }
    }
}

/**
 A minor amount as editable MAJOR text, with the currency's own decimal count.

 `String(toMajor(...))` alone would print `1234.0` for a whole amount and
 `1234.5` for a half one; a money field wants the currency's digits. Zero-decimal
 currencies get no decimal point at all, which is what their users type.
 */
private func majorText(_ minor: Int64, _ currency: String) -> String {
    String(format: "%.\(minorUnits(currency))f", toMajor(money(minor, currency)))
}

/**
 Web's summary card: what the trip cost, and which way your side leans.

 Without it the screen listed rows and left the user to add them up — you could
 not tell what a trip cost in total, or whether you were up or down on it,
 without doing arithmetic by hand.

 The auto-split badge sits here rather than inside the edit sheet because it is
 a FACT about the group that changes what happens to transactions you have not
 made yet. A setting you cannot see is a surprise waiting to happen.
 */
private struct GroupSummaryCard: View {
    let summary: GroupSummaryUiModel

    var body: some View {
        SanvyaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(S.Groups.totalSpent).font(.subheadline).foregroundColor(.text2)
                        Text(summary.totalSpentFormatted).font(.title).fontWeight(.bold).foregroundColor(.text)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(S.Groups.youreOwed).font(.subheadline).foregroundColor(.text2)
                        Text(summary.owedFormatted).font(.title3).fontWeight(.bold).foregroundColor(.positive)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(S.Groups.youOwe).font(.subheadline).foregroundColor(.text2)
                        Text(summary.oweFormatted).font(.title3).fontWeight(.bold).foregroundColor(.negative)
                    }
                }
                HStack(spacing: 8) {
                    Text(dateRangeText).font(.subheadline).foregroundColor(.text2)
                    Text("\u{00B7} " + S.Groups.members(count: summary.memberCount))
                        .font(.subheadline).foregroundColor(.text2)
                    if summary.autoSplit {
                        Text("\u{00B7} " + S.Groups.autoSplitOn).font(.subheadline).foregroundColor(.accent)
                    }
                }
            }
        }
    }

    private var dateRangeText: String {
        guard let start = summary.startDate else { return S.Groups.noDates }
        guard let end = summary.endDate else { return start }
        return "\(start) \u{2013} \(end)"
    }
}

/**
 Rename, re-date, and the auto-split toggle — web's edit modal.

 The toggle is DISABLED without both dates, and the repository forces the flag
 off in that case regardless. A trip with no range has nothing to match a
 transaction's date against, so an auto-split flag on one is a setting that
 silently never fires — worse than an absent one, because the user believes it
 is working.
 */
private struct EditGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: SplitGroup
    let viewModel: GroupDetailViewModel

    @State private var name: String
    // Web's two `<input type="date">`s can be empty; a SwiftUI DatePicker
    // cannot. `hasDates` is that empty state, made explicit -- the alternative
    // is a sheet that can set a range but never clear one.
    @State private var hasDates: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var auto: Bool
    @State private var error: String?
    @State private var saving = false

    init(group: SplitGroup, viewModel: GroupDetailViewModel) {
        self.group = group
        self.viewModel = viewModel
        let s = group.startDate.flatMap(IsoDay.date(from:))
        let e = group.endDate.flatMap(IsoDay.date(from:))
        _name = State(initialValue: group.name)
        _hasDates = State(initialValue: s != nil && e != nil)
        _start = State(initialValue: s ?? Date())
        _end = State(initialValue: e ?? s ?? Date())
        _auto = State(initialValue: group.autoSplit)
    }

    private var startIso: String { hasDates ? IsoDay.string(from: start) : "" }
    private var endIso: String { hasDates ? IsoDay.string(from: end) : "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(S.Groups.namePlaceholder, text: $name)
                }
                Section(header: Text(S.Groups.datesOptional)) {
                    Toggle(S.Groups.datesOptional, isOn: $hasDates)
                    if hasDates {
                        DatePicker(S.Statements.fromDate, selection: $start, displayedComponents: .date)
                        // `in: start...` is web's `min={start}`: an inverted
                        // range matches no transaction at all.
                        DatePicker(S.Statements.toDate, selection: $end, in: start..., displayedComponents: .date)
                    }
                }
                Section {
                    Toggle(isOn: Binding(get: { auto && hasDates }, set: { auto = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(S.Groups.autoSplitLabel).foregroundColor(.text)
                            Text(S.Groups.autoSplitDesc(
                                start: hasDates ? startIso : "\u{2014}",
                                end: hasDates ? endIso : "\u{2014}",
                                kind: group.kind
                            ))
                            .font(.caption).foregroundColor(.text2)
                        }
                    }
                    .disabled(!hasDates)
                }
                if let error { Text(error).foregroundColor(.negative).font(.caption) }
                Section {
                    Button(action: save) {
                        Text(saving ? S.Translation.commonSaving : S.Translation.commonSave)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                    .listRowBackground(Color.accent)
                    .foregroundColor(.white)
                }
            }
            .navigationTitle(S.Groups.edit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Groups.cancel) { dismiss() }.foregroundColor(.text2)
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            let err = await viewModel.updateGroup(name: name, startDate: startIso, endDate: endIso, autoSplit: auto)
            saving = false
            error = err
            if err == nil { dismiss() }
        }
    }
}
