import SwiftUI
import Factory
import Domain
import Data

private struct DraftItem: Identifiable {
    let id: String
    var description: String
    var value: String
}

/// Edit transaction — ported from transactions/[id]/edit/page.tsx per
/// docs/mobile/screen-specs/transactions.md. iOS had no edit screen for
/// transactions at all before this (only a fake New form and a
/// non-interactive list row). The edit-history sheet and the split-expense
/// banner, deferred by that first port, are both here now.
struct EditTransactionView: View {
    let transactionId: String

    @Environment(\.dismiss) private var dismiss
    @Injected(\.ledgerRepository) private var ledgerRepository
    @Injected(\.authRepository) private var authRepository
    @Injected(\.prefsRepository) private var prefsRepository

    @State private var loaded = false
    @State private var accounts: [Account] = []
    @State private var categories: [CategoryRow] = []
    @State private var labelOptions: [LabelRow] = []
    @State private var paymentMethods: [PaymentMethodRow] = []

    @State private var type = "expense"
    @State private var accountId = ""
    @State private var transferAmount = ""
    @State private var items: [DraftItem] = []
    @State private var categoryId: String?
    @State private var selectedLabels: [String] = []
    @State private var paymentMethod = ""
    @State private var note = ""
    @State private var intent: String?
    @State private var currency = FormOptions.defaultCurrency
    @State private var occurredAt = Date()

    /// The split expense this row belongs to, or nil for an ordinary one.
    @State private var split: TransactionSplit?
    /// Every recorded change to this transaction, newest first.
    @State private var history: [TransactionAudit] = []
    @State private var showHistory = false
    /// The group the split banner was asked to open, presented over this form.
    @State private var openGroupId: String?

    @State private var saving = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?

    /// The category the transaction ALREADY had when it was opened.
    ///
    /// This is the "suggestion" the categoriser learns against on this screen.
    /// Web passes `originalCategoryId` where the create screen passes the
    /// auto-applied suggestion, and the two mean the same thing: something was
    /// on screen proposing a category, and the user chose otherwise. Changing it
    /// is a correction, and `scoreTokens` weights a correction at five ordinary
    /// sightings.
    @State private var originalCategoryId: String?

    /// The categoriser is a paid feature and web gates BOTH halves on it —
    /// `if (type !== "transfer" && isPaid && categoryId !== originalCategoryId)`.
    /// Starts CLOSED and stays closed if the entitlement can't be read: a gate
    /// that fails open is not a gate.
    @State private var isPaid = false

    private var account: Account? { accounts.first { $0.id == accountId } }
    private var relevantCategories: [CategoryRow] { categories.filter { $0.kind == (type == "income" ? "income" : "expense") } }
    private var relevantPaymentMethods: [PaymentMethodRow] { paymentMethods.filter { $0.accountTypeId == account?.type } }

    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    ProgressView(S.Transactions.loading).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            SplitBannerView(
                                split: split,
                                myUserId: authRepository.currentUserId,
                                onOpenGroup: { openGroupId = $0 }
                            )

                            Picker(S.Transactions.auditType, selection: $type) {
                                // `type.*`, not `filter.*`: the form's three
                                // chips come from web's `t(`type.${tp}`)`, and
                                // the two namespaces are free to diverge.
                                Text(S.Transactions.typeExpense).tag("expense")
                                Text(S.Transactions.typeIncome).tag("income")
                                Text(S.Transactions.typeTransfer).tag("transfer")
                            }
                            .pickerStyle(.segmented)

                            Text(S.Transactions.account).font(.system(size: 13)).foregroundColor(Color.text2)
                            ChipRow(options: accounts.map(\.id), selected: accountId,
                                    label: { id in accounts.first { $0.id == id }?.name ?? "" },
                                    onSelect: { accountId = $0 })

                            if type == "transfer" {
                                TextField(S.Transactions.amountCurrency(currency: currency), text: $transferAmount)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                amountCard

                                Text(S.Transactions.category).font(.system(size: 13)).foregroundColor(Color.text2)
                                CategoryPickerView(categories: relevantCategories, selectedId: $categoryId)

                                if !relevantPaymentMethods.isEmpty {
                                    Text(S.Transactions.paymentMethod).font(.system(size: 13)).foregroundColor(Color.text2)
                                    ChipRow(options: relevantPaymentMethods.map(\.id), selected: paymentMethod,
                                            label: { id in relevantPaymentMethods.first { $0.id == id }?.label ?? "" },
                                            onSelect: { paymentMethod = $0 })
                                }
                            }

                            Text(S.Transactions.labels).font(.system(size: 13)).foregroundColor(Color.text2)
                            LabelPickerRow(available: labelOptions.map(\.name), selected: $selectedLabels)

                            if type == "expense" {
                                Text("Intent (mindfulness)").font(.system(size: 13)).foregroundColor(Color.text2)
                                HStack(spacing: 8) {
                                    intentChip("Untagged", value: nil, color: Color.text)
                                    intentChip("Need", value: "need", color: Color.positive)
                                    intentChip("Greed", value: "greed", color: Color.negative)
                                }
                            }

                            TextField(S.Transactions.note, text: $note).textFieldStyle(.roundedBorder)

                            DatePicker(S.Transactions.date, selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])

                            if let error { Text(error).foregroundColor(Color.negative).font(.system(size: 13)) }

                            HStack(spacing: 10) {
                                Button(saving ? S.Transactions.saving : S.Transactions.saveChanges, action: save)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(saving)
                                Button(S.Transactions.cancel) { dismiss() }.buttonStyle(.bordered)
                                Spacer()
                                Button(S.Transactions.delete) { confirmDelete = true }.foregroundColor(Color.negative)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(S.Transactions.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Translation.commonClose) { dismiss() }.foregroundColor(Color.text2)
                }
                // Web hides this behind a kebab with exactly one item; a plain
                // toolbar button is the native equivalent, and the same call
                // GroupDetailView made when it turned web's kebab into chips.
                // Hidden entirely when nothing has been recorded yet, matching
                // web's `{audit.length > 0 && ...}`.
                if !history.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(S.Transactions.viewHistory) { showHistory = true }
                            .foregroundColor(Color.accent)
                    }
                }
            }
            .sanvyaModal(isPresented: $showHistory, label: S.Transactions.editHistory) {
                EditHistorySheet(
                    entries: history,
                    currency: currency,
                    categories: categories,
                    accounts: accounts,
                    paymentMethods: paymentMethods,
                    onClose: { showHistory = false }
                )
            }
            // Web's banner links to /groups/[id] and navigates away from the
            // form. This shell has no detail routing above a sheet (see
            // AppDestinations' note on why), so the group is presented OVER the
            // form instead — which also means dismissing it returns to the edit
            // in progress rather than discarding it.
            //
            // The `NavigationStack` with a Close item is not decoration:
            // `GroupDetailView` is documented as embedded content whose back
            // button lives in its PARENT's toolbar, and inside a sheet the app
            // shell's `registerBack` is not there to supply one.
            .sheet(item: Binding(
                get: { openGroupId.map(OpenGroup.init(id:)) },
                set: { openGroupId = $0?.id }
            )) { target in
                NavigationStack {
                    GroupDetailView(groupId: target.id, onBack: { openGroupId = nil })
                        .padding(16)
                        .background(Color.bg.ignoresSafeArea())
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(S.Translation.commonClose) { openGroupId = nil }
                                    .foregroundColor(Color.text2)
                            }
                        }
                }
            }
            .confirmationDialog(S.Transactions.deleteConfirmTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(S.Transactions.delete, role: .destructive) { delete() }
                Button(S.Transactions.cancel, role: .cancel) {}
            } message: {
                Text("This can't be undone from here.")
            }
        }
        .task { await loadAll() }
    }

    private func intentChip(_ label: String, value: String?, color: Color) -> some View {
        let selected = intent == value
        return Button(label) { intent = value }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? color.opacity(0.18) : Color.surface2)
            .foregroundColor(selected ? color : Color.text)
            .clipShape(Capsule())
    }

    /**
     The running total of the item rows, in the transaction's own currency.

     Web heads the amount card with it (`format(total, "en-US")`), and it is the
     only place an edited multi-item expense shows what it now comes to — the
     rows themselves each show a part. This port had the rows and not the sum.

     Summed per ITEM, not on the sum, so each item rounds the way web's does,
     and through `fromMajor` so a zero-decimal currency is not read as a
     hundredth of itself.
     */
    private var totalMoney: Money {
        money(items.reduce(Int64(0)) { $0 + fromMajor(jsParseFloat($1.value) ?? 0, currency).amount }, currency)
    }

    /// Web's amount card: the running total as the headline, the item rows that
    /// feed it underneath.
    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(items.count > 1 ? S.Transactions.amountWithItems : S.Transactions.amount)
                    .font(.system(size: 13))
                    .foregroundColor(Color.text2)
                // Unmasked: the user is editing this number, and the
                // hide-amounts mask would make the form unusable. Web reaches
                // past `useMoneyFmt` here for the same reason.
                Text(formatMoneyUnmasked(totalMoney))
                    .font(.system(size: 40, weight: .bold))
                    // Web's edit page has only the two colours — it draws the
                    // card for expense and income only, never for a transfer.
                    .foregroundColor(type == "expense" ? Color.negative : Color.positive)
            }
            itemsEditor
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous))
    }

    private var itemsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($items) { $item in
                HStack {
                    TextField(
                        items.count > 1
                            ? S.Transactions.item(n: String(itemNumber(of: item.id)))
                            : S.Transactions.whatFor,
                        text: $item.description
                    )
                    .textFieldStyle(.roundedBorder)
                    TextField(amountPlaceholder, text: $item.value)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                    if items.count > 1 {
                        Button("×") { items.removeAll { $0.id == item.id } }
                            .foregroundColor(Color.text2)
                    }
                }
            }
            Button(S.Transactions.addItemSplit) { items.append(DraftItem(id: UUID().uuidString, description: "", value: "")) }
                .font(.system(size: 13)).foregroundColor(Color.accent)
        }
    }

    /// 1-based position of a draft row — web's `t("item", { n: idx + 1 })`.
    ///
    /// Looked up by id rather than taken from `ForEach`'s index, because the
    /// binding form of `ForEach` hands back the element, not its offset.
    private func itemNumber(of id: String) -> Int {
        (items.firstIndex { $0.id == id } ?? 0) + 1
    }

    private func loadAll() async {
        async let a: () = watchAccountsLoop()
        async let c: () = watchCategoriesLoop()
        async let l: () = watchLabelsLoop()
        async let p: () = watchPaymentMethodsLoop()
        async let t: () = watchTransactionLoop()
        async let e: () = watchEntitlement()
        async let s: () = watchSplitLoop()
        async let h: () = watchHistoryLoop()
        _ = await (a, c, l, p, t, e, s, h)
    }
    private func watchSplitLoop() async {
        do { for try await found in try ledgerRepository.watchSplitForTransaction(transactionId: transactionId) { split = found } }
        catch { print("Failed to watch split for \(transactionId): \(error)") }
    }
    private func watchHistoryLoop() async {
        do { for try await rows in try ledgerRepository.watchHistory(transactionId: transactionId) { history = rows } }
        catch { print("Failed to watch history for \(transactionId): \(error)") }
    }
    private func watchAccountsLoop() async {
        do { for try await list in try ledgerRepository.watchAccounts(includeArchived: true) { accounts = list } }
        catch { print("Failed to watch accounts: \(error)") }
    }
    private func watchCategoriesLoop() async {
        do { for try await list in try ledgerRepository.watchCategories() { categories = list } }
        catch { print("Failed to watch categories: \(error)") }
    }
    private func watchLabelsLoop() async {
        do { for try await list in try ledgerRepository.watchLabels() { labelOptions = list } }
        catch { print("Failed to watch labels: \(error)") }
    }
    private func watchPaymentMethodsLoop() async {
        do { for try await list in try ledgerRepository.watchPaymentMethods() { paymentMethods = list } }
        catch { print("Failed to watch payment methods: \(error)") }
    }

    /// Seeds the editable fields once from the loaded row + its items/labels,
    /// then leaves them alone -- mirrors Android's EditTransactionViewModel's
    /// "seed once, preserve user edits" pattern.
    private func watchTransactionLoop() async {
        do {
            for try await txns in try ledgerRepository.watchAllTransactions() {
                guard let txn = txns.first(where: { $0.id == transactionId }) else { continue }
                guard !loaded else { continue }
                let labelNames = (try? await currentLabelNames()) ?? []
                let fetchedItems = (try? await ledgerRepository.items(transactionId: transactionId)) ?? []
                let drafts: [DraftItem]
                if !fetchedItems.isEmpty {
                    // `toMajor`, not `/ 100.0`: the field is edited in MAJOR
                    // units and saved back through `fromMajor`, so a hardcoded
                    // scale here would show a JPY amount a hundred times too
                    // small and then save that back as the truth.
                    drafts = fetchedItems.map { DraftItem(id: $0.id, description: $0.description, value: String(toMajor(money($0.amount, txn.currency)))) }
                } else {
                    drafts = [DraftItem(id: "new_\(Date().timeIntervalSince1970)", description: txn.description ?? "", value: String(toMajor(money(txn.amount, txn.currency))))]
                }
                type = txn.type
                accountId = txn.accountId
                transferAmount = String(toMajor(money(txn.amount, txn.currency)))
                items = drafts
                categoryId = txn.categoryId
                originalCategoryId = txn.categoryId
                selectedLabels = labelNames
                paymentMethod = txn.paymentMethod ?? ""
                note = txn.note ?? ""
                intent = txn.intent
                currency = txn.currency
                occurredAt = parseOccurredAt(txn.occurredAt) ?? Date()
                loaded = true
            }
        } catch { print("Failed to watch transaction \(transactionId): \(error)") }
    }

    private func currentLabelNames() async throws -> [String] {
        for try await map in try ledgerRepository.watchTransactionLabelNames() {
            return map[transactionId] ?? []
        }
        return []
    }

    /// Matches transactions/[id]/edit/page.tsx's save() exactly.
    private func save() {
        saving = true
        error = nil
        Task {
            do {
                let userId = try await authRepository.ensureUser()
                var patch: [String: Sendable?] = [
                    "type": type,
                    "account_id": accountId,
                    "payment_method": paymentMethod.isEmpty ? nil : paymentMethod,
                    "note": note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces),
                    "occurred_at": ISO8601DateFormatter().string(from: occurredAt),
                ]
                if type == "transfer" {
                    patch["amount"] = fromMajor(Double(transferAmount) ?? 0, currency).amount
                    // `patch["k"] = nil` (the literal) is special-cased by
                    // Swift's Dictionary subscript setter to REMOVE the key,
                    // even though patch's Value type (Sendable?) is itself
                    // Optional -- it does NOT set an explicit null the way
                    // updateTransaction's patch semantics need ("present key,
                    // nil value" must survive so track() actually clears the
                    // column). updateValue(_:forKey:) takes a plain `Value`
                    // param (not `Value?`), so it inserts/overwrites instead
                    // of removing.
                    patch.updateValue(nil, forKey: "category_id")
                    patch.updateValue(nil, forKey: "description")
                    // Deliberately NOT setting "items" here: Swift's Dictionary
                    // subscript can't cleanly express "set this Sendable?
                    // value to an explicit nil" vs "remove the key" for a
                    // doubly-optional value type without a fragile cast, so
                    // this leaves any pre-existing items untouched rather
                    // than risk a wrong cast. Matches "absent = don't touch"
                    // (the safe subset of updateTransaction's patch
                    // semantics) -- only matters for the rare edit where a
                    // multi-item expense/income is retyped to a transfer.
                } else {
                    let nonZero = items.filter { (Double($0.value) ?? 0) > 0 }
                    let totalMinor = nonZero.reduce(Int64(0)) { $0 + fromMajor(Double($1.value) ?? 0, currency).amount }
                    patch["amount"] = totalMinor
                    patch["category_id"] = categoryId
                    let combined = nonZero.map { $0.description.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
                    patch["description"] = combined.isEmpty ? nil : combined
                    if nonZero.count > 1 {
                        patch["items"] = nonZero.enumerated().map { i, it -> TransactionItemInput in
                            let desc = it.description.trimmingCharacters(in: .whitespaces)
                            return TransactionItemInput(description: desc.isEmpty ? "Item \(i + 1)" : desc, amount: fromMajor(Double(it.value) ?? 0, currency))
                        }
                    } else {
                        patch["items"] = [TransactionItemInput]()
                    }
                    if type == "expense" { patch["intent"] = intent }
                }
                patch["labels"] = selectedLabels
                try await ledgerRepository.updateTransaction(userId: userId, id: transactionId, patch: patch)
                await learnFromThisSave(userId: userId, description: patch["description"] as? String)
                saving = false
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }

    private func watchEntitlement() async {
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

    /// Teach the categoriser from a re-categorisation.
    ///
    /// Three differences from the create screen, all of them web's:
    ///
    /// * only fires when the category actually CHANGED. Re-saving a transaction
    ///   without touching its category is not evidence of anything.
    /// * the text is the combined DESCRIPTION only, not description + note. The
    ///   create screen joins the note in; this one does not, and mirroring that
    ///   matters because the two write into the same rule table — a phrase rule
    ///   keyed on "coffee" and one keyed on "coffee paid back Ravi" are
    ///   different rules, and only one of them will ever match again.
    /// * `originalCategoryId` plays the suggestion's part.
    ///
    /// Best-effort: a learning failure must never turn a saved edit into an
    /// error the user has to read.
    private func learnFromThisSave(userId: String, description: String?) async {
        guard type != "transfer", isPaid, categoryId != originalCategoryId else { return }
        try? await ledgerRepository.learnFromSave(
            userId: userId,
            // `|| ""` on web: an item-less transaction still learns nothing,
            // because learnFromSave itself returns early on empty text.
            text: description ?? "",
            chosenCategoryId: categoryId,
            suggestedCategoryId: originalCategoryId
        )
    }

    private func delete() {
        deleting = true
        Task {
            do {
                let userId = try await authRepository.ensureUser()
                try await ledgerRepository.removeTransaction(userId: userId, id: transactionId)
                deleting = false
                dismiss()
            } catch {
                self.error = error.localizedDescription
                deleting = false
            }
        }
    }
}

/// A group id, made `Identifiable` so `.sheet(item:)` can drive off it. A bare
/// `String` cannot: `Identifiable` needs an `id`, and conforming `String` to it
/// app-wide would make every string a sheet subject.
private struct OpenGroup: Identifiable {
    let id: String
}

#Preview {
    EditTransactionView(transactionId: "preview")
}
