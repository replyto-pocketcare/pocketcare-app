import SwiftUI

struct CreditCardsView: View {
    @Binding var isDrawerOpen: Bool
    @State private var viewModel = CreditCardsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(viewModel.cards) { card in
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
                                        .foregroundColor(Color.accent)
                                    Text("Available limit: \(card.availableLimitFormatted)")
                                        .font(.caption)
                                        .foregroundColor(Color.text2)
                                }

                                Spacer()

                                Button(action: {}) {
                                    Text("Pay Bill")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.accent)
                                        .foregroundColor(Color.surface)
                                        .cornerRadius(10)
                                }
                            }
                            .padding(16)
                            .background(Color.surface)
                            .cornerRadius(14)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Credit Cards")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.spring()) {
                            isDrawerOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .imageScale(.large)
                    }
                }
            }
        }
    }
}

#Preview {
    CreditCardsView(isDrawerOpen: .constant(false))
}
