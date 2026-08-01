import SwiftUI

struct HoldingUiItem: Identifiable {
    let id: String
    let name: String
    let symbolExchange: String
    let assetClass: String
    let quantity: String
    let currentValueFormatted: String
    let returnFormatted: String
    let isPositiveReturn: Bool
}

struct InvestmentsView: View {
    @State private var selectedFilter = "All"

    let sampleHoldings = [
        HoldingUiItem(id: "1", name: "Reliance Industries", symbolExchange: "RELIANCE • NSE", assetClass: "stock", quantity: "25 shares", currentValueFormatted: "₹76,250", returnFormatted: "+18.4%", isPositiveReturn: true),
        HoldingUiItem(id: "2", name: "HDFC Flexi Cap Fund", symbolExchange: "INF179KC1951 • MF", assetClass: "mutual_fund", quantity: "1,420 units", currentValueFormatted: "₹1,12,000", returnFormatted: "+24.8%", isPositiveReturn: true),
        HoldingUiItem(id: "3", name: "Nifty 50 Index SIP", symbolExchange: "MONTHLY SIP", assetClass: "sip", quantity: "₹5,000/mo", currentValueFormatted: "₹48,000", returnFormatted: "+12.1%", isPositiveReturn: true),
        HoldingUiItem(id: "4", name: "Bitcoin", symbolExchange: "BTC • Crypto", assetClass: "crypto", quantity: "0.025 BTC", currentValueFormatted: "₹1,45,000", returnFormatted: "-4.2%", isPositiveReturn: false),
        HoldingUiItem(id: "5", name: "HDFC 1-Year FD", symbolExchange: "7.25% p.a.", assetClass: "fd", quantity: "1 Deposit", currentValueFormatted: "₹1,00,000", returnFormatted: "+7.25%", isPositiveReturn: true)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Portfolio Summary Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Total Portfolio Value")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.inkSoft)

                        Text("₹4,81,250")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(Theme.ink)

                        HStack {
                            Text("▲ +₹68,400 (+16.5%)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.sage.opacity(0.3))
                                .foregroundColor(Theme.sage)
                                .cornerRadius(6)

                            Spacer()

                            Text("All-Time Return")
                                .font(.caption)
                                .foregroundColor(Theme.inkSoft)
                        }
                    }
                    .padding(20)
                    .background(Theme.cream)
                    .cornerRadius(18)

                    // Holdings List
                    VStack(spacing: 12) {
                        ForEach(sampleHoldings) { holding in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(holding.name)
                                        .font(.body)
                                        .fontWeight(.bold)
                                        .foregroundColor(Theme.ink)

                                    Text("\(holding.symbolExchange) • \(holding.quantity)")
                                        .font(.caption)
                                        .foregroundColor(Theme.inkSoft)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(holding.currentValueFormatted)
                                        .font(.body)
                                        .fontWeight(.bold)
                                        .foregroundColor(Theme.ink)

                                    Text(holding.returnFormatted)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(holding.isPositiveReturn ? Theme.sage : Theme.terracotta)
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
            .navigationTitle("Investments")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {}) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(Theme.terracotta)
                    }
                }
            }
        }
    }
}

#Preview {
    InvestmentsView()
}
