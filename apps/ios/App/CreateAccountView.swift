import SwiftUI
import Factory
import Domain
import Data

/// New account — ported from apps/web/app/accounts/new/page.tsx per
/// docs/mobile/screen-specs/accounts.md.
///
/// The credit-card branch was built 2026-08-28. Until then a card created
/// natively silently dropped its limit, statement day, due day and amount due
/// — every field the Cards screen and its reminders are built on — so a card
/// added on the phone was an inert account with a name.
///
/// Mirrors Android's CreateAccountScreen.kt. Rewritten
/// 2026-08-05: the previous version was a native Form/Picker mockup whose
/// Save button called dismiss() and never wrote anything -- no repository
/// call at all, 4 of 7 account types missing, no color, no
/// include-in-net-worth/allow-negative fields.
struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    /// Web routes by TYPE after saving — a new card lands on Cards, a new
    /// demat on Investments — because that is where the thing the user just
    /// made actually lives. Dismissing back to Accounts would leave a credit
    /// card apparently missing.
    @Environment(\.selectTab) private var selectTab
    @Injected(\.ledgerRepository) private var ledgerRepository
    @Injected(\.authRepository) private var authRepository
    @Injected(\.creditCardRepository) private var creditCardRepository

    @State private var name = ""
    @State private var type = "savings"
    @State private var currency = FormOptions.defaultCurrency
    @State private var color = accountColorHex[0]
    @State private var includeInNetWorth = true
    // nil = "follow type default", matches web's `allowNeg: Boolean | null`
    // exactly (accounts/new/page.tsx's allowNegEffective = allowNeg ?? isCard).
    @State private var allowNegativeOverride: Bool?
    @State private var openingBalance = ""
    // ---- credit card ----
    /// The card's limit, as typed. Optional: web stores 0 when it is blank.
    @State private var creditLimit = ""
    /// What is owed on the current statement, as typed.
    @State private var dueAmount = ""
    /// Web's defaults, as STRINGS, because the field is a string and "" has to
    /// survive as "" until save clamps it.
    @State private var statementDay = "1"
    @State private var dueDay = "20"
    @State private var saving = false

    private var allowNegativeEffective: Bool { allowNegativeOverride ?? (type == "credit_card") }

    private var isCard: Bool { type == "credit_card" }
    private var isDemat: Bool { type == "demat" }

    /// Live preview of the cycle, so the user understands the roll-forward rule
    /// before saving rather than after. Nil when there is nothing to preview —
    /// web gates it on `isCard && dueAmount`, and an empty box has no date.
    private var cardPreview: CardDue? {
        guard isCard, !dueAmount.isEmpty else { return nil }
        return cardDueDate(
            createdIso: todayIso(),
            statementDay: clampCardDay(statementDay, fallback: 1),
            dueDay: clampCardDay(dueDay, fallback: 20)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Load-bearing copy, not decorative -- keep verbatim (spec).
                    Text(S.Accounts.noBankLink)
                        .font(.system(size: 13.5))
                        .foregroundColor(Color.text2)

                    TextField(S.Accounts.accountName, text: $name)
                        .textFieldStyle(.roundedBorder)

                    Text(S.Accounts.typeLabel).font(.system(size: 13)).foregroundColor(Color.text2)
                    ChipRow(options: accountTypes, selected: type, label: accountTypeLabel, onSelect: { type = $0 })

                    Text(S.Accounts.currency).font(.system(size: 13)).foregroundColor(Color.text2)
                    ChipRow(options: accountCurrencies, selected: currency, onSelect: { currency = $0 })

                    Text(S.Accounts.colour).font(.system(size: 13)).foregroundColor(Color.text2)
                    ColorSwatchRow(selected: color, onSelect: { color = $0 })

                    Toggle(S.Accounts.includeShort, isOn: $includeInNetWorth)
                    AllowNegativeToggle(isOn: Binding(
                        get: { allowNegativeEffective },
                        set: { allowNegativeOverride = $0 }
                    ))

                    if isCard {
                        cardFields
                    } else if isDemat {
                        TextField(S.Accounts.invested(currency: currency), text: $openingBalance)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text(S.Accounts.dematNote)
                            .font(.system(size: 12))
                            .foregroundColor(Color.text2)
                            .padding(.top, -4)
                    } else {
                        TextField(S.Accounts.openingBalance(currency: currency), text: $openingBalance)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: save) {
                        Text(saving ? S.Accounts.saving : S.Accounts.save)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                    }
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
                .padding(16)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(S.Accounts.newAccount)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Accounts.cancel) { dismiss() }
                        .foregroundColor(Color.text2)
                }
            }
        }
    }

    /// The credit-card branch: limit, amount due, and the two cycle days, with
    /// the live preview underneath.
    ///
    /// The preview is not decoration. The roll-forward rule — enter a balance
    /// after the statement has closed and it is due NEXT cycle — is invisible
    /// in the fields themselves, and a due date the user did not expect reads
    /// as a bug in the app rather than as the rule it is. Web shows the
    /// sentence for exactly that reason, and the date in it comes from Domain,
    /// under vectors.
    @ViewBuilder
    private var cardFields: some View {
        Text(S.Accounts.creditCardDetails).font(.system(size: 13)).foregroundColor(Color.text2)
        HStack(spacing: 8) {
            TextField(S.Accounts.creditLimit(currency: currency), text: $creditLimit)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField(S.Accounts.amountDue(currency: currency), text: $dueAmount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
        HStack(spacing: 8) {
            TextField(S.Accounts.statementDay, text: $statementDay)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                // Web strips non-digits and caps the field at two characters.
                .onChange(of: statementDay) { _, v in statementDay = digits2(v) }
            TextField(S.Accounts.dueDay, text: $dueDay)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: dueDay) { _, v in dueDay = digits2(v) }
        }
        if let preview = cardPreview {
            let amount = "\(currency) \(dueAmount)"
            let date = formatCardDay(preview.dueOn)
            Text(preview.thisCycle
                 ? S.Accounts.dueThisCycle(amount: amount, date: date)
                 : S.Accounts.dueNextCycle(amount: amount, date: date))
                .font(.system(size: 12.5))
                .foregroundColor(Color.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.border, lineWidth: 1)
                }
        }
    }

    /// Matches accounts/new/page.tsx's save() for the regular-account path:
    /// create, then setOpeningBalance if non-zero.
    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !saving else { return }
        saving = true
        Task {
            do {
                // authRepository.currentUserId is unreliable (always nil --
                // see AuthRepositoryImpl.currentUserId's own comment); this
                // repo's established fallback (AppDelegate.swift) is
                // ensureUser(), which works whether the user is a guest or
                // signed in.
                let userId = try await authRepository.ensureUser()
                let accountId = try await ledgerRepository.createAccount(
                    userId: userId,
                    name: name.trimmingCharacters(in: .whitespaces),
                    type: type,
                    currency: currency,
                    color: color,
                    allowNegative: allowNegativeEffective
                )
                // Web creates the row, then UPDATEs the flag off if the toggle
                // was cleared (`accounts/new/page.tsx`) — the INSERT
                // deliberately omits the column so it keeps its read-side
                // default. The toggle was drawn and its value never read: an
                // account excluded from net worth at creation was included
                // anyway.
                if !includeInNetWorth {
                    try await ledgerRepository.updateAccount(id: accountId, values: ["include_in_net_worth": 0])
                }
                if isCard {
                    try await saveCard(userId: userId, accountId: accountId)
                } else if let opening = jsParseFloat(openingBalance), opening != 0 {
                    try await ledgerRepository.setOpeningBalance(
                        userId: userId,
                        accountId: accountId,
                        balance: fromMajor(opening, currency),
                        occurredAt: ISO8601DateFormatter().string(from: Date())
                    )
                }
                saving = false
                dismiss()
                if isCard {
                    selectTab(.cards)
                } else if isDemat {
                    selectTab(.investments)
                }
            } catch {
                print("Failed to create account: \(error)")
                saving = false
            }
        }
    }

    /// The credit-card branch of web's save().
    ///
    /// Three writes, in web's order and for web's reasons:
    ///
    /// 1. **The balance is stored NEGATIVE.** A card's "balance" is what you
    ///    owe, and the ledger stores what the account holds — so an owed amount
    ///    is a negative opening balance. Getting this sign wrong would make a
    ///    debt read as savings in net worth.
    /// 2. **The details row**, with both days clamped to 1...28 so the due date
    ///    is a date that exists in February.
    /// 3. **The cycle**, only when something is owed. `pending_due` is stored
    ///    whatever the cycle says; the roll-forward is expressed by the DATE,
    ///    not by a zero — which is why `thisCycle` drives only the preview
    ///    sentence and never the amount.
    private func saveCard(userId: String, accountId: String) async throws {
        let sDay = clampCardDay(statementDay, fallback: 1)
        let dDay = clampCardDay(dueDay, fallback: 20)
        let owed = jsParseFloat(dueAmount) ?? 0
        if owed != 0 {
            try await ledgerRepository.setOpeningBalance(
                userId: userId,
                accountId: accountId,
                balance: fromMajor(-owed, currency),
                occurredAt: ISO8601DateFormatter().string(from: Date())
            )
        }
        let limit = jsParseFloat(creditLimit) ?? 0
        try await creditCardRepository.upsertDetails(
            userId: userId,
            details: CreditCardDetails(
                accountId: accountId,
                statementDay: sDay,
                dueDay: dDay,
                // Web writes 0 rather than nil for a blank limit, and the Cards
                // screen reads 0 as "no limit set" — keep both halves.
                creditLimit: limit != 0 ? fromMajor(limit, currency).amount : 0,
                cardLast4: nil,
                pendingDue: nil,
                dueOn: nil
            )
        )
        if owed != 0 {
            let due = cardDueDate(createdIso: todayIso(), statementDay: sDay, dueDay: dDay)
            try await creditCardRepository.setCycleDetails(
                accountId: accountId,
                pendingDue: fromMajor(owed, currency).amount,
                dueOnIso: due.dueOn
            )
        }
    }
}

/// Web strips non-digits and caps the day fields at two characters.
private func digits2(_ v: String) -> String {
    String(v.filter(\.isNumber).prefix(2))
}

/// Today as a LOCAL `yyyy-MM-dd`.
///
/// Local, not UTC: the cycle question is "which calendar day is it for the
/// person holding the card", and an ISO8601 instant answers a different one.
private func todayIso() -> String { IsoDay.today() }

/// `yyyy-MM-dd` in the device's own short date format.
///
/// Web calls `toLocaleDateString()` with no locale, which is the browser's.
/// `.dateStyle = .short` with the default locale is the same promise on iOS:
/// the user's format, not ours.
private func formatCardDay(_ iso: String) -> String {
    guard let date = IsoDay.date(from: iso) else { return iso }
    let out = DateFormatter()
    out.dateStyle = .short
    out.timeStyle = .none
    return out.string(from: date)
}

#Preview {
    CreateAccountView()
}
