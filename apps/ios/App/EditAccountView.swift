import SwiftUI
import Factory
import Domain
import Data

private enum BalanceMode {
    case direct
    case transaction
}

/// Persisted ledger text, stays English by design -- matches
/// accounts/[id]/edit/page.tsx's ADJUSTMENT_TITLE exactly (data, not UI
/// chrome). Mirrors Android's EditAccountViewModel.kt constant of the same
/// name, added the same session (2026-08-05).
private let adjustmentTitle = "Account Balance Adjustment record"

/// Edit account — ported from apps/web/app/accounts/[id]/edit/page.tsx per
/// docs/mobile/screen-specs/accounts.md: name/type/color/include/allow-neg
/// editing, delete (cascade-or-keep, both soft-delete), and the balance-
/// adjustment tool (direct vs record-as-transaction). New this session --
/// iOS had no edit screen at all before (only a fake New form and a
/// read-only list), so this is a first pass, not a port of an existing file.
struct EditAccountView: View {
    let accountId: String

    @Environment(\.dismiss) private var dismiss
    @Injected(\.ledgerRepository) private var ledgerRepository
    @Injected(\.authRepository) private var authRepository

    @State private var loaded = false
    @State private var name = ""
    @State private var type = "savings"
    @State private var color = accountColorHex[0]
    @State private var includeInNetWorth = true
    @State private var allowNegative = false

    @State private var currentBalance: Money?
    @State private var currentBalanceFormatted = "…"
    @State private var targetBalance = ""
    @State private var balanceMode: BalanceMode = .direct
    @State private var balanceMessage: String?

    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    ProgressView(S.Accounts.loading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            TextField(S.Accounts.accountName, text: $name)
                                .textFieldStyle(.roundedBorder)

                            Text(S.Accounts.typeLabel).font(.system(size: 13)).foregroundColor(Color.text2)
                            ChipRow(options: accountTypes, selected: type, label: accountTypeLabel, onSelect: { type = $0 })

                            Text(S.Accounts.colour).font(.system(size: 13)).foregroundColor(Color.text2)
                            ColorSwatchRow(selected: color, onSelect: { color = $0 })

                            Toggle(S.Accounts.includeShort, isOn: $includeInNetWorth)
                            AllowNegativeToggle(isOn: $allowNegative)

                            HStack(spacing: 10) {
                                Button(S.Accounts.saveChanges, action: save)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                                Button(S.Accounts.cancel) { dismiss() }
                                    .buttonStyle(.bordered)
                                Spacer()
                                Button(S.Accounts.delete) { confirmDelete = true }
                                    .foregroundColor(Color.negative)
                            }

                            Divider().padding(.vertical, 4)

                            balanceAdjustmentCard
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(S.Accounts.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Translation.commonClose) { dismiss() }
                        .foregroundColor(Color.text2)
                }
            }
            .confirmationDialog(S.Accounts.deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(S.Settings.deleteEverything, role: .destructive) { delete(cascade: true) }
                Button("Delete, keep transactions", role: .destructive) { delete(cascade: false) }
                Button(S.Accounts.cancel, role: .cancel) {}
            } message: {
                Text("Deleting keeps your data safe -- this only marks the account (and optionally its transactions) as removed, it isn't a permanent hard delete.")
            }
        }
        .task { await observeAccount() }
    }

    private var balanceAdjustmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adjust balance").font(.system(size: 17, weight: .bold)).foregroundColor(Color.text)
            Text("Current balance: \(currentBalanceFormatted)")
                .font(.system(size: 13)).foregroundColor(Color.text2)
            TextField(S.Accounts.newBalance, text: $targetBalance)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                modeChip(S.Accounts.changeDirectly, mode: .direct)
                modeChip("Record as transaction", mode: .transaction)
            }
            Text(balanceMode == .direct
                ? "A silent correction entry, no category, doesn't show up in insights."
                : "A real income/expense entry, appears in history and insights.")
                .font(.system(size: 12)).foregroundColor(Color.text2)
            Button(S.Accounts.updateBalance, action: applyBalance)
                .buttonStyle(.bordered)
                .disabled(currentBalance == nil || targetBalance.isEmpty)
            if let balanceMessage {
                Text(balanceMessage).font(.system(size: 13)).foregroundColor(Color.text2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous))
    }

    private func modeChip(_ label: String, mode: BalanceMode) -> some View {
        let isSelected = balanceMode == mode
        return Button(label) { balanceMode = mode }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accent : Color.surface2)
            .foregroundColor(isSelected ? .white : Color.text)
            .clipShape(Capsule())
    }

    /// Seeds the editable fields once from the loaded row, then only
    /// refreshes the read-only balance display on subsequent emissions --
    /// mirrors Android's EditAccountViewModel.kt "seed once, preserve
    /// user edits" combine().
    private func observeAccount() async {
        do {
            let stream = try ledgerRepository.watchAccount(id: accountId)
            for try await account in stream {
                guard let account else { continue }
                if !loaded {
                    name = account.name
                    type = account.type
                    color = account.color ?? accountColorHex[0]
                    includeInNetWorth = account.includeInNetWorth
                    allowNegative = account.allowNegative
                    loaded = true
                }
                await refreshBalance()
            }
        } catch {
            print("Failed to observe account \(accountId): \(error)")
        }
    }

    private func refreshBalance() async {
        do {
            let balances = try await ledgerRepository.accountBalances(includeArchived: true)
            guard let match = balances.first(where: { $0.account.id == accountId }) else { return }
            currentBalance = match.balance
            currentBalanceFormatted = formatMoneyAware(match.balance)
        } catch {
            print("Failed to load balance for \(accountId): \(error)")
        }
    }

    private func save() {
        Task {
            do {
                try await ledgerRepository.updateAccount(id: accountId, values: [
                    "name": name.trimmingCharacters(in: .whitespaces),
                    "type": type,
                    "color": color,
                    "include_in_net_worth": includeInNetWorth,
                    "allow_negative": allowNegative,
                ])
                dismiss()
            } catch {
                print("Failed to save account \(accountId): \(error)")
            }
        }
    }

    /// Matches accounts/[id]/edit/page.tsx's deleteAccount(cascade) exactly:
    /// cascade soft-deletes the account's transactions first, then the
    /// account; "keep" soft-deletes only the account.
    private func delete(cascade: Bool) {
        deleting = true
        Task {
            do {
                if cascade {
                    try await ledgerRepository.cascadeDeleteAccountTransactions(accountId: accountId)
                }
                try await ledgerRepository.deleteAccount(id: accountId)
                deleting = false
                dismiss()
            } catch {
                print("Failed to delete account \(accountId): \(error)")
                deleting = false
            }
        }
    }

    /// Matches accounts/[id]/edit/page.tsx's applyBalance() exactly: delta =
    /// target - current (minor units); "direct" writes a no-category
    /// `adjustment` transaction, "transaction" writes a real income/expense
    /// sized to |delta|. Both use adjustmentTitle as the description
    /// (persisted ledger text -- stays English, never localized).
    private func applyBalance() {
        guard let current = currentBalance, let targetMajor = Double(targetBalance) else { return }
        let target = fromMajor(targetMajor, current.currency)
        let delta = target.amount - current.amount
        if delta == 0 {
            balanceMessage = "Already at that balance"
            return
        }
        Task {
            do {
                let userId = try await authRepository.ensureUser()
                let now = ISO8601DateFormatter().string(from: Date())
                if balanceMode == .direct {
                    try await ledgerRepository.createTransaction(
                        userId: userId, accountId: accountId, type: "adjustment",
                        amount: money(delta, current.currency), occurredAt: now,
                        note: "Balance adjustment", description: adjustmentTitle
                    )
                } else {
                    try await ledgerRepository.createTransaction(
                        userId: userId, accountId: accountId,
                        type: delta > 0 ? "income" : "expense",
                        amount: money(abs(delta), current.currency), occurredAt: now,
                        note: "Balance adjustment", description: adjustmentTitle
                    )
                }
                let formattedTarget = formatMoneyAware(target)
                balanceMessage = "Balance updated to \(formattedTarget)"
                targetBalance = ""
            } catch {
                print("Failed to apply balance adjustment for \(accountId): \(error)")
            }
        }
    }
}

#Preview {
    EditAccountView(accountId: "preview")
}
