import SwiftUI
import Domain

struct PayViaUpiSheet: View {
    @Environment(\.dismiss) private var dismiss

    let counterpartyName: String
    let vpa: String
    let amountMinor: Int64
    var note: String = "Sanvya settle-up"
    /// Called with the built intent's `tr=` reference just before dismissing,
    /// when the user taps "Mark as paid" -- added task #30 so
    /// Splits' settle-up flow can record a "pending" settlement the payee
    /// still has to confirm (matches PayViaUpi.tsx's own `onPaid: (ref:
    /// string) => void` prop). Optional/no-op default so this stays a
    /// source-compatible change for any other future caller.
    var onPaid: (String) -> Void = { _ in }

    @State private var showFallback = false
    @State private var copiedNotice: String? = nil

    private var builtIntent: BuiltIntent? {
        let params = IntentParams(vpa: vpa, name: counterpartyName, amountMinor: Double(amountMinor), note: note)
        return try? buildIntentUrl(params)
    }

    private var maskedVpa: String {
        maskVpa(vpa)
    }

    private var amountRupees: String {
        String(format: "%.2f", Double(amountMinor) / 100.0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("Paying \(counterpartyName)")
                        .font(.headline)
                        .foregroundColor(Color.text)

                    Text(maskedVpa)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(Color.text2)
                }

                Text("₹\(amountRupees)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(Color.accent)

                Button(action: {
                    if let intentUrl = builtIntent?.url, let url = URL(string: intentUrl) {
                        UIApplication.shared.open(url) { success in
                            if !success {
                                showFallback = true
                            }
                        }
                    } else {
                        showFallback = true
                    }
                }) {
                    Text(S.Payments.payOpenApp)
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accent)
                        .foregroundColor(Color.surface)
                        .cornerRadius(12)
                }

                if !showFallback {
                    Button(action: { showFallback = true }) {
                        Text(S.Payments.payDidntOpen)
                            .font(.caption)
                            .foregroundColor(Color.text2)
                    }
                }

                if showFallback {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pay manually")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(Color.text)

                        HStack {
                            Text(vpa)
                                .font(.caption)
                                .fontDesign(.monospaced)
                            Spacer()
                            Button("Copy ID") {
                                UIPasteboard.general.string = vpa
                                copiedNotice = "Copied UPI ID"
                            }
                            .font(.caption)
                        }

                        HStack {
                            Text("₹\(amountRupees)")
                                .font(.caption)
                                .fontDesign(.monospaced)
                            Spacer()
                            Button(S.Payments.payCopyAmount) {
                                UIPasteboard.general.string = amountRupees
                                copiedNotice = "Copied Amount"
                            }
                            .font(.caption)
                        }

                        if let notice = copiedNotice {
                            Text(notice)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(Color.positive)
                        }
                    }
                    .padding(12)
                    .background(Color.surface2)
                    .cornerRadius(12)
                }

                Spacer()

                Button(action: {
                    onPaid(builtIntent?.ref ?? "")
                    dismiss()
                }) {
                    Text(S.Payments.payMarkPaid)
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.positive)
                        .foregroundColor(Color.surface)
                        .cornerRadius(12)
                }

                Text("We can't see UPI payments directly, so we'll ask \(counterpartyName) to confirm it arrived.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.text2)
            }
            .padding(20)
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(S.Payments.payButton)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Translation.commonCancel) { dismiss() }
                        .foregroundColor(Color.text2)
                }
            }
        }
    }
}

#Preview {
    PayViaUpiSheet(counterpartyName: "Rahul Sharma", vpa: "rahul@upi", amountMinor: 120000)
}
