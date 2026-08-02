import SwiftUI
import Factory

struct DashboardView: View {
    @Binding var isDrawerOpen: Bool
    @State private var viewModel = Container.shared.dashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Net Worth Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("NET WORTH")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.surface.opacity(0.8))

                        Text(viewModel.netWorthFormatted)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color.surface)

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Assets")
                                    .font(.caption2)
                                    .foregroundColor(Color.surface.opacity(0.7))
                                Text(viewModel.assetsFormatted)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color.surface)
                            }
                            Spacer()
                            VStack(alignment: .leading) {
                                Text("Liabilities")
                                    .font(.caption2)
                                    .foregroundColor(Color.surface.opacity(0.7))
                                Text(viewModel.liabilitiesFormatted)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color.surface)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accent)
                    .cornerRadius(20)

                    // Quick Actions
                    HStack(spacing: 16) {
                        Spacer()
                        QuickActionButtonView(icon: "plus", label: "Expense")
                        Spacer()
                        QuickActionButtonView(icon: "arrow.triangle.2.circlepath", label: "Transfer")
                        Spacer()
                        QuickActionButtonView(icon: "person.2", label: "Settle Up")
                        Spacer()
                    }

                    // Accounts Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Accounts")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(Color.text)
                            Spacer()
                            Button(action: {}) {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(Color.text2)
                            }
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(viewModel.accounts, id: \.account.id) { acctWithBal in
                                    let balanceCents = acctWithBal.balance.amount
                                    let balanceFormatted = formatCents(balanceCents)
                                    PocketCard {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(acctWithBal.account.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(Color.text)
                                            Spacer()
                                            Text(balanceFormatted)
                                                .font(.headline)
                                                .fontWeight(.bold)
                                                .foregroundColor(balanceCents < 0 ? Color.accent : Color.positive)
                                        }
                                        .frame(width: 138, height: 68, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }

                    // Recent Activity Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Activity")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(Color.text)

                        ForEach(viewModel.recentTransactions) { txn in
                            RowTile(
                                title: txn.description,
                                subtitle: txn.date,
                                trailing: {
                                    Text(txn.amount)
                                        .font(.body)
                                        .fontWeight(.bold)
                                        .foregroundColor(txn.isIncome ? Color.positive : Color.text)
                                }
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Sanvya")
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
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.cancel()
        }
    }
    
    private func formatCents(_ cents: Int64) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "INR"
        fmt.maximumFractionDigits = 2
        fmt.locale = Locale(identifier: "en_IN")
        return fmt.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "₹0.00"
    }
}

struct QuickActionButtonView: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color.accent)
                .frame(width: 50, height: 50)
                .background(Color.surface)
                .clipShape(Circle())

            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(Color.text)
        }
    }
}

#Preview {
    DashboardView(isDrawerOpen: .constant(false))
}
