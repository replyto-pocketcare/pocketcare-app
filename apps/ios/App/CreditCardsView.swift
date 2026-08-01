import SwiftUI

struct CreditCardUiItem: Identifiable {
    let id: String
    let cardName: String
    let bankNetwork: String
    let last4: String
    let outstandingFormatted: String
    let availableLimitFormatted: String
    let dueDate: String
    let gradientColors: [Color]
}

struct CreditCardsView: View {
    let sampleCards = [
        CreditCardUiItem(
            id: "1",
            cardName: "HDFC Regalia Gold",
            bankNetwork: "HDFC Bank • Visa",
            last4: "4821",
            outstandingFormatted: "₹28,450",
            availableLimitFormatted: "₹2,71,550",
            dueDate: "15 Aug 2026",
            gradientColors: [Color(red: 0.17, green: 0.24, blue: 0.31), Color(red: 0.10, green: 0.15, blue: 0.18)]
        ),
        CreditCardUiItem(
            id: "2",
            cardName: "ICICI Amazon Pay",
            bankNetwork: "ICICI Bank • RuPay",
            last4: "9102",
            outstandingFormatted: "₹6,120",
            availableLimitFormatted: "₹1,43,880",
            dueDate: "22 Aug 2026",
            gradientColors: [Theme.terracotta, Color(red: 0.48, green: 0.24, blue: 0.16)]
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(sampleCards) { card in
                        VStack(spacing: 12) {
                            // Card Face (CreditCard.tsx mirror)
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(card.bankNetwork)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(")))")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white.opacity(0.85))
                                }

                                Spacer()

                                // Chip
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(red: 0.91, green: 0.83, blue: 0.66))
                                    .frame(width: 40, height: 30)

                                Spacer()

                                Text("••••  ••••  ••••  \(card.last4)")
                                    .font(.system(.title3, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Spacer()

                                HStack(alignment: .bottom) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("CARD HOLDER")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white.opacity(0.7))
                                        Text(card.cardName)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("DUE DATE")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white.opacity(0.7))
                                        Text(card.dueDate)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .padding(20)
                            .frame(height: 200)
                            .background(LinearGradient(colors: card.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .cornerRadius(18)
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)

                            // Statement & payoff action
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Outstanding: \(card.outstandingFormatted)")
                                        .font(.body)
                                        .fontWeight(.bold)
                                        .foregroundColor(Theme.terracotta)
                                    Text("Available limit: \(card.availableLimitFormatted)")
                                        .font(.caption)
                                        .foregroundColor(Theme.inkSoft)
                                }

                                Spacer()

                                Button(action: {}) {
                                    Text("Pay Bill")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Theme.terracotta)
                                        .foregroundColor(Theme.cream)
                                        .cornerRadius(10)
                                }
                            }
                            .padding(16)
                            .background(Theme.cream)
                            .cornerRadius(14)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.clay50.ignoresSafeArea())
            .navigationTitle("Credit Cards")
        }
    }
}

#Preview {
    CreditCardsView()
}
