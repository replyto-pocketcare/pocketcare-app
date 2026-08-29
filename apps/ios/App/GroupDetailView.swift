import SwiftUI
import Domain
import Data

/// Real port of apps/web/app/groups/[id]/page.tsx (task #30). Embedded content
/// within SplitsView's own NavigationStack (its back button lives in the
/// parent's toolbar), matching LoanDetailContentView's convention.
///
/// Two of the original scope cuts are now closed:
///
/// **Add expense** no longer opens a local equal-split sheet. Web's button is a
/// link to the full transaction form with this group preselected, and so is
/// this: an unequal expense added from inside a group used to be impossible on
/// a phone while the percent/exact/itemised editor sat one sheet away.
///
/// **Itemised bills** can be opened in place. `expense_items` has existed since
/// 0040 with no UI on either phone, so "who had what" — the exact question
/// people ask when a split is argued about — had no answer outside the browser.
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
                                    ExpenseRow(expense: e, viewModel: viewModel)
                                }
                            }
                        }

                        // Settled up — the other half of the group's history.
                        // Its own section rather than mixed into Expenses: a
                        // settlement moves money between two members without
                        // adding to what the group spent, so interleaving them
                        // would imply it counts toward the total.
                        if !viewModel.settlements.isEmpty {
                            sectionHeader(S.Groups.settledTitle)
                            VStack(spacing: 4) {
                                ForEach(viewModel.settlements) { s in
                                    settlementRow(s)
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
            // Web's "Add expense" is a link to the full transaction form with
            // this group preselected, not a second, lesser editor.
            CreateTransactionView(preselectSplitGroupId: groupId)
        }
        .sanvyaFormPresentation(item: $settleTarget) { target in
            SettleUpView(
                viewModel: viewModel,
                target: target,
                targetName: target.name,
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

    /// The group's currency, not the base one: every balance in a group is
    /// denominated in the group's own currency, and formatting a EUR trip's
    /// balances with a rupee symbol is a lie about what is owed.
    private func memberBalanceText(_ m: MemberUiModel) -> String {
        if m.net == 0 { return S.Groups.settledTag }
        let currency = viewModel.group?.currency ?? baseCurrencyNow()
        let amount = formatMoney(abs(m.net), currency)
        return m.net > 0 ? S.Groups.owesYouAmt(amount: amount) : S.Groups.youOweAmt(amount: amount)
    }

    /**
     One past settlement, with its status.

     A PENDING settlement is a claim, not a fact: it came from a UPI hand-off
     that gives no delivery callback, and only the payee can close it. Rendering
     it identically to a confirmed one tells both people the debt is settled
     when the money may never have arrived — which is web's "Waiting to be
     confirmed".
     */
    private func settlementRow(_ s: SettlementUiModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(settlementLabel(s)).font(.subheadline).fontWeight(.medium).foregroundColor(.text)
                Text(s.date).font(.caption2).foregroundColor(.text2)
                if s.pending {
                    Text(S.Groups.settledPending).font(.caption2).foregroundColor(.warning)
                }
            }
            Spacer()
            Text(s.amountFormatted).fontWeight(.semibold).foregroundColor(.text2)
        }
        .padding(.vertical, 4)
    }

    private func settlementLabel(_ s: SettlementUiModel) -> String {
        if s.iPaid { return S.Groups.settledYouPaid(name: s.otherName) }
        if s.paidToMe { return S.Groups.settledPaidYou(name: s.otherName) }
        return S.Groups.settledBetween(from: s.fromName, to: s.toName)
    }
}

/**
 One expense, expandable in place when the bill was itemised.

 Web's own comment on the same row: the answer to "why do I owe this?" belongs
 next to the number, not on another screen. The chip only exists when
 `expenses.has_items` is set, so an ordinary expense keeps the plain row.
 */
private struct ExpenseRow: View {
    let expense: ExpenseUiModel
    let viewModel: GroupDetailViewModel

    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.description).foregroundColor(.text).fontWeight(.medium)
                    Text(expense.date).font(.caption2).foregroundColor(.text2)
                }
                Spacer()
                if expense.hasItems {
                    SanvyaChip(open ? S.Receipts.breakdownHide : S.Receipts.breakdownShow, isActive: open) {
                        open.toggle()
                        if open { viewModel.loadBreakdown(expenseId: expense.id) }
                    }
                }
                Text(expense.amountFormatted).fontWeight(.bold).foregroundColor(.text)
            }

            if expense.hasItems && open {
                if let breakdown = viewModel.breakdowns[expense.id] {
                    ItemBreakdownPanel(
                        breakdown: breakdown,
                        currency: expense.currency,
                        // A closure literal, not `viewModel.displayName`:
                        // an unapplied reference to a @MainActor method is a
                        // conversion the compiler has to justify, and the
                        // literal is what every other call site here uses.
                        nameOf: { viewModel.displayName($0) }
                    )
                } else {
                    ProgressView()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/**
 Who had what, and what that came to.

 Read-only, exactly as web is: editing a split after the fact means rewriting
 ledger postings, which is the edit-transaction flow's job.

 The person chips filter to one member's lines. The arithmetic behind both the
 filter and the footer total is Domain's `itemBreakdown` under its own golden
 vectors — the two platforms cannot drift on which lines are "yours".
 */
private struct ItemBreakdownPanel: View {
    let breakdown: ExpenseBreakdownUiModel
    let currency: String
    /// Resolved by the view model, which already holds the group's members —
    /// an item share can only belong to a member of the group the expense is
    /// in, so there is nothing else to look up.
    let nameOf: (String) -> String

    /// "" is web's own "everyone" value, not a placeholder — see itemBreakdown.
    @State private var filter = ""

    private var itemsById: [String: ExpenseItem] {
        Dictionary(breakdown.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var breakdownView: ItemBreakdownView {
        itemBreakdown(
            items: breakdown.items.map { ItemBreakdownItem(id: $0.id, amount: $0.amount) },
            shares: breakdown.shares.map { ItemBreakdownShare(itemId: $0.itemId, userId: $0.userId, shareAmount: $0.shareAmount) },
            filterUserId: filter
        )
    }

    var body: some View {
        let model = breakdownView
        let byId = itemsById
        VStack(alignment: .leading, spacing: 10) {
            // One person cannot be filtered against themselves — web hides the
            // row entirely below two people, and so does this.
            if model.everyone.count > 1 {
                ChipRow(
                    options: [""] + model.everyone,
                    selected: filter,
                    label: { id in id.isEmpty ? S.Receipts.breakdownEveryone : nameOf(id) },
                    onSelect: { filter = $0 }
                )
            }

            ForEach(model.lines, id: \.itemId) { line in
                lineRow(line, item: byId[line.itemId])
            }

            HStack {
                Text(filter.isEmpty ? S.Receipts.splitTotal : S.Receipts.breakdownPersonTotal(name: nameOf(filter)))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.text)
                Spacer(minLength: 8)
                Text(formatMoney(model.total, currency))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.text)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func lineRow(_ line: ItemBreakdownLine, item: ExpenseItem?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item?.description?.isEmpty == false ? item!.description! : kindLabel(item?.kind))
                        .font(.system(size: 13.5))
                        .foregroundColor(.text)
                    // Plain captions, not chips: these are labels, and a chip
                    // implies a control you can press. (Web's own note on the
                    // same two spans.)
                    if let item, item.kind != "item" {
                        Text(kindLabel(item.kind).uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.text2)
                    }
                    if let qty = quantityLabel(item) {
                        Text(qty).font(.system(size: 11.5)).foregroundColor(.text2)
                    }
                }
                if !line.shares.isEmpty {
                    Text(line.shares.map { "\(nameOf($0.userId)) \(formatMoney($0.amount, currency))" }.joined(separator: " \u{00B7} "))
                        .font(.system(size: 11.5))
                        .foregroundColor(.text2)
                }
            }
            Spacer(minLength: 8)
            Text(formatMoney(line.amount, currency))
                .font(.system(size: 13.5))
                .foregroundColor(.text)
        }
    }
}

/// `expense_items.kind` as a label. Unknown kinds read as a plain item, which
/// is what web's `t("kind.<kind>", kind)` degrades to.
private func kindLabel(_ kind: String?) -> String {
    switch kind {
    case "tax": return S.Receipts.kindTax
    case "service_charge": return S.Receipts.kindServiceCharge
    case "tip": return S.Receipts.kindTip
    case "discount": return S.Receipts.kindDiscount
    default: return S.Receipts.kindItem
    }
}

/**
 "2 kg" / "3×", or nothing at all when the line carries no quantity.

 The bare "×" when there is no unit is web's, and is a symbol rather than a word
 on purpose — it needs no translation, which is why it is not a key.
 */
private func quantityLabel(_ item: ExpenseItem?) -> String? {
    guard let milli = item?.quantity else { return nil }
    let unit = (item?.unit?.isEmpty == false) ? item!.unit! : nil
    return S.Receipts.splitQtyLabel(qty: trimmedQty(milli), unit: unit.map { " \($0)" } ?? "\u{00D7}")
}

/**
 Milli-units as the shortest exact decimal: 2000 → "2", 1500 → "1.5".
 Web prints the raw JS number, which drops trailing zeros the same way.

 A knowing duplicate of the same helper in `SplitReceiptView.swift`: it is
 private there, and lifting it into a shared component is a change to a file
 this one does not own.
 */
private func trimmedQty(_ milli: Int64) -> String {
    let major = qtyToMajor(milli)
    if major == major.rounded() { return String(Int64(major)) }
    var text = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), major)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
}

/**
 Settle up with one member — web's settle Modal on `/friends`.

 Two things this used to get wrong, both of which booked money that never moved:

 **There was no "None".** Every settlement picked an account, so settling a cash
 debt in person still posted a bank transfer. Web's account `<select>` opens on
 an empty option that means exactly "don't post anything", and the repository
 already honours a nil account by skipping the ledger leg.

 **UPI was offered unconditionally.** It is a rupee rail, so it is offered only
 when this settlement is in INR and there is an amount to send — web's
 `base === "INR" && Number(amount) > 0`. The currency compared here is the
 GROUP's, because that is what the settlement is recorded in.
 */
private struct SettleUpView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: GroupDetailViewModel
    let target: MemberUiModel
    let targetName: String
    let currency: String

    @State private var amount: String
    /// "" is a real option, not a placeholder — see the doc comment above.
    @State private var accountId = ""
    @State private var error: String?
    @State private var saving = false

    private var direction: String { target.net >= 0 ? "received" : "paid" }

    /// `fromMajor`, never `* 100`: the settlement carries its own currency and
    /// a zero-decimal one would be sent a hundred times over.
    private var amountMinor: Int64 {
        fromMajor(Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0, currency).amount
    }

    private var upiOffered: Bool { direction == "paid" && currency == "INR" && amountMinor > 0 }

    init(viewModel: GroupDetailViewModel, target: MemberUiModel, targetName: String, currency: String) {
        self.viewModel = viewModel
        self.target = target
        self.targetName = targetName
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
                Section {
                    Text(target.net >= 0 ? S.Splits.theyPayYouBack(name: targetName) : S.Splits.youPayThemBack(name: targetName))
                        .font(.caption).foregroundColor(.text2)
                    TextField(S.Splits.amountLabel(currency: currency), text: $amount).keyboardType(.decimalPad)
                }

                Section(header: Text(direction == "received" ? S.Splits.receivedInto : S.Splits.paidFrom)) {
                    ChipRow(
                        options: [""] + viewModel.accounts.map(\.id),
                        selected: accountId,
                        label: { id in
                            id.isEmpty
                                ? S.Splits.noneMarkSettled
                                : (viewModel.accounts.first { $0.id == id }?.name ?? "")
                        },
                        onSelect: { accountId = $0 }
                    )
                }

                if upiOffered {
                    // Web renders the UPI stages INLINE inside the settle modal
                    // rather than stacking an alert on a sheet — an alert over
                    // a sheet on a phone hides the amount the payment is for.
                    Section { upiSection }
                }

                if let error { Text(error).foregroundColor(.negative).font(.caption) }
                Section {
                    Button(action: settleManually) {
                        Text(saving ? S.Splits.settling : S.Splits.settle).frame(maxWidth: .infinity)
                    }
                    .disabled(amountMinor <= 0 || saving)
                    .listRowBackground(Color.accent)
                    .foregroundColor(.white)
                }
            }
            .navigationTitle(S.Splits.settleWith(name: targetName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(S.Groups.cancel) { viewModel.resetUpiStage(); dismiss() }.foregroundColor(.text2) }
            }
        }
        .sheet(isPresented: isUpiSheetPresented) {
            upiSheetContent
        }
    }

    @ViewBuilder
    private var upiSection: some View {
        switch viewModel.upiStage {
        case .idle, .ready:
            Button(S.Payments.payButton) { viewModel.startUpiFetch(otherUserId: target.userId) }
        case .fetching:
            HStack { ProgressView(); Text(S.Payments.payPreparing).font(.caption).foregroundColor(.text2) }
        case let .error(message, code):
            VStack(alignment: .leading, spacing: 8) {
                Text(code == "no_handle" ? S.Payments.payNoHandle(name: targetName) : message)
                    .font(.caption).foregroundColor(.negative)
                Button(S.Payments.payBack) { viewModel.resetUpiStage() }
            }
        }
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
                counterpartyName: displayName ?? targetName,
                vpa: vpa,
                amountMinor: amountMinor,
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
            let err = await viewModel.settleManually(
                otherUserId: target.userId,
                amountMajorText: amount,
                direction: direction,
                // nil is "None — just mark settled": the repository skips the
                // ledger leg entirely, which is the whole point of the option.
                accountId: accountId.isEmpty ? nil : accountId
            )
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
