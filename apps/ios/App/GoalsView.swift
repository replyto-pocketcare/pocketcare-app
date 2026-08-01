import SwiftUI

struct GoalUiItem: Identifiable {
    let id: String
    let name: String
    let currentFormatted: String
    let targetFormatted: String
    let targetDate: String
    let progress: Double
}

struct CashflowUiItem: Identifiable {
    let id: String
    let title: String
    let amountFormatted: String
    let expectedDate: String
    let isIncome: Bool
    let status: String
}

struct GoalsView: View {
    @State private var selectedTab = 0 // 0: Goals, 1: Cashflow
    @State private var showingCreateSheet = false

    let sampleGoals = [
        GoalUiItem(id: "1", name: "Emergency Fund (6 Months)", currentFormatted: "₹3,50,000", targetFormatted: "₹5,00,000", targetDate: "Dec 2026", progress: 0.70),
        GoalUiItem(id: "2", name: "Japan Vacation", currentFormatted: "₹1,20,000", targetFormatted: "₹2,50,000", targetDate: "Oct 2027", progress: 0.48),
        GoalUiItem(id: "3", name: "MacBook Pro Upgrade", currentFormatted: "₹1,80,000", targetFormatted: "₹2,00,000", targetDate: "Mar 2027", progress: 0.90)
    ]

    let sampleCashflows = [
        CashflowUiItem(id: "1", title: "Annual Bonus", amountFormatted: "+₹1,50,000", expectedDate: "15 Aug 2026", isIncome: true, status: "planned"),
        CashflowUiItem(id: "2", title: "Health Insurance Premium", amountFormatted: "-₹24,000", expectedDate: "01 Sep 2026", isIncome: false, status: "planned"),
        CashflowUiItem(id: "3", title: "Fixed Deposit Maturity", amountFormatted: "+₹50,000", expectedDate: "10 Jul 2026", isIncome: true, status: "completed")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Section", selection: $selectedTab) {
                    Text("Goals").tag(0)
                    Text("Cashflow").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                ScrollView {
                    if selectedTab == 0 {
                        VStack(spacing: 14) {
                            ForEach(sampleGoals) { goal in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(goal.name)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .foregroundColor(Theme.ink)
                                        Spacer()
                                        Text("Target: \(goal.targetDate)")
                                            .font(.caption)
                                            .foregroundColor(Theme.inkSoft)
                                    }

                                    ProgressView(value: goal.progress)
                                        .tint(Theme.terracotta)
                                        .scaleEffect(x: 1, y: 1.5, anchor: .center)
                                        .padding(.vertical, 4)

                                    HStack {
                                        Text("Saved: \(goal.currentFormatted)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(Theme.sage)
                                        Spacer()
                                        Text("Goal: \(goal.targetFormatted)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(Theme.ink)
                                    }
                                }
                                .padding(18)
                                .background(Theme.cream)
                                .cornerRadius(16)
                            }
                        }
                        .padding(16)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(sampleCashflows) { cf in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(cf.title)
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundColor(Theme.ink)
                                        Text("Expected: \(cf.expectedDate)")
                                            .font(.caption)
                                            .foregroundColor(Theme.inkSoft)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(cf.amountFormatted)
                                            .font(.body)
                                            .fontWeight(.bold)
                                            .foregroundColor(cf.isIncome ? Theme.sage : Theme.terracotta)

                                        Text(cf.status.capitalized)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(cf.status == "completed" ? Theme.sage.opacity(0.3) : Theme.clay100)
                                            .cornerRadius(6)
                                    }
                                }
                                .padding(16)
                                .background(Theme.cream)
                                .cornerRadius(12)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Theme.clay50.ignoresSafeArea())
            .navigationTitle("Goals & Cashflow")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateSheet = true }) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(Theme.terracotta)
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateGoalView()
            }
        }
    }
}

#Preview {
    GoalsView()
}
