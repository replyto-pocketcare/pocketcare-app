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
    @Binding var isDrawerOpen: Bool
    @State private var selectedFilter = "All"

    @State private var viewModel = InvestmentsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Portfolio Summary Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Total Portfolio Value")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(Color.text2)

                        Text(viewModel.totalValueFormatted)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(Color.text)

                        HStack {
                            Text(viewModel.totalReturnFormatted)
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(viewModel.isTotalReturnPositive ? Color.positive.opacity(0.3) : Color.accent.opacity(0.3))
                                .foregroundColor(viewModel.isTotalReturnPositive ? Color.positive : Color.accent)
                                .cornerRadius(6)

                            Spacer()

                            Text("All-Time Return")
                                .font(.caption)
                                .foregroundColor(Color.text2)
                        }
                    }
                    .padding(20)
                    .background(Color.surface)
                    .cornerRadius(18)

                    // Holdings List
                    VStack(spacing: 12) {
                        ForEach(viewModel.holdings) { holding in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(holding.name)
                                        .font(.body)
                                        .fontWeight(.bold)
                                        .foregroundColor(Color.text)

                                    Text("\(holding.symbolExchange) • \(holding.quantity)")
                                        .font(.caption)
                                        .foregroundColor(Color.text2)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(holding.currentValueFormatted)
                                        .font(.body)
                                        .fontWeight(.bold)
                                        .foregroundColor(Color.text)

                                    Text(holding.returnFormatted)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(holding.isPositiveReturn ? Color.positive : Color.accent)
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
            .navigationTitle("Investments")
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {}) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(Color.accent)
                    }
                }
            }
        }
    }
}

#Preview {
    InvestmentsView(isDrawerOpen: .constant(false))
}
