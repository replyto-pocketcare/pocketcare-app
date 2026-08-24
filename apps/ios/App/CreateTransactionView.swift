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

    private var account: Account? { accounts.first { $0.id == accountId } ?? accounts.first }
    private var toAccount: Account? { accounts.first { $0.id == toAccountId } ?? accounts.first { $0.id != account?.id } }
    private var isInvestment: Bool { account?.type == "stocks" || account?.type == "mutual_funds" }
    private var currency: String { account?.currency ?? baseCurrencyNow() }
    private var relevantCategories: [CategoryRow] { categories.filter { $0.kind == (type == "income" ? "income" : "expense") } }
    private var relevantPaymentMethods: [PaymentMethodRow] { paymentMethods.filter { $0.accountTypeId == account?.type } }

    private var total: Double { items.reduce(0) { $0 + (Double($1.value) ?? 0) } }
    private var canSave: Bool {
        guard account != nil, total > 0, !saving else { return false }
        if type == "transfer" { return toAccount != nil && toAccount!.id != account!.id }
        return true
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
                                Text("Investment accounts can only move money via transfers")
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
                                CategoryPickerView(categories: relevantCategories, selectedId: $categoryId)

                                if !relevantPaymentMethods.isEmpty {
                                    Text(S.Transactions.paymentMethod).font(.system(size: 13)).foregroundColor(Color.text2)
                                    ChipRow(options: relevantPaymentMethods.map(\.id), selected: paymentMethod,
                                            label: { id in relevantPaymentMethods.first { $0.id == id }?.label ?? "" },
                                            onSelect: { paymentMethod = $0 })
                                }
                            }

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
        _ = await (acctsTask, catsTask, labelsTask, methodsTask)
    }
    private func watchAccountsLoop() async {
        do {
            for try await list in try ledgerRepository.watchAccounts(includeArchived: false) { accounts = list }
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
                if type == "transfer" {
                    guard let to = toAccount else { return }
                    let crossCurrency = to.currency != currency
                    _ = try await ledgerRepository.createTransaction(
                        userId: userId, accountId: acct.id, type: "transfer",
                        amount: fromMajor(total, currency), occurredAt: occurredIso,
                        labels: selectedLabels.isEmpty ? nil : selectedLabels,
                        toAccountId: to.id,
                        toAmount: crossCurrency ? fromMajor(Double(toValue) ?? 0, to.currency) : nil
                    )
                } else {
                    let nonZero = items.filter { (Double($0.value) ?? 0) > 0 }
                    let combinedDescription = nonZero.map { $0.description.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
                    let itemPayload: [TransactionItemInput]? = nonZero.count > 1
                        ? nonZero.enumerated().map { i, it in
                            TransactionItemInput(
                                description: it.description.trimmingCharacters(in: .whitespaces).isEmpty ? "Item \(i + 1)" : it.description.trimmingCharacters(in: .whitespaces),
                                amount: fromMajor(Double(it.value) ?? 0, currency)
                            )
                        }
                        : nil
                    _ = try await ledgerRepository.createTransaction(
                        userId: userId, accountId: acct.id, type: type,
                        amount: fromMajor(total, currency), occurredAt: occurredIso,
                        categoryId: categoryId, labels: selectedLabels.isEmpty ? nil : selectedLabels,
                        note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces),
                        description: combinedDescription.isEmpty ? nil : combinedDescription,
                        paymentMethod: paymentMethod.isEmpty ? nil : paymentMethod,
                        items: itemPayload
                    )
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
