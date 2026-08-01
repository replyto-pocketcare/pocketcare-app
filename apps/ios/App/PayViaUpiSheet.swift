import SwiftUI
import Domain

struct PayViaUpiSheet: View {
    @Environment(\.dismiss) private var dismiss

    let counterpartyName: String
    let vpa: String
    let amountMinor: Int64
    var note: String = "PocketCare settle-up"

    @State private var showFallback = false
    @State private var copiedNotice: String? = nil

    private var builtIntent: BuiltIntent {
        let params = IntentParams(vpa: vpa, name: counterpartyName, amountMinor: amountMinor, note: note)
        return (try? buildIntentUrl(params)) ?? BuiltIntent(url: "upi://pay", reference: "REF")
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
                        .foregroundColor(Theme.ink)

                    Text(maskedVpa)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(Theme.inkSoft)
                }

                Text("₹\(amountRupees)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(Theme.terracotta)

                Button(action: {
                    if let url = URL(string: builtIntent.url) {
                        UIApplication.shared.open(url) { success in
                            if !success {
                                showFallback = true
                            }
                        }
                    }
                }) {
                    Text("Open UPI App")
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.terracotta)
                        .foregroundColor(Theme.cream)
                        .cornerRadius(12)
                }

                if !showFallback {
                    Button(action: { showFallback = true }) {
                        Text("Didn't open? Pay another way")
                            .font(.caption)
                            .foregroundColor(Theme.inkSoft)
                    }
                }

                if showFallback {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pay manually")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.ink)

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
                            Button("Copy Amount") {
                                UIPasteboard.general.string = amountRupees
                                copiedNotice = "Copied Amount"
                            }
                            .font(.caption)
                        }

                        if let notice = copiedNotice {
                            Text(notice)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.sage)
                        }
                    }
                    .padding(12)
                    .background(Theme.clay100)
                    .cornerRadius(12)
                }

                Spacer()

                Button(action: {
                    dismiss()
                }) {
                    Text("I've paid — tell them")
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.sage)
                        .foregroundColor(Theme.cream)
                        .cornerRadius(12)
                }

                Text("We can't see UPI payments directly, so we'll ask \(counterpartyName) to confirm it arrived.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.inkSoft)
            }
            .padding(20)
            .background(Theme.clay50.ignoresSafeArea())
            .navigationTitle("Pay via UPI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.inkSoft)
                }
            }
        }
    }
}

#Preview {
    PayViaUpiSheet(counterpartyName: "Rahul Sharma", vpa: "rahul@upi", amountMinor: 120000)
}
