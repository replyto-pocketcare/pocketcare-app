import SwiftUI

struct BudgetUiItem: Identifiable {
    let id: String
    let name: String
    let period: String
    let spentFormatted: String
    let limitFormatted: String
    let progress: Double // 0.0 to 1.0+
    let categories: [String]
}

struct BudgetsView: View {
    @State private var showingCreateSheet = false

    let sampleBudgets = [
        BudgetUiItem(id: "1", name: "Monthly Dining Out", period: "monthly", spentFormatted: "₹6,400", limitFormatted: "₹8,000", progress: 0.80, categories: ["Food & Dining"]),
        BudgetUiItem(id: "2", name: "Groceries & Household", period: "monthly", spentFormatted: "₹11,200", limitFormatted: "₹15,000", progress: 0.74, categories: ["Groceries"]),
        BudgetUiItem(id: "3", name: "Entertainment & Leisure", period: "monthly", spentFormatted: "₹5,200", limitFormatted: "₹4,000", progress: 1.30, categories: ["Shopping", "Entertainment"]),
        BudgetUiItem(id: "4", name: "Fuel & Transport", period: "monthly", spentFormatted: "₹2,100", limitFormatted: "₹5,000", progress: 0.42, categories: ["Transport"])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(sampleBudgets) { budget in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(budget.name)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(Theme.ink)

                                    Text("\(budget.period.capitalized) • \(budget.categories.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(Theme.inkSoft)
                                }
                                Spacer()
                                BudgetStatusBadge(progress: budget.progress)
                            }

                            ProgressView(value: min(budget.progress, 1.0))
                                .tint(budget.progress > 1.0 ? Theme.terracotta : (budget.progress > 0.8 ? Color.orange : Theme.sage))
                                .scaleEffect(x: 1, y: 1.5, anchor: .center)
                                .padding(.vertical, 4)

                            HStack {
                                Text("Spent: \(budget.spentFormatted)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Theme.ink)
                                Spacer()
                                Text("Limit: \(budget.limitFormatted)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Theme.inkSoft)
                            }
                        }
                        .padding(18)
                        .background(Theme.cream)
                        .cornerRadius(16)
                    }
                }
                .padding(16)
            }
            .background(Theme.clay50.ignoresSafeArea())
            .navigationTitle("Budgets")
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
                CreateBudgetView()
            }
        }
    }
}

struct BudgetStatusBadge: View {
    let progress: Double

    var body: some View {
        let (label, bg, fg) = statusInfo

        Text(label)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .foregroundColor(fg)
            .cornerRadius(8)
    }

    private var statusInfo: (String, Color, Color) {
        if progress > 1.0 {
            return ("Over Budget", Theme.terracottaSoft, Theme.cream)
        } else if progress > 0.8 {
            return ("Near Limit", Color.orange.opacity(0.3), Theme.ink)
        } else {
            return ("On Track", Theme.sage.opacity(0.3), Theme.ink)
        }
    }
}

#Preview {
    BudgetsView()
}
