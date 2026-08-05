import SwiftUI
import Factory
import Domain
import Data

/// New account — ported from apps/web/app/accounts/new/page.tsx per
/// docs/mobile/screen-specs/accounts.md, regular-account path only (credit
/// card / demat branches deferred to those screens, see spec). Rewritten
/// 2026-08-05: the previous version was a native Form/Picker mockup whose
/// Save button called dismiss() and never wrote anything -- no repository
/// call at all, 4 of 7 account types missing, no color, no
/// include-in-net-worth/allow-negative fields.
struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Injected(\.ledgerRepository) private var ledgerRepository
    @Injected(\.authRepository) private var authRepository

    @State private var name = ""
    @State private var type = "savings"
    @State private var currency = "INR"
    @State private var color = accountColorHex[0]
    @State private var includeInNetWorth = true
    // nil = "follow type default", matches web's `allowNeg: Boolean | null`
    // exactly (accounts/new/page.tsx's allowNegEffective = allowNeg ?? isCard).
    @State private var allowNegativeOverride: Bool?
    @State private var openingBalance = ""
    @State private var saving = false

    private var allowNegativeEffective: Bool { allowNegativeOverride ?? (type == "credit_card") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Load-bearing copy, not decorative -- keep verbatim (spec).
                    Text("Nothing here connects to your bank. You're naming a place your money sits and typing in the amount yourself.")
                        .font(.system(size: 13.5))
                        .foregroundColor(Color.text2)

                    TextField("Account name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Text("Type").font(.system(size: 13)).foregroundColor(Color.text2)
                    ChipRow(options: accountTypes, selected: type, label: accountTypeLabel, onSelect: { type = $0 })

                    Text("Currency").font(.system(size: 13)).foregroundColor(Color.text2)
                    ChipRow(options: accountCurrencies, selected: currency, onSelect: { currency = $0 })

                    Text("Colour").font(.system(size: 13)).foregroundColor(Color.text2)
                    ColorSwatchRow(selected: color, onSelect: { color = $0 })

                    Toggle("Include in net worth", isOn: $includeInNetWorth)
                    AllowNegativeToggle(isOn: Binding(
                        get: { allowNegativeEffective },
                        set: { allowNegativeOverride = $0 }
                    ))

                    TextField("Opening balance (\(currency))", text: $openingBalance)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)

                    Button(action: save) {
                        Text(saving ? "Saving…" : "Save")
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
            .navigationTitle("New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                }
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
                if let opening = Double(openingBalance), opening != 0 {
                    try await ledgerRepository.setOpeningBalance(
                        userId: userId,
                        accountId: accountId,
                        balance: fromMajor(opening, currency),
                        occurredAt: ISO8601DateFormatter().string(from: Date())
                    )
                }
                saving = false
                dismiss()
            } catch {
                print("Failed to create account: \(error)")
                saving = false
            }
        }
    }
}

#Preview {
    CreateAccountView()
}
