import SwiftUI
import Factory
import Domain
import Data

private struct DraftItem: Identifiable {
    let id: String
    var description: String
    var value: String
}

/// New transaction — ported from transactions/new/page.tsx's regular
/// expense/income/transfer path per docs/mobile/screen-specs/transactions.md.
/// Rewritten 2026-08-05: the previous version was a native Form/Picker
/// mockup with hardcoded categories/accounts whose Save button called
/// dismiss() without ever calling the repository -- nothing it "created"
/// was persisted. Split-expense, templates, and AI auto-categorize are
/// explicitly deferred (see spec's Scope section).
struct CreateTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Injected(\.ledgerRepository) private var ledgerRepository
    @Injected(\.authRepository) private var authRepository
    @Injected(\.prefsRepository) private var prefsRepository
    @Injected(\.splitsRepository) private var splitsRepository

    @State private var accounts: [Account] = []
    @State private var categories: [CategoryRow] = []
    @State private var labelOptions: [LabelRow] = []
    @State private var paymentMethods: [PaymentMethodRow] = []

    @State private var type = "expense"
    @State private var accountId: String?
    @State private var toAccountId: String?
    @State private var categoryId: String?
    @State private var selectedLabels: [String] = []
    @State private var note = ""
    @State private var paymentMethod = ""
    @State private var items: [DraftItem] = [DraftItem(id: UUID().uuidString, description: "", value: "")]
    @State private var toValue = ""
    @State private var occurredAt = Date()
    @State private var saving = false
    @State private var error: String?

    // ---- auto-categorisation ----
    /// What the categoriser proposed for the current description, and whether it
    /// was applied without the user asking. Both are needed at save time:
    /// learning treats "you suggested Food and they chose Groceries" as a
    /// CORRECTION worth five ordinary sightings, and that is only true if the
    /// suggestion was actually on screen.
    @State private var suggestedCategoryId: String?
    @State private var autoApplied = false
    /// True once the user has touched the category picker themselves. A manual
    /// pick stops the suggester overwriting it, for good — web keeps the same
    /// latch and never clears it.
    @State private var manualCategory = false
    @State private var suggestTask: Task<Void, Never>?
    /// Whether the categoriser runs at all.
    ///
    /// Web gates BOTH halves on the entitlement — `useAutoCategorize(text, cats,
    /// isPaid && type !== "transfer")` and `if (... && isPaid) learnCategory(...)`.
    /// The first port of this screen missed it, so a free account was quietly
    /// getting a paid feature and, worse, writing category rules that would then
    /// shape suggestions it was never supposed to see.
    ///
    /// Starts CLOSED and stays closed if the entitlement can't be read: a gate
    /// that fails open is not a gate.
    @State private var isPaid = false
    @State private var entitlementTask: Task<Void, Never>?

    // ---- split ----
    /// Web keeps the split editor's state on the page, not in a store, and so
    /// does this: every field below feeds `splitPlan` in Domain, which decides
    /// the numbers, and `save()`, which writes them. Nothing here computes.
    @State private var groups: [SplitGroup] = []
    /// Every membership row, keyed by group id. One watch over a small table
    /// beats standing a subscription up and down as the picker changes.
    @State private var groupMembers: [String: [String]] = [:]
    @State private var connections: [UserProfile] = []
    @State private var me = ""
    @State private var splitOn = false
    /// Set the moment the user touches the toggle or the group picker. It is
    /// the whole guard on auto-split: without it a deliberate "no, not this
    /// trip" would be undone on the next state change.
    @State private var splitTouched = false
    @State private var splitGroupId = ""
    @State private var splitMode = SplitModes.equal
    @State private var splitMembers: [String] = []
    @State private var shareText: [String: String] = [:]
    @State private var multiPayer = false
    @State private var paidText: [String: String] = [:]
    @State private var forOtherOn = false
    @State private var forOtherUserId = ""

    private var account: Account? { accounts.first { $0.id == accountId } ?? accounts.first }
    private var toAccount: Account? { accounts.first { $0.id == toAccountId } ?? accounts.first { $0.id != account?.id } }
    private var isInvestment: Bool { account?.type == "stocks" || account?.type == "mutual_funds" }
    private var currency: String { account?.currency ?? baseCurrencyNow() }
    private var relevantCategories: [CategoryRow] { categories.filter { $0.kind == (type == "income" ? "income" : "expense") } }
    private var relevantPaymentMethods: [PaymentMethodRow] { paymentMethods.filter { $0.accountTypeId == account?.type } }

    /// The typed amount.
    ///
    /// Web is `items.map(it => fromMajor(parseFloat(it.value) || 0, currency))`
    /// summed — per item, not on the sum, so each item rounds the way web's
    /// does, and `fromMajor` rather than a hardcoded ×100 so a zero-decimal
    /// currency is not read as a hundredth of itself.
    /// Summed in MINOR UNITS, then wrapped once.
    ///
    /// Not `reduce` over `Money`: `money(0, currency)` is ambiguous between the
    /// `Int64` and `Double` overloads at an integer literal, and threading a
    /// `Money` through the accumulator only to unwrap `.amount` on every step
    /// adds nothing. The rounding that matters still happens per item, inside
    /// `fromMajor`, which is the whole point.
    private var totalMinor: Int64 {
        items.reduce(Int64(0)) { $0 + fromMajor(jsParseFloat($1.value) ?? 0, currency).amount }
    }
    private var totalMoney: Money { money(totalMinor, currency) }

    private var canSave: Bool {
        guard account != nil, totalMinor > 0, !saving else { return false }
        if type == "transfer" { return toAccount != nil && toAccount!.id != account!.id }
        return true
    }

    // ---- split, derived ----

    /// Members of a group in `created_at` order — the order web's chips use.
    private func membersOf(_ groupId: String) -> [String] { groupMembers[groupId] ?? [] }

    /// A member's display name. "You" for the current user, as web has it.
    private func memberName(_ userId: String) -> String {
        userId == me
            ? S.Receipts.splitYou
            : (connections.first { $0.id == userId }?.name ?? String(userId.prefix(8)))
    }

    private var splitIsActive: Bool {
        splitActive(type: type, splitOn: splitOn, groupId: splitGroupId, memberCount: splitMembers.count)
    }

    private var forOtherIsActive: Bool {
        forOtherActive(
            type: type, splitOn: splitOn, forOtherOn: forOtherOn,
            otherUserId: forOtherUserId, totalMinor: totalMinor
        )
    }

    /// The whole split, recomputed by Domain whenever anything it reads moves.
    private var plan: SplitPlan {
        splitPlan(
            groupId: splitGroupId, mode: splitMode, memberIds: splitMembers, me: me,
            totalMinor: totalMinor, currency: currency, shareText: shareText,
            multiPayer: multiPayer, paidText: paidText, hasAccount: account != nil
        )
    }

    private var splitEditor: some View {
        SplitEditorView(
            type: type, currency: currency, accountName: account?.name ?? "", me: me,
            groups: groups, connections: connections,
            plan: plan, totalMinor: totalMinor,
            membersOf: membersOf, memberName: memberName,
            splitOn: $splitOn, splitTouched: $splitTouched,
            splitGroupId: $splitGroupId, splitMode: $splitMode,
            splitMembers: $splitMembers, shareText: $shareText,
            multiPayer: $multiPayer, paidText: $paidText,
            forOtherOn: $forOtherOn, forOtherUserId: $forOtherUserId
        )
    }

    /// Auto-split: a date inside an auto-split trip preselects it, ONCE.
    ///
    /// `splitTouched` is the whole guard — see its declaration. Runs on the
    /// inputs web's effect depends on, and on nothing else.
    private func applyAutoSplit() {
        guard type == "expense", !splitTouched else { return }
        let candidates = groups.map {
            AutoSplitCandidate(id: $0.id, startDate: $0.startDate, endDate: $0.endDate, autoSplit: $0.autoSplit)
        }
        // The LOCAL calendar day, not UTC: web reads the first 10 chars of a
        // `datetime-local` value, so a 1am expense on the 3rd is the 3rd. An
        // ISO8601 (UTC) string would move it across the trip boundary east of
        // Greenwich. Built per call -- DateFormatter is not Sendable.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        guard let auto = autoSplitGroupFor(groups: candidates, dateIso: fmt.string(from: occurredAt)),
              splitGroupId != auto else { return }
        splitOn = true
        splitGroupId = auto
        splitMembers = membersOf(auto)
        splitMode = SplitModes.equal
    }

    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    // "New account" would be a false affordance here (this
                    // sheet has no path to also present the Accounts flow on
                    // top of itself) -- Close is what it actually does, say so.
                    VStack(spacing: 12) {
                        Text("Add an account first, from the Accounts screen").font(.headline).foregroundColor(Color.text).multilineTextAlignment(.center)
                        Button(S.Translation.commonClose) { dismiss() }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker(S.Transactions.auditType, selection: $type) {
                                Text(S.Transactions.filterExpense).tag("expense")
                                Text(S.Transactions.filterIncome).tag("income")
                                Text(S.Transactions.filterTransfer).tag("transfer")
                            }
                            .pickerStyle(.segmented)
                            .disabled(isInvestment)
                            .onChange(of: isInvestment) { _, inv in if inv { type = "transfer" } }
                            if isInvestment {
                                Text(S.Transactions.investmentTransferOnly)
                                    .font(.system(size: 12)).foregroundColor(Color.text2)
                            }

                            if type == "transfer" {
                                TextField("Amount (\(currency))", text: Binding(
                                    get: { items.first?.value ?? "" },
                                    set: { items = [DraftItem(id: items.first?.id ?? UUID().uuidString, description: "", value: $0)] }
                                ))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            } else {
                                itemsEditor
                            }

                            Text(type == "transfer" ? S.Transactions.fromAccount : S.Transactions.account).font(.system(size: 13)).foregroundColor(Color.text2)
                            ChipRow(options: accounts.map(\.id), selected: accountId ?? account?.id ?? "",
                                    label: { id in accounts.first { $0.id == id }.map { "\($0.name) · \($0.currency)" } ?? "" },
                                    onSelect: { accountId = $0 })

                            if type == "transfer" {
                                Text(S.Transactions.toAccount).font(.system(size: 13)).foregroundColor(Color.text2)
                                ChipRow(options: accounts.filter { $0.id != account?.id }.map(\.id), selected: toAccountId ?? toAccount?.id ?? "",
                                        label: { id in accounts.first { $0.id == id }.map { "\($0.name) · \($0.currency)" } ?? "" },
                                        onSelect: { toAccountId = $0 })
                                if let to = toAccount, to.currency != currency {
                                    TextField("Amount received (\(to.currency))", text: $toValue)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }

                            if type != "transfer" {
                                Text(S.Transactions.category).font(.system(size: 13)).foregroundColor(Color.text2)
                                CategoryPickerView(
                                    categories: relevantCategories,
                                    selectedId: Binding(
                                        get: { categoryId },
                                        set: { picked in
                                            categoryId = picked
                                            manualCategory = true
                                            autoApplied = false
                                        }
                                    )
                                )

                                if !relevantPaymentMethods.isEmpty {
                                    Text(S.Transactions.paymentMethod).font(.system(size: 13)).foregroundColor(Color.text2)
                                    ChipRow(options: relevantPaymentMethods.map(\.id), selected: paymentMethod,
                                            label: { id in relevantPaymentMethods.first { $0.id == id }?.label ?? "" },
                                            onSelect: { paymentMethod = $0 })
                                }
                            }

                            // Web places the two split cards immediately
                            // above Labels, after category and payment method
                            // and before the free-text fields. Both are
                            // expense-only and mutually exclusive;
                            // SplitEditorView decides which (if either) to draw.
                            splitEditor

                            Text(S.Transactions.labelsOptional).font(.system(size: 13)).foregroundColor(Color.text2)
                            LabelPickerRow(available: labelOptions.map(\.name), selected: $selectedLabels)

                            TextField(S.Transactions.noteOptional, text: $note).textFieldStyle(.roundedBorder)

                            DatePicker(S.Transactions.date, selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])

                            if let error { Text(error).foregroundColor(Color.negative).font(.system(size: 13)) }

                            Button(action: save) {
                                Text(saving ? S.Transactions.saving : S.Translation.commonSave)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 12)
                            }
                            .background(Color.accent)
                            .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
                            .disabled(!canSave)
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(S.Transactions.addTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Transactions.cancel) { dismiss() }.foregroundColor(Color.text2)
                }
            }
        }
        .task { await loadLookups() }
        .task { await watchEntitlement() }
        // Re-suggest whenever the text that feeds the categoriser changes.
        // Keyed on the joined string, not on `items`, so moving the cursor or
        // re-selecting text does not re-suggest and stomp a manual choice.
        .onChange(of: autoCategorizeText) { _, _ in scheduleSuggestion() }
        .onChange(of: type) { _, _ in scheduleSuggestion() }
        .onChange(of: type) { _, _ in applyAutoSplit() }
        .onChange(of: occurredAt) { _, _ in applyAutoSplit() }
        .onDisappear {
            suggestTask?.cancel()
            entitlementTask?.cancel()
        }
    }

    private var itemsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($items) { $item in
                HStack {
                    TextField(items.count > 1 ? S.Receipts.kindItem : "What for?", text: $item.description)
                        .textFieldStyle(.roundedBorder)
                    TextField("0.00", text: $item.value)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                    if items.count > 1 {
                        Button("×") { items.removeAll { $0.id == item.id } }
                    }
                }
            }
            Button("+ Add item") { items.append(DraftItem(id: UUID().uuidString, description: "", value: "")) }
                .font(.system(size: 13)).foregroundColor(Color.accent)
        }
    }

    private func loadLookups() async {
        async let acctsTask: () = watchAccountsLoop()
        async let catsTask: () = watchCategoriesLoop()
        async let labelsTask: () = watchLabelsLoop()
        async let methodsTask: () = watchPaymentMethodsLoop()
        async let groupsTask: () = watchGroupsLoop()
        async let membersTask: () = watchGroupMembersLoop()
        async let connsTask: () = watchConnectionsLoop()
        _ = await (acctsTask, catsTask, labelsTask, methodsTask, groupsTask, membersTask, connsTask)
    }

    private func watchGroupsLoop() async {
        do {
            // `includeDirect: false`, matching web's `useGroups()`: a direct
            // group is the 1:1 container "I paid for someone else" creates and
            // is not something to pick from a list.
            for try await list in try splitsRepository.watchGroups(includeDirect: false) {
                groups = list
                applyAutoSplit()
            }
        } catch { print("Failed to watch groups: \(error)") }
    }
    private func watchGroupMembersLoop() async {
        do {
            for try await map in try splitsRepository.watchAllGroupMembers() {
                groupMembers = map
                applyAutoSplit()
            }
        } catch { print("Failed to watch group members: \(error)") }
    }
    private func watchConnectionsLoop() async {
        do {
            guard let userId = authRepository.currentUserId else { return }
            me = userId
            for try await list in try splitsRepository.watchConnections(userId: userId) { connections = list }
        } catch { print("Failed to watch connections: \(error)") }
    }
    private func watchAccountsLoop() async {
        do {
            // Web's picker query carries `NOT_INVESTMENT_ACCOUNT_SQL` — demat,
            // stocks and mutual funds are excluded from the NEW-transaction
            // form entirely (the EDIT form does not filter, because it has to
            // show whatever the transaction already points at). Without it a
            // user could book a grocery expense against their demat account.
            //
            // `isInvestment` above is web's own defensive branch and stays:
            // with this filter in place it can never be true here, exactly as
            // it can never be true on web. Reproducing dead code is the point
            // of a port.
            for try await list in try ledgerRepository.watchAccounts(includeArchived: false) {
                accounts = list.filter { !FormOptions.isInvestmentAccount($0.type) }
            }
        } catch { print("Failed to watch accounts: \(error)") }
    }
    private func watchCategoriesLoop() async {
        do {
            for try await list in try ledgerRepository.watchCategories() { categories = list }
        } catch { print("Failed to watch categories: \(error)") }
    }
    private func watchLabelsLoop() async {
        do {
            for try await list in try ledgerRepository.watchLabels() { labelOptions = list }
        } catch { print("Failed to watch labels: \(error)") }
    }
    private func watchPaymentMethodsLoop() async {
        do {
            for try await list in try ledgerRepository.watchPaymentMethods() { paymentMethods = list }
        } catch { print("Failed to watch payment methods: \(error)") }
    }

    /// What the categoriser reads: every item description plus the note,
    /// exactly as web joins them. A transfer contributes nothing — it has no
    /// category to suggest.
    private var autoCategorizeText: String {
        if type == "transfer" { return "" }
        let descriptions = items
            .map { $0.description.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return [descriptions, note.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Debounced at web's own 220ms.
    ///
    /// The query is two narrow reads, but running them on every keystroke of a
    /// long POS narration would still be dozens of round-trips for one answer.
    /// Cancelling the previous task is what makes it a debounce rather than a
    /// queue.
    private func watchEntitlement() async {
        guard entitlementTask == nil else { return }
        entitlementTask = Task {
            do {
                for try await row in try prefsRepository.watchEntitlement() {
                    isPaid = Domain.isPaid(
                        tier: row?.tier,
                        premiumTrialStartDate: row?.premiumTrialStartDate,
                        compTier: row?.compTier,
                        compUntil: row?.compUntil,
                        now: Date()
                    )
                }
            } catch {
                isPaid = false
            }
        }
        await entitlementTask?.value
    }

    private func scheduleSuggestion() {
        suggestTask?.cancel()
        let text = autoCategorizeText
        guard isPaid, !text.isEmpty, type != "transfer" else {
            suggestedCategoryId = nil
            return
        }
        let options = relevantCategories.map { CategoryData(id: $0.id, name: $0.name) }
        guard !options.isEmpty else { return }
        suggestTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            if Task.isCancelled { return }
            var uid = authRepository.currentUserId
            if uid == nil { uid = try? await authRepository.ensureUser() }
            guard let userId = uid else { return }
            let suggestion = try? await ledgerRepository.suggestCategory(
                text: text, userId: userId, categories: options
            )
            if Task.isCancelled { return }
            suggestedCategoryId = suggestion
            if let suggestion, !manualCategory, categoryId != suggestion {
                categoryId = suggestion
                autoApplied = true
            }
        }
    }

    /// Teach the categoriser from what was actually saved.
    ///
    /// The suggestion is passed ONLY when it was auto-applied. That is web's
    /// rule and it is the load-bearing part: a correction is "you proposed X and
    /// I chose Y", which is only meaningful if X was on screen. Passing a
    /// suggestion the user never saw would record a correction they never made,
    /// and corrections count for five ordinary sightings.
    ///
    /// Best-effort: a learning failure must never turn a saved transaction into
    /// an error the user has to read.
    private func learnFromThisSave(userId: String) async {
        let text = autoCategorizeText
        guard isPaid, !text.isEmpty, let chosen = categoryId else { return }
        try? await ledgerRepository.learnFromSave(
            userId: userId,
            text: text,
            chosenCategoryId: chosen,
            suggestedCategoryId: autoApplied ? suggestedCategoryId : nil
        )
    }

    /// Matches transactions/new/page.tsx's save() for the regular
    /// (non-split) path exactly.
    private func save() {
        guard let acct = account, canSave else { return }
        saving = true
        error = nil
        Task {
            do {
                let userId = try await authRepository.ensureUser()
                let occurredIso = ISO8601DateFormatter().string(from: occurredAt)
                let nonZeroItems = items.filter { (jsParseFloat($0.value) ?? 0) > 0 }
                let splitDescription: String? = {
                    let joined = nonZeroItems
                        .map { $0.description.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")
                    return joined.isEmpty ? nil : joined
                }()
                let trimmedNote = note.trimmingCharacters(in: .whitespaces)

                // Paid entirely for someone else: a 1:1 split where they carry
                // the whole share and you carry none. `mode = "exact"` with your
                // share pinned to 0 is what makes projectPersonal book the full
                // amount as `lend` rather than as your own spending -- the money
                // left your account, but none of it was yours to spend.
                if forOtherIsActive {
                    let person = connections.first { $0.id == forOtherUserId }
                    let groupId = try await splitsRepository.getOrCreateDirectGroup(
                        userId: userId, otherUserId: forOtherUserId,
                        otherName: person?.name ?? "Direct", currency: acct.currency
                    )
                    _ = try await splitsRepository.createSplitExpense(
                        userId: userId,
                        input: SplitExpenseInput(
                            groupId: groupId,
                            mode: SplitModes.exact,
                            total: totalMoney,
                            participants: [
                                ParticipantInput(userId: userId, value: 0),
                                ParticipantInput(userId: forOtherUserId, value: Double(totalMinor)),
                            ],
                            payers: [PayerInput(userId: userId, paid: totalMinor, accountId: acct.id)],
                            categoryId: categoryId,
                            description: splitDescription,
                            note: trimmedNote.isEmpty ? nil : trimmedNote,
                            occurredAt: occurredIso
                        )
                    )
                    await learnFromThisSave(userId: userId)
                    saving = false
                    dismiss()
                    return
                }

                // Split path: book only your share; lend/borrow the rest via the
                // virtual accounts createSplitExpense maintains.
                let currentPlan = plan
                if splitIsActive && currentPlan.valid {
                    _ = try await splitsRepository.createSplitExpense(
                        userId: userId,
                        input: SplitExpenseInput(
                            groupId: splitGroupId,
                            mode: splitMode,
                            total: totalMoney,
                            participants: currentPlan.participants.map {
                                ParticipantInput(userId: $0.userId, value: $0.value)
                            },
                            payers: currentPlan.payers.map {
                                PayerInput(
                                    userId: $0.userId,
                                    paid: $0.paidMinor,
                                    // Only MY leg carries an account -- the
                                    // others' money did not move through one of
                                    // mine, and web writes null for them.
                                    accountId: $0.isMe ? acct.id : nil
                                )
                            },
                            categoryId: categoryId,
                            description: splitDescription,
                            note: trimmedNote.isEmpty ? nil : trimmedNote,
                            occurredAt: occurredIso
                        )
                    )
                    await learnFromThisSave(userId: userId)
                    saving = false
                    dismiss()
                    return
                }

                if type == "transfer" {
                    guard let to = toAccount else { return }
                    let crossCurrency = to.currency != currency
                    _ = try await ledgerRepository.createTransaction(
                        userId: userId, accountId: acct.id, type: "transfer",
                        amount: totalMoney, occurredAt: occurredIso,
                        labels: selectedLabels.isEmpty ? nil : selectedLabels,
                        toAccountId: to.id,
                        toAmount: crossCurrency ? fromMajor(Double(toValue) ?? 0, to.currency) : nil
                    )
                } else {
                    let nonZero = nonZeroItems
                    let combinedDescription = splitDescription ?? ""
                    let itemPayload: [TransactionItemInput]? = nonZero.count > 1
                        ? nonZero.enumerated().map { i, it in
                            TransactionItemInput(
                                description: it.description.trimmingCharacters(in: .whitespaces).isEmpty ? "Item \(i + 1)" : it.description.trimmingCharacters(in: .whitespaces),
                                amount: fromMajor(jsParseFloat(it.value) ?? 0, currency)
                            )
                        }
                        : nil
                    _ = try await ledgerRepository.createTransaction(
                        userId: userId, accountId: acct.id, type: type,
                        amount: totalMoney, occurredAt: occurredIso,
                        categoryId: categoryId, labels: selectedLabels.isEmpty ? nil : selectedLabels,
                        note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces),
                        description: combinedDescription.isEmpty ? nil : combinedDescription,
                        paymentMethod: paymentMethod.isEmpty ? nil : paymentMethod,
                        items: itemPayload
                    )
                    await learnFromThisSave(userId: userId)
                }
                saving = false
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

#Preview {
    CreateTransactionView()
}
